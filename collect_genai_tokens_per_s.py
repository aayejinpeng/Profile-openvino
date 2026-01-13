#!/usr/bin/env python3

import argparse
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable


_THROUGHPUT_RE = re.compile(
    r"Throughput:\s*"  # label
    r"(?P<val>[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"  # number
    r"(?:\s*±\s*(?P<std>[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?))?"  # optional std
    r"\s*tokens/s"
)


DEFAULT_SEQLENS: list[int] = [
    1,
    2,
    4,
    8,
    16,
    32,
    64,
    128,
    256,
    512,
    1024,
    2048,
    4096,
    8192,
    16384,
]


def parse_seqlens_arg(values: list[str]) -> list[int]:
    # Accept both comma-separated and space-separated forms.
    tokens: list[str] = []
    for v in values:
        tokens.extend([t for t in v.split(",") if t != ""])

    seqlens: list[int] = []
    seen: set[int] = set()
    for t in tokens:
        try:
            n = int(t)
        except ValueError as e:
            raise ValueError(f"Invalid seqlen: {t!r}") from e
        if n < 1:
            raise ValueError(f"seqlen must be >= 1, got {n}")
        if n not in seen:
            seen.add(n)
            seqlens.append(n)
    if not seqlens:
        raise ValueError("seqlens list is empty")
    return seqlens


def parse_throughput_tokens_per_s(output: str) -> float | None:
    matches = list(_THROUGHPUT_RE.finditer(output))
    if not matches:
        return None
    # Prefer the last printed throughput (usually the final summary).
    return float(matches[-1].group("val"))


def run_one(binary: Path, model_dir: Path, seqlen: int, cpu_core: str | None) -> tuple[float | None, str, int]:
    cmd: list[str] = []
    if cpu_core is not None and shutil.which("taskset"):
        cmd += ["taskset", "-c", str(cpu_core)]

    cmd += [str(binary), "-m", str(model_dir), "--yjp", str(seqlen)]

    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = proc.stdout or ""
    return parse_throughput_tokens_per_s(out), out, proc.returncode


def write_csv_matrix(
    out_csv: Path,
    models: list[str],
    rows: Iterable[tuple[int, dict[str, float | None]]],
) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_csv.with_suffix(out_csv.suffix + ".tmp")
    with tmp_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["seqlen", *models])
        for seqlen, values in rows:
            writer.writerow([seqlen, *[("" if values.get(m) is None else values[m]) for m in models]])
    tmp_path.replace(out_csv)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run benchmark_genai across seqlens and models and collect tokens/s.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--binary", type=Path, default=None, help="Path to benchmark_genai binary")
    parser.add_argument("--models", nargs="+", default=["a8w8", "f8e4m3", "nvfp4", "WOi4", "WOi8", "WOmxfp4", "WOnf4"])
    parser.add_argument(
        "--seqlens",
        nargs="+",
        default=None,
        help=(
            "Explicit seqlen list. Accepts comma-separated or space-separated values, e.g. "
            "--seqlens 1,2,4,8 or --seqlens 1 2 4 8. Overrides --max-seq."
        ),
    )
    # Keep the CLI minimal and explicit: either use --seqlens or default list.
    parser.add_argument("--cpu-core", default="0", help="CPU core list passed to taskset -c (set empty to disable taskset)")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    root: Path = args.root
    binary = args.binary or (root / "bin" / "samples_bin" / "benchmark_genai")
    out_csv = args.out or (root / "profile_log" / "genai_tokens_per_s.csv")

    if not binary.exists():
        print(f"ERROR: benchmark_genai not found: {binary}", file=sys.stderr)
        return 2

    cpu_core = args.cpu_core if args.cpu_core != "" else None

    try:
        seqlens = parse_seqlens_arg(args.seqlens) if args.seqlens is not None else DEFAULT_SEQLENS
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    rows: list[tuple[int, dict[str, float | None]]] = [
        (seqlen, {m: None for m in args.models}) for seqlen in seqlens
    ]

    # 先写一个“空表”，方便你在运行中实时打开观察
    write_csv_matrix(out_csv, args.models, rows)
    print(f"CSV initialized: {out_csv}")

    for seqlen, values in rows:
        print(f"=== seqlen={seqlen} ===")
        for model in args.models:
            model_dir = root / "model" / model
            if not model_dir.exists():
                print(f"WARN: model dir not found, skip: {model_dir}", file=sys.stderr)
                values[model] = None
                write_csv_matrix(out_csv, args.models, rows)
                print(f"CSV update: seqlen={seqlen}, model={model}, tokens/s=NA (missing model dir)")
                continue

            print(f"Running model={model} ...")
            tok_s, raw_out, rc = run_one(binary=binary, model_dir=model_dir, seqlen=seqlen, cpu_core=cpu_core)

            if rc != 0:
                print(f"WARN: benchmark_genai failed (model={model}, seqlen={seqlen}) rc={rc}", file=sys.stderr)

            if tok_s is None:
                print(
                    f"WARN: cannot parse Throughput tokens/s (model={model}, seqlen={seqlen}); output kept in stderr\n"
                    f"--- output begin ---\n{raw_out}\n--- output end ---\n",
                    file=sys.stderr,
                )

            values[model] = tok_s

            # 实时落盘：每完成一个点就更新 CSV，并输出新增值
            write_csv_matrix(out_csv, args.models, rows)
            pretty = "NA" if tok_s is None else f"{tok_s:.2f}"
            print(f"CSV update: seqlen={seqlen}, model={model}, tokens/s={pretty}")
            sys.stdout.flush()

    print(f"CSV final: {out_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
