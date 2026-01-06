#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

usage() {
    cat << 'EOF'
Usage: get_model_original_log.sh [options]

Generate profile logs by running OpenVINO GenAI benchmark.

Options:
    -m, --model-name <name|- > Model folder name under $ROOT_DIR/model.
                                                        Use '-' to run ALL models under $ROOT_DIR/model.
  -o, --out-dir <dir>        Output directory for logs/csv.
                            Default: $ROOT_DIR/profile_log/genai
  -c, --cores <list>         taskset core list. Default: 0
  -y, --yjp <n>              --yjp value passed to benchmark_genai. Default: 128
  -h, --help                 Show this help.

Examples:
    ./get_model_original_log.sh -m -
    ./get_model_original_log.sh -m "llama3.2-1B"
EOF
}

MODELS_DIR_DEFAULT="$ROOT_DIR/model"
OUT_DIR_DEFAULT="$ROOT_DIR/profile_log"
CORE_LIST_DEFAULT="0"
YJP_DEFAULT="128"

MODEL_NAME=""
OUT_DIR="$OUT_DIR_DEFAULT"
CORE_LIST="$CORE_LIST_DEFAULT"
YJP="$YJP_DEFAULT"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model-name)
            MODEL_NAME="$2"; shift 2 ;;
        -o|--out-dir)
            OUT_DIR="$2"; shift 2 ;;
        -c|--cores)
            CORE_LIST="$2"; shift 2 ;;
        -y|--yjp)
            YJP="$2"; shift 2 ;;
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

MODELS_ROOT_DIR="$(readlink -f "$MODELS_DIR_DEFAULT")"
OUT_DIR="$(readlink -m "$OUT_DIR")"

mkdir -p "$ROOT_DIR/profile_log"

source "$ROOT_DIR/.venv/bin/activate"

# NOTE: install/setupvars.sh may reference unset variables; keep our script strict
# but temporarily disable nounset while sourcing it.
set +u
source "$ROOT_DIR/install/setupvars.sh"
set -u

mkdir -p "$OUT_DIR"

if [[ ! -d "$MODELS_ROOT_DIR" ]]; then
    echo "Models root dir not found: $MODELS_ROOT_DIR" >&2
    exit 1
fi

shopt -s nullglob

run_quant_dir() {
    local model_name="$1"
    local quant_name="$2"
    local quant_dir="$3"

    # local quant="${model_name}/${quant_name}"
    # label="${label}"
    mkdir -p "${OUT_DIR}/${model_name}"


    echo "Profiling model: ${MODELS_ROOT_DIR}/${model_name}/${quant_name}"
    echo "Output will be saved to $OUT_DIR/${model_name}/${quant_name}.csv"
    echo "Log will be saved to $OUT_DIR/${model_name}/${quant_name}.log"
    OV_CPU_VERBOSE=3 \
        taskset -c "$CORE_LIST" \
        "$ROOT_DIR/bin/samples_bin/benchmark_genai" \
        -m "$quant_dir" \
        --yjp "$YJP" \
        --log_file "$OUT_DIR/${model_name}/${quant_name}.csv" \
        > "$OUT_DIR/${model_name}/${quant_name}.log"
    echo "Completed profiling for model: ${MODELS_ROOT_DIR}/${model_name}/${quant_name}"
}

found_any=0

if [[ "$MODEL_NAME" == "-" ]]; then
    for model_base in "$MODELS_ROOT_DIR"/*; do
        [[ -d "$model_base" ]] || continue
        model_base_name="$(basename "$model_base")"

        for quant_dir in "$model_base"/*; do
            [[ -d "$quant_dir" ]] || continue
            xml_count=("$quant_dir"/*.xml)
            if [[ ${#xml_count[@]} -eq 0 ]]; then
                continue
            fi
            found_any=1
            quant_name="$(basename "$quant_dir")"
            run_quant_dir "$model_base_name" "$quant_name" "$quant_dir"
        done
    done
else
    target_model_dir="$MODELS_ROOT_DIR/$MODEL_NAME"
    if [[ ! -d "$target_model_dir" ]]; then
        echo "Model dir not found: $target_model_dir" >&2
        exit 1
    fi

    for quant_dir in "$target_model_dir"/*; do
        [[ -d "$quant_dir" ]] || continue
        xml_count=("$quant_dir"/*.xml)
        if [[ ${#xml_count[@]} -eq 0 ]]; then
            continue
        fi
        found_any=1
        quant_name="$(basename "$quant_dir")"
        run_quant_dir "$MODEL_NAME" "$quant_name" "$quant_dir"
    done
fi

if [[ $found_any -eq 0 ]]; then
    if [[ "$MODEL_NAME" == "-" ]]; then
        echo "No quantized model folders found under: $MODELS_ROOT_DIR" >&2
        echo "Expected structure: $MODELS_ROOT_DIR/<model>/<quant>/*.xml" >&2
    else
        echo "No quantized model folders found under: $MODELS_ROOT_DIR/$MODEL_NAME" >&2
        echo "Expected structure: $MODELS_ROOT_DIR/$MODEL_NAME/<quant>/*.xml" >&2
    fi
    exit 1
fi
