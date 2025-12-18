set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -m venv ./.venv
source ./.venv/bin/activate
pip install --upgrade pip
pip install openvino-genai==2025.4.0

echo "Environment setup complete. To activate the virtual environment, run 'source ./.venv/bin/activate'."

git clone git@github.com:aayejinpeng/openvino.genai.git
cd openvino.genai
git checkout yjp_profile_per_layer
git submodule update --init --recursive
pip install --requirement ./samples/export-requirements.txt

git clone git@github.com:aayejinpeng/openvino.git
cd openvino
git checkout 2025.4.0
git submodule update --init --recursive
cd ..

echo "Building OpenVINO"

cd openvino
sudo ./install_build_dependencies.sh
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --parallel
cd ..
cmake --install ./build --prefix ../install

echo "OpenVINO build and installation complete."
source ./install/setupvars.sh

cd openvino.genai
echo "Environment variables set up for OpenVINO GenAI."

cmake -DCMAKE_BUILD_TYPE=Release -S ./ -B ./build/
cmake --build ./build/ --config Release -j

echo "OpenVINO GenAI build complete."

echo "Install OpenVINO GenAI"
cmake --install ./build/ --config Release --prefix ../install
echo "OpenVINO GenAI installation complete."

echo "To use OpenVINO GenAI, build the samples located in the 'samples' directory."
cd ../install
cd samples
./build_samples.sh -i $SCRIPT_DIR/bin
echo "Sample build complete. You can now run the samples." 
