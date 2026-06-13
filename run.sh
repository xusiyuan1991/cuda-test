#!/bin/bash
# GPU/CUDA 环境测试脚本
# 测试 nvcc, nvidia-smi, Python GPU 库等

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

check() {
    local name="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[PASS]${NC} $name"
        ((pass_count++))
    else
        echo -e "  ${RED}[FAIL]${NC} $name"
        ((fail_count++))
    fi
}

echo "============================================"
echo "  CUDA / GPU 环境测试"
echo "============================================"
echo ""

# ---- 1. 基础环境 ----
echo -e "${YELLOW}[1] 基础环境检查${NC}"
check "Linux 内核版本" uname -r
check "OS 发行版" cat /etc/os-release
echo "  uname -a: $(uname -a)"
echo ""

# ---- 2. NVIDIA 驱动 & nvidia-smi ----
echo -e "${YELLOW}[2] NVIDIA 驱动 & nvidia-smi${NC}"
if command -v nvidia-smi &> /dev/null; then
    echo -e "  ${GREEN}[PASS]${NC} nvidia-smi 可用"
    ((pass_count++))
    nvidia-smi --query-gpu=name,driver_version,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader | while IFS=, read -r name driver mem util temp; do
        echo "  GPU: $name"
        echo "  驱动版本: $driver"
        echo "  显存: $mem"
        echo "  GPU 利用率: $util"
        echo "  温度: $temp"
    done
    echo ""
    echo "  --- nvidia-smi 完整输出 (前 30 行) ---"
    nvidia-smi | head -30
else
    echo -e "  ${RED}[FAIL]${NC} nvidia-smi 不可用 — 未安装 NVIDIA 驱动或不在 PATH 中"
    ((fail_count++))
fi
echo ""

# ---- 3. NVCC 编译器 ----
echo -e "${YELLOW}[3] NVCC (NVIDIA CUDA Compiler)${NC}"
if command -v nvcc &> /dev/null; then
    echo -e "  ${GREEN}[PASS]${NC} nvcc 可用"
    ((pass_count++))
    echo "  路径: $(which nvcc)"
    echo "  版本:"
    nvcc --version
else
    echo -e "  ${RED}[FAIL]${NC} nvcc 不可用"
    ((fail_count++))
fi
echo ""

# ---- 4. NVCC 编译测试 ----
echo -e "${YELLOW}[4] NVCC 编译测试${NC}"
CUDA_SRC=$(mktemp /tmp/cuda_test_XXXX.cu)
CUDA_OUT=$(mktemp /tmp/cuda_test_XXXX)

cat > "$CUDA_SRC" << 'EOF'
#include <stdio.h>
#include <cuda_runtime.h>

__global__ void hello_cuda() {
    printf("Hello from GPU block %d, thread %d!\n", blockIdx.x, threadIdx.x);
}

int main() {
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    printf("CUDA 设备数量: %d\n", deviceCount);

    for (int i = 0; i < deviceCount; i++) {
        cudaDeviceProp prop;
        cudaGetDeviceProperties(&prop, i);
        printf("设备 %d: %s\n", i, prop.name);
        printf("  计算能力: %d.%d\n", prop.major, prop.minor);
        printf("  SM 数量: %d\n", prop.multiProcessorCount);
        printf("  全局内存: %.2f GB\n", prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
        printf("  最大线程数/块: %d\n", prop.maxThreadsPerBlock);
    }

    if (deviceCount > 0) {
        hello_cuda<<<2, 4>>>();
        cudaDeviceSynchronize();
    }

    printf("NVCC 编译测试通过!\n");
    return 0;
}
EOF

if command -v nvcc &> /dev/null; then
    if nvcc -o "$CUDA_OUT" "$CUDA_SRC" 2>&1; then
        echo -e "  ${GREEN}[PASS]${NC} NVCC 编译成功"
        ((pass_count++))
        echo "  --- 运行编译产物 ---"
        "$CUDA_OUT" 2>&1 || true
    else
        echo -e "  ${RED}[FAIL]${NC} NVCC 编译失败"
        ((fail_count++))
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} nvcc 不可用，跳过编译测试"
fi
rm -f "$CUDA_SRC" "$CUDA_OUT"
echo ""

