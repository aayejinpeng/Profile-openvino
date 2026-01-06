执行`setup_env.sh`来获取openvino_genai和openvino

执行`get_all_model.sh`来获取所有量化模型,`./get_all_model.sh -m "meta-llama/Llama-3.2-1B-Instruct" -name "llama3.2-1B"`

执行`get_genai_profile.sh`来获取模型的perlayer的profile性能(genai)

执行`get_openvino_profile.sh`来获取模型的perlayer的profile性能(openvino)

执行`get_model_original_log.sh`来获取所有量化模型的单核seq=128的推理性能`./get_model_original_log.sh -m - -y 128 -c 0`

执行`get_onednn_profile.sh`来获取特定模型下，特定数据格式矩阵乘的onednn算子的性能，需要修改`onednn_test/llama3.2-1B`下的内容，并保存到`model/特定模型下`，根据自己需求修改其配置。`./get_onednn_profile.sh -m -`

