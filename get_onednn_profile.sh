#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

usage() {
	cat << 'EOF'
Usage: get_onednn_profile.sh [options]

Run OneDNN benchdnn profiling for exported OneDNN batches.

Required:
  -m, --model-name <name|->  Model folder name under ./model.
							Use '-' to run ALL models under ./model.

Optional:
  -o, --out-root <dir>       Output root dir (default: ./profile_log)
  -c, --cores <list>         taskset core list (default: 0)
  -h, --help                 Show this help.

Expected layout:
	model/<model>/onednn/<variant>   (each variant folder is used as --batch input)

Examples:
  ./get_onednn_profile.sh -m "llama3.2-1B"
  ./get_onednn_profile.sh -m - -c 0
EOF
}

MODELS_ROOT_DIR_DEFAULT="$ROOT_DIR/model"
OUT_ROOT_DEFAULT="$ROOT_DIR/profile_log"
CORE_LIST_DEFAULT="0"

MODEL_NAME=""
OUT_ROOT="$OUT_ROOT_DEFAULT"
CORE_LIST="$CORE_LIST_DEFAULT"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-m|--model-name)
			MODEL_NAME="$2"; shift 2 ;;
		-o|--out-root)
			OUT_ROOT="$2"; shift 2 ;;
		-c|--cores)
			CORE_LIST="$2"; shift 2 ;;
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

MODELS_ROOT_DIR="$(readlink -f "$MODELS_ROOT_DIR_DEFAULT")"
OUT_ROOT="$(readlink -m "$OUT_ROOT")"

BENCHDNN_BIN="$ROOT_DIR/bin/onednn_bench/benchdnn"
if [[ ! -x "$BENCHDNN_BIN" ]]; then
	echo "benchdnn not found or not executable: $BENCHDNN_BIN" >&2
	exit 1
fi

if [[ ! -d "$MODELS_ROOT_DIR" ]]; then
	echo "Models root dir not found: $MODELS_ROOT_DIR" >&2
	exit 1
fi

mkdir -p "$OUT_ROOT"

shopt -s nullglob

run_onednn_for_model() {
	local model_dir="$1"
	local model_base
	model_base="$(basename "$model_dir")"

	if [[ ! -d "$model_dir/onednn" ]]; then
		echo "WARN: onednn dir not found, skip: $model_dir/onednn" >&2
		return 0
	fi

	local found=0
	for variant_path in "$model_dir"/onednn/*; do
		[[ -e "$variant_path" ]] || continue
		found=1
		local variant
		variant="$(basename "$variant_path")"

		local out_csv="$OUT_ROOT/$model_base/onednn_${variant}.csv"
		mkdir -p "$(dirname "$out_csv")"

		echo "Profiling OneDNN: ${model_base}/onednn/${variant}"
		echo "Output will be saved to $out_csv"
		echo "CMD: taskset -c \"$CORE_LIST\" \"$BENCHDNN_BIN\" --mode=P --ip --batch=\"$variant_path\" > \"$out_csv\""
		taskset -c "$CORE_LIST" \
			"$BENCHDNN_BIN" --mode=P --ip --batch="$variant_path" \
			> "$out_csv"
		echo "OneDNN profiling complete: ${model_base}/onednn/${variant}"
	done

	if [[ $found -eq 0 ]]; then
		echo "WARN: no onednn variants found under: $model_dir/onednn" >&2
	fi
}

if [[ "$MODEL_NAME" == "-" ]]; then
	any=0
	for model_dir in "$MODELS_ROOT_DIR"/*; do
		[[ -d "$model_dir" ]] || continue
		any=1
		run_onednn_for_model "$model_dir"
	done
	if [[ $any -eq 0 ]]; then
		echo "No model folders found under: $MODELS_ROOT_DIR" >&2
		exit 1
	fi
else
	target_model_dir="$MODELS_ROOT_DIR/$MODEL_NAME"
	if [[ ! -d "$target_model_dir" ]]; then
		echo "Model dir not found: $target_model_dir" >&2
		exit 1
	fi
	run_onednn_for_model "$target_model_dir"
fi
