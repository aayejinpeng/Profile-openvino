import openvino_genai as ov_genai
import numpy as np
import argparse
import random
import string



def main():
    parser = argparse.ArgumentParser(description="Run OpenVINO GenAI pipeline")
    parser.add_argument(
        "--models_path",
        type=str,
        required=True,
        help="Path to the exported OpenVINO model directory"
    )
    args = parser.parse_args()

    # 使用命令行参数填充 models_path
    pipe = ov_genai.LLMPipeline(args.models_path, "CPU",config={"PERF_COUNT": "YES"})
    
    tokenizer = pipe.get_tokenizer()
    tokens = tokenizer.encode(["t"], pad_to_max_length=True, max_length=250)
    result = pipe.generate(tokens, max_new_tokens=1)
    for i in range(10):
        rand_str = ''.join(random.choices(string.ascii_lowercase, k=10000))
        tokens = tokenizer.encode([rand_str], pad_to_max_length=True, max_length=128)
        print("Token count:", tokens.input_ids.shape)
        result = pipe.generate(tokens, max_new_tokens=1)
        perf_metrics = result.perf_metrics
        print(f'Generate duration: {perf_metrics.get_generate_duration().mean:.2f} ms')
        print("input tokens:", perf_metrics.get_num_input_tokens())
        print("prefill tokens/s =", perf_metrics.get_num_input_tokens() / perf_metrics.get_generate_duration().mean*1000)
        print("End of profiling information")


if __name__ == "__main__":
    main()
