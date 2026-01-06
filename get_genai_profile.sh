#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

mkdir -p $ROOT_DIR/profile_log

source $ROOT_DIR/.venv/bin/activate
source $ROOT_DIR/install/setupvars.sh

for model in a8w8 f8e4m3 nf4 WOi4 WOi8 WOmxfp4 WOnf4; do
    mkdir -p $ROOT_DIR/profile_log/
    echo "Profiling model: $model"
    OV_CPU_VERBOSE=3 taskset -c 0 $ROOT_DIR/bin/samples_bin/benchmark_genai -m $ROOT_DIR/model/$model --yjp 128 --log_file $ROOT_DIR/profile_log/genai/$model.csv > $ROOT_DIR/profile_log/genai/$model.log
    echo "Completed profiling for model: $model"
done