# ---- 5. Python 环境 ----
echo -e "${YELLOW}[5] Python 环境${NC}"
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo -e "  ${RED}[FAIL]${NC} Python 不可用"
    ((fail_count++))
    PYTHON=""
fi

if [ -n "$PYTHON" ]; then
    echo -e "  ${GREEN}[PASS]${NC} Python 可用: $($PYTHON --version 2>&1)"
    ((pass_count++))
    echo "  路径: $(which $PYTHON)"
fi
echo ""

# ---- 6. PyTorch GPU 测试 ----
echo -e "${YELLOW}[6] PyTorch GPU 测试${NC}"
if [ -n "$PYTHON" ]; then
    PYTORCH_OUT=$($PYTHON -c "
try:
    import torch
    print('PyTorch 版本:', torch.__version__)
    print('CUDA 可用:', torch.cuda.is_available())
    if torch.cuda.is_available():
        print('CUDA 版本:', torch.version.cuda)
        print('cuDNN 版本:', torch.backends.cudnn.version())
        print('GPU 设备数量:', torch.cuda.device_count())
        for i in range(torch.cuda.device_count()):
            print(f'  GPU {i}: {torch.cuda.get_device_name(i)}')
            props = torch.cuda.get_device_properties(i)
            print(f'    计算能力: {props.major}.{props.minor}')
            print(f'    总显存: {props.total_mem / 1024**3:.2f} GB')
        # 简单张量运算测试
        x = torch.randn(1000, 1000).cuda()
        y = torch.randn(1000, 1000).cuda()
        z = torch.mm(x, y)
        print('GPU 矩阵乘法测试通过! (1000x1000)')
    else:
        print('CUDA 不可用，跳过 GPU 测试')
except ImportError:
    print('IMPORT_ERROR: PyTorch 未安装')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    echo "$PYTORCH_OUT" | while IFS= read -r line; do echo "  $line"; done
    if echo "$PYTORCH_OUT" | grep -q "IMPORT_ERROR"; then
        echo -e "  ${YELLOW}[SKIP]${NC} PyTorch 未安装"
    elif echo "$PYTORCH_OUT" | grep -q "ERROR:"; then
        echo -e "  ${RED}[FAIL]${NC} PyTorch 测试出错"
        ((fail_count++))
    elif echo "$PYTORCH_OUT" | grep -q "GPU 矩阵乘法测试通过"; then
        echo -e "  ${GREEN}[PASS]${NC} PyTorch GPU 测试通过"
        ((pass_count++))
    elif echo "$PYTORCH_OUT" | grep -q "CUDA 不可用"; then
        echo -e "  ${YELLOW}[WARN]${NC} PyTorch 已安装但 CUDA 不可用"
    else
        echo -e "  ${GREEN}[PASS]${NC} PyTorch 可用"
        ((pass_count++))
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} Python 不可用，跳过 PyTorch 测试"
fi
echo ""

# ---- 7. TensorFlow GPU 测试 ----
echo -e "${YELLOW}[7] TensorFlow GPU 测试${NC}"
if [ -n "$PYTHON" ]; then
    TF_OUT=$($PYTHON -c "
try:
    import tensorflow as tf
    print('TensorFlow 版本:', tf.__version__)
    gpus = tf.config.list_physical_devices('GPU')
    print('GPU 设备数量:', len(gpus))
    for gpu in gpus:
        print(' ', gpu)
    if gpus:
        with tf.device('/GPU:0'):
            a = tf.random.normal([1000, 1000])
            b = tf.random.normal([1000, 1000])
            c = tf.matmul(a, b)
        print('GPU 矩阵乘法测试通过! (1000x1000)')
except ImportError:
    print('IMPORT_ERROR: TensorFlow 未安装')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    echo "$TF_OUT" | while IFS= read -r line; do echo "  $line"; done
    if echo "$TF_OUT" | grep -q "IMPORT_ERROR"; then
        echo -e "  ${YELLOW}[SKIP]${NC} TensorFlow 未安装"
    elif echo "$TF_OUT" | grep -q "ERROR:"; then
        echo -e "  ${RED}[FAIL]${NC} TensorFlow 测试出错"
        ((fail_count++))
    elif echo "$TF_OUT" | grep -q "GPU 矩阵乘法测试通过"; then
        echo -e "  ${GREEN}[PASS]${NC} TensorFlow GPU 测试通过"
        ((pass_count++))
    else
        echo -e "  ${GREEN}[PASS]${NC} TensorFlow 可用"
        ((pass_count++))
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} Python 不可用，跳过 TensorFlow 测试"
fi
echo ""

