#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

usage() {
    cat << 'EOF'
Usage: get_genai_seq_token_per_s.sh [options]

Collect tokens/s across sequence lengths for quantized GenAI models.

Required:
  -m, --model-name <name|->  Model folder name under ./model.
                            Use '-' to run ALL models under ./model.

Optional:
  -o, --out-root <dir>       Output root dir (default: ./profile_log)
  -c, --cores <list>         taskset core list (default: 0)
  -dl, --default-seqlens <preset>  Use preset seqlen sequence:
                              log2: 1,2,4,8,...,16384 (default)
                              add128: 1,2,4,...,256,384,512,...,16384 (step 128 after 256)
  -l, --seqlens <list>       Explicit seqlens (comma-separated), overrides -dl
  -h, --help                 Show this help.

Model layouts supported:
    - flat:      model/<quant>/*.xml               -> output: profile_log/<quant>/genai_tokens_per_s.csv
    - two-level: model/<model>/<quant>/*.xml       -> output: profile_log/<model>/genai_tokens_per_s.csv (columns=quant)

Examples:
  ./get_genai_seq_token_per_s.sh -m -
  ./get_genai_seq_token_per_s.sh -m "llama3.2-1B" -s 16384 -c 0
EOF
}

MODELS_ROOT_DIR="$ROOT_DIR/model"
OUT_ROOT_DEFAULT="$ROOT_DIR/profile_log"
CORE_LIST_DEFAULT="0"
DEFAULT_SEQLENS_PRESET="log2"

MODEL_NAME=""
OUT_ROOT="$OUT_ROOT_DEFAULT"
CORE_LIST="$CORE_LIST_DEFAULT"
SEQLENS=""
DEFAULT_PRESET="$DEFAULT_SEQLENS_PRESET"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model-name)
            MODEL_NAME="$2"; shift 2 ;;
        -o|--out-root)
            OUT_ROOT="$2"; shift 2 ;;
        -c|--cores)
            CORE_LIST="$2"; shift 2 ;;
        -dl|--default-seqlens)
            DEFAULT_PRESET="$2"; shift 2 ;;
        -l|--seqlens)
            SEQLENS="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$MODEL_NAME" ]]; then
    echo "Missing required argument: -m/--model-name" >&2
    usage
    exit 2
fi

# Generate seqlen list: explicit -l overrides -dl preset
SEQLENS_SUFFIX=""
if [[ -n "$SEQLENS" ]]; then
    # User provided explicit -l
    SEQLENS_SUFFIX="custom"
else
    # Use -dl preset
    SEQLENS_SUFFIX="$DEFAULT_PRESET"
    case "$DEFAULT_PRESET" in
        log2)
            SEQLENS="1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384"
            ;;
        add128)
            # 1,2,4,8,16,32,64,128,256, then 384..16384 step 128
            base="1,2,4,8,16,32,64,128,256"
            seq_add128=""
            for ((i=384; i<=16384; i+=128)); do
                seq_add128="${seq_add128}${i},"
            done
            seq_add128="${seq_add128%,}"
            SEQLENS="${base},${seq_add128}"
            ;;
        *)
            echo "Unknown -dl preset: $DEFAULT_PRESET" >&2
            echo "Supported: log2, add128" >&2
            exit 2
            ;;
    esac
fi

mkdir -p "$ROOT_DIR/profile_log"

source "$ROOT_DIR/.venv/bin/activate"

# install/setupvars.sh may reference unset variables; avoid nounset failures.
nounset_was_on=0
case "$-" in
    *u*) nounset_was_on=1 ;;
esac
set +u
source "$ROOT_DIR/install/setupvars.sh"
if [[ $nounset_was_on -eq 1 ]]; then
    set -u
else
    set +u
fi

MODELS_ROOT_DIR="$(readlink -f "$MODELS_ROOT_DIR")"
OUT_ROOT="$(readlink -m "$OUT_ROOT")"

mkdir -p "$OUT_ROOT"

if [[ ! -d "$MODELS_ROOT_DIR" ]]; then
    echo "Models root dir not found: $MODELS_ROOT_DIR" >&2
    exit 1
fi

is_ov_export_dir() {
    local dir="$1"
    shopt -s nullglob
    local xmls=("$dir"/*.xml)
    shopt -u nullglob
    [[ ${#xmls[@]} -gt 0 ]]
}

run_group() {
    local group_name="$1"   # top-level folder name under model/
    shift
    local out_csv="$OUT_ROOT/${group_name//\//__}/genai_tokens_per_s_${SEQLENS_SUFFIX}.csv"
    mkdir -p "$(dirname "$out_csv")"

    local tmp_root
    tmp_root="$(mktemp -d -t genai_tokens_root.XXXXXX)"
    trap 'rm -rf "$tmp_root"' RETURN
    mkdir -p "$tmp_root/model"

    # Remaining args are pairs: <label> <path>
    declare -a labels=()
    while [[ $# -gt 0 ]]; do
        local label="$1"
        local path="$2"
        shift 2
        local safe_label
        safe_label="${label//\//__}"
        if [[ -e "$tmp_root/model/$safe_label" ]]; then
            echo "WARN: duplicate quant label in group '$group_name', skip: $safe_label" >&2
            continue
        fi
        ln -s "$path" "$tmp_root/model/$safe_label"
        labels+=("$safe_label")
    done

    if [[ ${#labels[@]} -eq 0 ]]; then
        echo "WARN: no quant dirs to run for group: $group_name" >&2
        return 0
    fi

    echo "Collecting tokens/s: $group_name -> $out_csv"
    cmd=(
        python "$ROOT_DIR/collect_genai_tokens_per_s.py"
        --root "$tmp_root"
        --binary "$ROOT_DIR/bin/samples_bin/benchmark_genai"
        --models "${labels[@]}"
        --seqlens "$SEQLENS"
        --cpu-core "$CORE_LIST"
        --out "$out_csv"
    )
    printf 'CMD:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
    "${cmd[@]}"
}

found_any=0

if [[ "$MODEL_NAME" == "-" ]]; then
    for top in "$MODELS_ROOT_DIR"/*; do
        [[ -d "$top" ]] || continue
        top_name="$(basename "$top")"

        if is_ov_export_dir "$top"; then
            # flat layout: treat as a group with a single "quant" (the folder itself)
            found_any=1
            run_group "$top_name" "$top_name" "$top"
            continue
        fi

        # two-level layout: group contains quant subdirs
        declare -a pairs=()
        for quant_dir in "$top"/*; do
            [[ -d "$quant_dir" ]] || continue
            if is_ov_export_dir "$quant_dir"; then
                found_any=1
                quant_name="$(basename "$quant_dir")"
                pairs+=("$quant_name" "$quant_dir")
            fi
        done
        if [[ ${#pairs[@]} -gt 0 ]]; then
            run_group "$top_name" "${pairs[@]}"
        fi
    done
else
    target="$MODELS_ROOT_DIR/$MODEL_NAME"
    if [[ ! -d "$target" ]]; then
        echo "Model dir not found: $target" >&2
        exit 1
    fi

    if is_ov_export_dir "$target"; then
        # flat: model/<name>/*.xml -> one-column CSV under profile_log/<name>/
        found_any=1
        run_group "$MODEL_NAME" "$MODEL_NAME" "$target"
    else
        # two-level: model/<name>/<quant>/*.xml -> multi-column CSV under profile_log/<name>/
        declare -a pairs=()
        for quant_dir in "$target"/*; do
            [[ -d "$quant_dir" ]] || continue
            if is_ov_export_dir "$quant_dir"; then
                found_any=1
                quant_name="$(basename "$quant_dir")"
                pairs+=("$quant_name" "$quant_dir")
            fi
        done
        if [[ ${#pairs[@]} -gt 0 ]]; then
            run_group "$MODEL_NAME" "${pairs[@]}"
        fi
    fi
fi

if [[ $found_any -eq 0 ]]; then
    echo "No quantized model folders found." >&2
    echo "Searched under: $MODELS_ROOT_DIR" >&2
    echo "Expected layout: model/<quant>/*.xml or model/<model>/<quant>/*.xml" >&2
    exit 1
fi
