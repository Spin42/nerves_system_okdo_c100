#!/bin/bash
# Install build tools on L4T (Ubuntu 18.04) and build vkpeak.
# Run as the normal user; uses sudo for apt.
set -eu
PASS=${1:?password}
echo "$PASS" | sudo -S apt-get update -qq
echo "$PASS" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cmake g++ make git libvulkan-dev
cd "$HOME"
# Ubuntu 18.04's CMake 3.10 is too old for ncnn; Kitware's binaries run on it
CM=cmake-3.31.6-linux-aarch64
[ -x "$CM/bin/cmake" ] || { wget -q "https://github.com/Kitware/CMake/releases/download/v3.31.6/$CM.tar.gz" && tar xzf "$CM.tar.gz"; }
export PATH=$HOME/$CM/bin:$PATH
cmake --version | head -1
[ -d vkpeak ] || git clone --depth 1 https://github.com/nihui/vkpeak.git
cd vkpeak
git submodule update --init --depth 1
cd ncnn && git submodule update --init --depth 1 glslang && cd ..
rm -rf build && mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j4
ls -la vkpeak
