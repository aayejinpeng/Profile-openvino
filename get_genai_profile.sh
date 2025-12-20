#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

mkdir -p $ROOT_DIR/profile_log

source $ROOT_DIR/install/setupvars.sh

for model in a8w8 f8e4m3 nvfp4 WOi4 WOi8 WOmxfp4 WOnf4; do
    echo "Profiling model: $model"
    OV_CPU_VERBOSE=3 taskset -c 0 $ROOT_DIR/bin/samples_bin/benchmark_genai -m $ROOT_DIR/model/$model --yjp 128 --log_file $ROOT_DIR/profile_log/genai/$model.csv
    echo "Completed profiling for model: $model"
done
