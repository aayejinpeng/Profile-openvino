#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

mkdir -p $ROOT_DIR/profile_log

source $ROOT_DIR/.venv/bin/activate
source $ROOT_DIR/install/setupvars.sh

echo "Collecting tokens/s across seqlens -> $ROOT_DIR/profile_log/genai_tokens_per_s.csv"
python $ROOT_DIR/collect_genai_tokens_per_s.py \
    --root $ROOT_DIR \
    --models a8w8 f8e4m3 nf4 WOi4 WOi8 WOmxfp4 WOnf4 \
    --max-seq 16384 \
    --cpu-core 0 \
    --out $ROOT_DIR/profile_log/genai_tokens_per_s.csv
