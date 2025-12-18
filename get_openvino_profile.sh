#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

mkdir -p $ROOT_DIR/profile_log

source $ROOT_DIR/install/setupvars.sh

for model in a8w8 f8e4m3 nvfp4 WOi4 WOi8 WOmxfp4 WOnf4; do
    echo "Profiling model: $model"
    taskset -c 0 python $ROOT_DIR/test_base_openvino.py --model $ROOT_DIR/model/$model/openvino_model.xml  --batch_size 1 --output $ROOT_DIR/profile_log/base/$model
    echo "Completed profiling for model: $model"
done