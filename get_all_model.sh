#!/bin/bash
set -euo pipefail

# Get the directory where this script is located
T_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR=$T_DIR

usage() {
        cat << 'EOF'
Usage: get_all_model.sh [options]

Export one base HF model into multiple OpenVINO quant formats under ./model/<ORIGINAL_MODEL_NAME>/...

Options:
    -m, --model <name>   HuggingFace model id/name (default: meta-llama/Llama-3.2-1B-Instruct)
    -name, --name <dir>  Output directory name under ./model (default: derived from model id)
    -h, --help           Show this help.

Also supported:
    ORIGINAL_MODEL_NAME environment variable overrides the default.

Examples:
    ./get_all_model.sh
    ./get_all_model.sh -m "meta-llama/Llama-3.2-1B-Instruct"
    ./get_all_model.sh -m "meta-llama/Llama-3.2-1B-Instruct" -name "llama3.2-1B"
    ORIGINAL_MODEL_NAME="Qwen/Qwen2.5-1.5B-Instruct" ./get_all_model.sh
EOF
}

# Create model folder
mkdir -p "$SCRIPT_DIR/model"

ORIGINAL_MODEL_NAME_DEFAULT="meta-llama/Llama-3.2-1B-Instruct"
ORIGINAL_MODEL_NAME="${ORIGINAL_MODEL_NAME:-$ORIGINAL_MODEL_NAME_DEFAULT}"

# Optional output folder name override
MODEL_DIR_NAME="${MODEL_DIR_NAME:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--model)
            ORIGINAL_MODEL_NAME="$2"; shift 2 ;;
        -name|--name)
            MODEL_DIR_NAME="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$MODEL_DIR_NAME" ]]; then
    # Default: replace '/' with '__' so it's a safe folder name.
    MODEL_DIR_NAME="${ORIGINAL_MODEL_NAME//\//__}"
fi

mkdir -p "$SCRIPT_DIR/model/$MODEL_DIR_NAME"
# Export model with optimum-cli
optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --quant-mode int8 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/a8w8"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --quant-mode nf4_f8e4m3 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/nf4"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --quant-mode f8e4m3 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/f8e4m3"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --weight-format nf4 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/WOnf4"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --weight-format mxfp4 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/WOmxfp4"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --weight-format int4 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/WOi4"

optimum-cli export openvino \
    --model "$ORIGINAL_MODEL_NAME" \
    --weight-format int8 \
    "$SCRIPT_DIR/model/$MODEL_DIR_NAME/WOi8"

