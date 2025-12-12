python3 -m venv ./.venv
source ./.venv/bin/activate
pip install --upgrade pip
pip install openvino-genai==2025.4.0

echo "Environment setup complete. To activate the virtual environment, run 'source ./.venv/bin/activate'."

git clone git@github.com:openvinotoolkit/openvino.genai.git
cd openvino.genai
git checkout v2025.4.0
pip install --requirement ./samples/export-requirements.txt

