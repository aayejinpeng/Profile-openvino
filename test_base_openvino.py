import time
import numpy as np
import openvino as ov
import csv
from collections import defaultdict
import argparse
import os

def main():
    parser = argparse.ArgumentParser(description="Run OpenVINO model profiling")
    parser.add_argument(
        "--model", 
        type=str, 
        required=True, 
        help="Path to OpenVINO IR model XML file (e.g. /path/to/model.xml)"
    )
    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="Path to save CSV file (default: diff_per_layer.csv in current directory)"
    )
    parser.add_argument(
        "--batch_size",
        type=int,
        required=True,
        help="Number of samples per inference run"
    )
    args = parser.parse_args()

    # 1. 初始化 OpenVINO
    core = ov.Core()
    model = core.read_model(args.model)

    # 2. 编译模型时开启性能计数
    compiled_model = core.compile_model(model, "CPU", {"PERF_COUNT": "YES"})

    # 3. 准备 Prefill 输入
    seq_len = 128
    batch_size = args.batch_size
    random_range = 100

    input_ids = np.random.randint(0, 1, size=(batch_size, seq_len), dtype=np.int64)
    attention_mask = np.ones((batch_size, seq_len), dtype=np.int64)
    position_ids = np.arange(seq_len, dtype=np.int64).reshape(1, -1)
    beam_idx = np.array(range(batch_size), dtype=np.int32)

    inputs = {
        "input_ids": input_ids,
        "attention_mask": attention_mask,
        "position_ids": position_ids,
        "beam_idx": beam_idx,
    }

    # 4. warm up
    print("warm up")
    for run_idx in range(1,10):
        start_time = time.time()
        infer_request = compiled_model.create_infer_request()
        _ = infer_request.infer(inputs)
        end_time = time.time()
        print(f"Run {run_idx + 1}/{10} completed in {end_time - start_time:.4f} seconds")
        # perf_counts = infer_request.get_profiling_info()
        # for perf in perf_counts:
        #     layer_times[perf.node_name].append(perf.cpu_time.microseconds)

    # 5. 收集性能数据
    layer_times = defaultdict(list)  # {layer_name: [time1, time2, ...]}

    for run_idx in range(1,2):
        infer_request = compiled_model.create_infer_request()
        start_time = time.time()
        _ = infer_request.infer(inputs)
        end_time = time.time()
        print(f"Run {run_idx + 1}/{1} completed in {end_time - start_time:.4f} seconds")
        perf_counts = infer_request.get_profiling_info()
        for perf in perf_counts:
            layer_times[perf.node_name].append(perf.cpu_time.microseconds)

    # 6. 写入 CSV 文件
    csv_file = args.output + "_seqlen_" + str(seq_len) + ".csv"
    os.makedirs(os.path.dirname(csv_file), exist_ok=True) if os.path.dirname(csv_file) else None

    with open(csv_file, "w", newline="") as f:
        writer = csv.writer(f)
        # 写表头
        header = ["Layer"] + [f"Run_{i+1}" for i in range(0)]
        writer.writerow(header)
        # 写每行
        for layer, times in layer_times.items():
            row = [layer] + times
            writer.writerow(row)

    print(f"CSV file saved to {os.path.abspath(csv_file)}")

if __name__ == "__main__":
    main()
