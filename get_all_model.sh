#!/bin/bash

# Get the directory where this script is located
T_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR=$T_DIR

# Create model folder
mkdir -p "$SCRIPT_DIR/model"

# Export model with optimum-cli
optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct \
    --quant-mode int8 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/a8w8"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct \
    --quant-mode nf4_f8e4m3 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/nvfp4"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct \
    --quant-mode f8e4m3 \
    --dataset wikitext2 \
    "$SCRIPT_DIR/model/f8e4m3"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct 
    --weight-format nf4 \
    "$SCRIPT_DIR/model/WOnf4"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct 
    --weight-format mxfp4 \
    "$SCRIPT_DIR/model/WOmxfp4"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct 
    --weight-format int4 \
    "$SCRIPT_DIR/model/WOi4"

optimum-cli export openvino \
    --model meta-llama/Llama-3.2-1B-Instruct 
    --weight-format int8 \
    "$SCRIPT_DIR/model/WOi8"

