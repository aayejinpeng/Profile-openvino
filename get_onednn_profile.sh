#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR=$SCRIPT_DIR

mkdir -p $ROOT_DIR/profile_log

source $ROOT_DIR/.venv/bin/activate
source $ROOT_DIR/install/setupvars.sh

echo "Profiling OneDNN benchmark for A16 model"
echo "Output will be saved to $ROOT_DIR/profile_log/onednn_a16.csv"
taskset -c 0 $ROOT_DIR/bin/onednn_bench/benchdnn --mode=P --ip  --batch=$ROOT_DIR/onednn_test/llama3.2_1B_a16 > $ROOT_DIR/profile_log/onednn_a16.csv
echo "OneDNN profiling for A16 model complete."

echo "Profiling OneDNN benchmark for A8 model"
echo "Output will be saved to $ROOT_DIR/profile_log/onednn_a8.csv"
taskset -c 0 $ROOT_DIR/bin/onednn_bench/benchdnn --mode=P --ip  --batch=$ROOT_DIR/onednn_test/llama3.2_1B_a8 > $ROOT_DIR/profile_log/onednn_a8.csv
echo "OneDNN profiling for A8 model complete."
