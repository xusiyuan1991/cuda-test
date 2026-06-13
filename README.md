# cuda-test

CUDA / GPU 环境完整检测脚本，一键诊断 GPU 驱动、CUDA 工具链、深度学习框架等 19 项关键配置。

## 快速开始

```bash
chmod +x run.sh
./run.sh
```

## 检测项目

| # | 类别 | 检测内容 |
|---|------|---------|
| 1 | 系统基础信息 | 内核版本、CPU 架构、内存、磁盘、GCC/Make/CMake |
| 2 | NVIDIA 驱动 | nvidia-smi、驱动版本、GPU 信息、拓扑、持久化/计算模式 |
| 3 | CUDA Toolkit | nvcc、CUDA_HOME、头文件、库文件、多版本安装 |
| 4 | CUDA 核心库 | cuBLAS、cuFFT、cuSPARSE、cuRAND、cuSOLVER、NVRTC、NPP、nvJPEG 等 19 个库 |
| 5 | NVCC 编译测试 | Hello World Kernel、向量加法、SAXPY、带宽测试、cuBLAS SGEMM |
| 6 | Python 环境 | 解释器、pip、conda、venv、NumPy、PyCUDA |
| 7 | PyTorch | CUDA 可用性、GPU 属性、张量矩阵乘法性能 (4096×4096) |
| 8 | TensorFlow | GPU 识别、SGEMM 性能测试 |
| 9 | JAX | GPU 设备、矩阵乘法性能 |
| 10 | CuPy | GPU 设备发现、cuBLAS 矩阵乘法性能 |
| 11 | Numba | CUDA JIT 编译、Kernel 正确性验证 |
| 12 | RAPIDS | cuDF、cuML、cuDNN Python 绑定、RMM |
| 13 | 深度学习相关库 | ONNX Runtime、Transformers、vLLM、Flash Attention、bitsandbytes、xformers、Triton、OpenCV CUDA、scikit-learn |
| 14 | NCCL | 系统库检测、环境变量 |
| 15 | cuDNN | 系统库检测、版本号 |
| 16 | TensorRT | Python 绑定、系统库、trtexec |
| 17 | Docker / 容器 | docker、nvidia-container-toolkit、nvidia runtime |
| 18 | 环境变量 | CUDA_HOME、CUDA_VISIBLE_DEVICES、LD_LIBRARY_PATH 等 |
| 19 | 内核模块 | nvidia/nvidia_uvm/nvidia_drm 模块、/dev 设备节点 |

## 示例输出

```
╔══════════════════════════════════════════════╗
║       CUDA / GPU 环境完整检测脚本            ║
║            2026-06-13 12:00:00               ║
╚══════════════════════════════════════════════╝

┌──────────────────────────────────────────────┐
│ 1. 系统基础信息
└──────────────────────────────────────────────┘
  ✓  uname -r (内核版本)
  ✓  uname -m (CPU 架构)
  ✓  /etc/os-release 存在
  ...

╔══════════════════════════════════════════════╗
║              测试结果汇总                    ║
╚══════════════════════════════════════════════╝

  ✓  通过:  42
  ✗  失败:  0
  ⚠  警告:  3
```

## 依赖

- **必需**: Bash 4.0+
- **可选**: NVIDIA 驱动、CUDA Toolkit、nvcc、Python 3.8+、各深度学习框架

脚本会自动检测已安装的组件，未安装的会标记为警告或跳过。

## 相关

- [CUDA Toolkit 下载](https://developer.nvidia.com/cuda-downloads)
- [NVIDIA 驱动下载](https://www.nvidia.com/drivers)
- [PyTorch 安装](https://pytorch.org/get-started/locally/)