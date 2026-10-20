#!/bin/bash
# Install build tools on L4T (Ubuntu 18.04) and build vkpeak.
# Run as the normal user; uses sudo for apt.
set -eu
PASS=${1:?password}
echo "$PASS" | sudo -S apt-get update -qq
echo "$PASS" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cmake g++ make git libvulkan-dev
cd "$HOME"
[ -d vkpeak ] || git clone --depth 1 https://github.com/nihui/vkpeak.git
cd vkpeak
git submodule update --init --depth 1
cd ncnn && git submodule update --init --depth 1 glslang && cd ..
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j4
ls -la vkpeak