# ---- 8. CuPy GPU 测试 ----
echo -e "${YELLOW}[8] CuPy GPU 测试${NC}"
if [ -n "$PYTHON" ]; then
    CUPY_OUT=$($PYTHON -c "
try:
    import cupy as cp
    print('CuPy 版本:', cp.__version__)
    print('CUDA 版本:', cp.cuda.runtime.runtimeGetVersion())
    print('GPU 设备数量:', cp.cuda.runtime.getDeviceCount())
    for i in range(cp.cuda.runtime.getDeviceCount()):
        with cp.cuda.Device(i):
            props = cp.cuda.runtime.getDeviceProperties(i)
            print(f'  GPU {i}: {props[\"name\"].decode()}')
            print(f'    总显存: {props[\"totalGlobalMem\"] / 1024**3:.2f} GB')
    x = cp.random.randn(1000, 1000)
    y = cp.random.randn(1000, 1000)
    z = cp.dot(x, y)
    print('GPU 矩阵乘法测试通过! (1000x1000)')
except ImportError:
    print('IMPORT_ERROR: CuPy 未安装')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    echo "$CUPY_OUT" | while IFS= read -r line; do echo "  $line"; done
    if echo "$CUPY_OUT" | grep -q "IMPORT_ERROR"; then
        echo -e "  ${YELLOW}[SKIP]${NC} CuPy 未安装"
    elif echo "$CUPY_OUT" | grep -q "ERROR:"; then
        echo -e "  ${RED}[FAIL]${NC} CuPy 测试出错"
        ((fail_count++))
    elif echo "$CUPY_OUT" | grep -q "GPU 矩阵乘法测试通过"; then
        echo -e "  ${GREEN}[PASS]${NC} CuPy GPU 测试通过"
        ((pass_count++))
    else
        echo -e "  ${GREEN}[PASS]${NC} CuPy 可用"
        ((pass_count++))
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} Python 不可用，跳过 CuPy 测试"
fi
echo ""

# ---- 9. CUDA 工具链版本 ----
echo -e "${YELLOW}[9] CUDA 工具链版本${NC}"
CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
if [ -d "$CUDA_HOME" ]; then
    echo -e "  ${GREEN}[PASS]${NC} CUDA_HOME: $CUDA_HOME"
    ((pass_count++))
    if [ -f "$CUDA_HOME/version.txt" ]; then
        echo "  CUDA 版本文件: $(cat $CUDA_HOME/version.txt)"
    fi
    if [ -f "$CUDA_HOME/include/cuda.h" ]; then
        echo "  cuda.h 存在"
    fi
else
    echo -e "  ${YELLOW}[WARN]${NC} CUDA_HOME ($CUDA_HOME) 不存在"
fi

echo "  \$PATH 中的 CUDA 相关路径:"
echo "$PATH" | tr ':' '\n' | grep -i cuda || echo "  (无)"
echo ""

# ---- 10. 环境变量检查 ----
echo -e "${YELLOW}[10] CUDA 环境变量${NC}"
echo "  CUDA_HOME: ${CUDA_HOME:-未设置}"
echo "  CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-未设置 (默认全部可见)}"
echo "  LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-未设置}"
echo ""

# ---- 汇总 ----
echo "============================================"
echo "  测试结果汇总"
echo "============================================"
echo -e "  通过: ${GREEN}${pass_count}${NC}"
echo -e "  失败: ${RED}${fail_count}${NC}"
echo ""

if [ "$fail_count" -eq 0 ]; then
    echo -e "${GREEN}所有测试通过!${NC}"
    exit 0
else
    echo -e "${RED}有 ${fail_count} 项测试失败，请检查上方的 [FAIL] 项${NC}"
    exit 1
fi