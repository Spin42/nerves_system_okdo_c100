# AI use cases on the C100 (2026-10-23)

The three nerves_ai use cases (LLM, speech to text, object detection) and the
stereo matcher, measured on the C100 running this system, each on the four
Cortex-A57 cores and, where the engine has a Vulkan backend, on the GM20B
through NVK. The engines are the upstream native tools, cross-compiled with
this system's toolchain and run as plain processes from `/root/ai` under the
GPU-error guard of the `c100_gpu` library (zero GPU errors and no new kernel
messages in every run). Nothing in the firmware changed; boot
`7e00fbd3-bd8e-4566-a4b8-937d93537b53`, slot B, normal governors, EMC 1600 MHz.

| Use case | CPU, 4 threads | GPU (NVK) | GPU gain |
|---|---:|---:|---:|
| LLM, TinyLlama 1.1B Q4_K_M, llama.cpp: generation | 1.03 tok/s | 4.34 tok/s | 4.2x |
| LLM, same, prompt processing (32 tokens) | 7.0 tok/s | 7.1 tok/s | none |
| LLM, TinyLlama 1.1B Q4_0: generation / prompt | 0.96 / 16.5 tok/s | 3.94 / 18.3 tok/s | 4.1x / 1.1x |
| Speech, whisper.cpp tiny.en f16, 11 s JFK clip | 10.2 s (encode 7.4 s) | 4.3 s (encode 1.5 s) | 2.4x |
| Speech, whisper.cpp tiny.en q8_0 | 6.0 s (encode 4.2 s) | 3.5 s (encode 1.6 s) | 1.7x |
| Vision, YOLOv5s 640x640, OpenCV DNN 4.10 | 931 ms per frame | no Vulkan backend | |
| Vision, YOLOv5s 640x640, ncnn c189d88 | 453 ms per frame | 1183 ms (fp16), 1561 ms (fp32) | 0.38x |
| Vision, YOLOv5s 640x640, IREE 3.13 compiled graph (padded, tuned, fp16 with f16 accumulators) | n/a | 458 ms (fp32: 589 ms) | 0.99x of ncnn CPU |
| Stereo SGBM 640x480 D64, our Vulkan kernels (OpenCV module / NxIREE graph) | 15.0 FPS (OpenCV CPU 3WAY) | 42.8 / 49.6 FPS | 2.9-3.3x |

Both whisper runs transcribed the clip correctly; the LLM produced the same
coherent continuation on CPU and GPU. The speech result on the GPU (0.32-0.39x
real time) is better than the phone's CPU result recorded for nerves_ai
(0.62-0.66x); LLM generation on this board's CPU is far below that phone
(1 against 6.3 tokens/s: fewer, slower, ARMv8.0 cores), and the GPU brings
it to 4 tokens/s. Three models loaded together fit comfortably (3.5 GB free of
4 GB at idle). Memory and CPU clock were checked: generation runs at the
maximum 1479 MHz under schedutil, and switching to the performance governor
changes nothing, so the CPU figures are compute-bound.

## What the GPU does and does not help

* ggml's Vulkan backend (llama.cpp, whisper.cpp) runs on NVK without changes:
  `fp16: 1`, warp size 32, no integer dot product or matrix cores. Matrix-vector
  work (token generation, the whisper encoder) gains 2-4x; batched prompt
  processing does not, since its matmul shaders have no fast path on Maxwell.
* ncnn's Vulkan path loses to its own NEON path for YOLOv5s on this GPU, in
  fp16 and in fp32; convolution networks are not a win here.
* OpenCV DNN has no Vulkan path for these models; the hand-written stereo
  kernels remain the strongest GPU case on this board.
* IREE compiles YOLOv5s to a working Vulkan graph once im2col convolutions
  with channels-last preprocessing, two padded tensor dimensions and a
  per-family tuning spec are used. In fp16 with f16 accumulators it uses
  the GM20B's packed HFMA2 (NAK/NVK patches 0008 and 0009) and reaches
  458 ms, level with ncnn on the CPU and 2.6x faster than ncnn's Vulkan
  path on NVK; without f16 accumulators the importer keeps f32 FMAs and
  fp16 is slower than fp32. The recipe is vendor-neutral, in
  `nx_iree/bench/yolo`; only the GM20B specs are in `c100_gpu`.
* NVIDIA's own stack is still well ahead: ncnn's Vulkan path on the L4T
  driver runs YOLOv5s at about 5 FPS on 640x480 inputs (Qengineering), about
  4.5x faster per pixel than the same shaders on NVK, and TensorRT fp16 is
  reported at roughly 60-100 ms at 640. That gap lies in NAK's Maxwell code
  generation and NVK, which is where further YOLO speed has to come from.

## Reproduction

Sources: llama.cpp and whisper.cpp master of 2026-10-23, ncnn c189d88 (the
tree used for the NVK layer tests), OpenCV 4.10.0. Models: TheBloke's
TinyLlama-1.1B-Chat-v1.0 Q4_K_M and Q4_0, ggerganov's `ggml-tiny.en.bin` and
`ggml-tiny.en-q8_0.bin`, ultralytics `yolov5s.onnx` (v7.0) and the ncnn
`yolov5s.param/bin` from ncnn-android-yolov5 (needs the example's custom
`YoloV5Focus` layer), `samples/jfk.wav` from whisper.cpp and `bus.jpg` from
yolov5.

ggml with the Vulkan backend, cross-compiled against this system's sysroot
(host needs `glslc` and the `spirv-headers` package; pass its config directory
and its include directory because the cross sysroot has neither):

```sh
A=.nerves/artifacts/nerves_system_okdo_c100-portable-0.1.0
CXX="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O2 -g2 -D_FORTIFY_SOURCE=1 -isystem /path/with/spirv/unified1"
cmake -S llama.cpp -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=$A/host/share/buildroot/toolchainfile.cmake \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="$CXX" -DGGML_VULKAN=ON -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8-a -DVulkan_GLSLC_EXECUTABLE=/usr/bin/glslc \
  -DSPIRV-Headers_DIR=/usr/lib/x86_64-linux-gnu/cmake/SPIRV-Headers -DLLAMA_CURL=OFF \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"
ninja -C build llama-bench llama-simple
```

Setting `CMAKE_CXX_FLAGS` replaces Buildroot's default flags, so the `-O2`
must be repeated: without it every C++ file (the Vulkan backend and ggml's
C++ CPU kernels) compiles unoptimized, and CPU generation drops to the same
1 token/s while the whisper encoder takes 52 s instead of 7 s. whisper.cpp
takes the same options (`whisper-cli`, `whisper-bench`); ncnn was built with
`NCNN_VULKAN=ON NCNN_BUILD_EXAMPLES=ON NCNN_SIMPLEOCV=ON` and a minimal static
OpenCV (core, imgproc, calib3d, dnn, imgcodecs, bundled protobuf, jpeg and
png) with the same toolchain file for the DNN benchmark, as in
`opencv_vkstereo/scripts/build-jetson.sh`.

On the board, `llama-bench -m model -ngl 0|99 -t 4 -p 32 -n 16`,
`whisper-cli -m model -f jfk.wav -t 4 [-ng] -nt`, the small ncnn and OpenCV
DNN timing programs and the guard runner `ai.exs` are kept with the run logs
(`r83` to `r89`) under `~/.cache/stereo-bench/nvidia-parity-20261022/lean/`
and in the durable experiment archive.
