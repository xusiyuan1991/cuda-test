#!/bin/bash
#===============================================================================
# CUDA / GPU 完整环境检测脚本
# 用法: ./run.sh
#===============================================================================

set +e  # 不因单项失败退出

# ---- 颜色 & 符号 ----
G='\033[0;32m'   # Green
R='\033[0;31m'   # Red
Y='\033[1;33m'   # Yellow
C='\033[0;36m'   # Cyan
B='\033[1;34m'   # Blue
M='\033[0;35m'   # Magenta
N='\033[0m'      # No Color

OK="${G}✓${N}"
BAD="${R}✗${N}"
WARN="${Y}⚠${N}"

pass=0
fail=0
warn=0
skip=0

# ---- 辅助函数 ----
say_pass() { echo -e "  ${OK}  $1"; ((pass++)); }
say_fail() { echo -e "  ${BAD}  $1"; ((fail++)); }
say_warn() { echo -e "  ${WARN}  $1"; ((warn++)); }
say_skip() { echo -e "    $1"; ((skip++)); }
say_info() { echo -e "    $1"; }
say_kv()   { printf "    %-30s %s\n" "$1" "$2"; }

section() {
    echo ""
    echo -e "${B}┌──────────────────────────────────────────────┐${N}"
    echo -e "${B}│${N} ${Y}$1${N}"
    echo -e "${B}└──────────────────────────────────────────────┘${N}"
}

run_cmd() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        say_pass "$label"
    else
        say_fail "$label"
    fi
}

run_cmd_quiet() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        say_pass "$label"
        return 0
    else
        say_fail "$label"
        return 1
    fi
}

echo ""
echo -e "${C}╔══════════════════════════════════════════════╗${N}"
echo -e "${C}║${N}       ${Y}CUDA / GPU 环境完整检测脚本${N}          ${C}║${N}"
echo -e "${C}║${N}            $(date '+%Y-%m-%d %H:%M:%S')               ${C}║${N}"
echo -e "${C}╚══════════════════════════════════════════════╝${N}"

#===============================================================================
section "1. 系统基础信息"
#===============================================================================

run_cmd "uname -r (内核版本)"    uname -r
run_cmd "uname -m (CPU 架构)"    uname -m
run_cmd "hostname 可解析"        hostname
run_cmd "/etc/os-release 存在"  test -f /etc/os-release

if [ -f /etc/os-release ]; then
    say_info "OS: $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
fi

# CPU
NCPU=$(nproc 2>/dev/null || echo "?")
say_kv "CPU 逻辑核心数"  "$NCPU"
if command -v lscpu >/dev/null 2>&1; then
    say_info "型号: $(lscpu 2>/dev/null | grep 'Model name' | head -1 | sed 's/.*://;s/^ *//')"
fi

# 内存
if command -v free >/dev/null 2>&1; then
    MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    say_kv "系统内存总量" "$MEM"
else
    run_cmd "free 命令可用" command -v free
fi

# 磁盘
if command -v df >/dev/null 2>&1; then
    ROOT_DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $4}')
    say_kv "根分区可用空间" "$ROOT_DISK"
fi

# GCC
run_cmd_quiet "gcc 可用" command -v gcc
if command -v gcc >/dev/null 2>&1; then
    say_kv "gcc 版本" "$(gcc --version 2>/dev/null | head -1)"
fi
run_cmd_quiet "g++ 可用" command -v g++
run_cmd_quiet "make 可用"   command -v make
run_cmd_quiet "cmake 可用"  command -v cmake

# Shell
say_kv "当前 Shell" "$SHELL"
say_kv "用户"       "$(whoami)"

#===============================================================================
section "2. NVIDIA 驱动 & nvidia-smi"
#===============================================================================

run_cmd_quiet "nvidia-smi 命令可用" command -v nvidia-smi

if command -v nvidia-smi >/dev/null 2>&1; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$DRIVER_VER" ]; then
        say_pass "NVIDIA 驱动已加载 (${DRIVER_VER})"
        say_kv "驱动版本" "$DRIVER_VER"
    else
        say_fail "NVIDIA 驱动未加载或无法查询"
    fi

    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    say_kv "GPU 数量" "$GPU_COUNT"

    if [ "$GPU_COUNT" -gt 0 ]; then
        nvidia-smi --query-gpu=index,name,uuid,memory.total,memory.free,utilization.gpu,temperature.gpu,power.draw,fan.speed,clocks.current.sm,clocks.current.memory,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader 2>/dev/null | while IFS=, read -r idx name uuid mem_total mem_free util temp power fan smclk memclk pcie_gen pcie_width; do
            say_kv "GPU-$idx"         "$(echo $name | xargs)"
            say_kv "  UUID"           "$(echo $uuid | xargs)"
            say_kv "  显存"           "$(echo $mem_total | xargs) (可用: $(echo $mem_free | xargs))"
            say_kv "  GPU 利用率"     "$(echo $util | xargs)"
            say_kv "  温度"           "$(echo $temp | xargs)°C"
            say_kv "  功耗"           "$(echo $power | xargs)"
            say_kv "  风扇转速"       "$(echo $fan | xargs)%"
            say_kv "  SM 时钟"        "$(echo $smclk | xargs) MHz"
            say_kv "  显存时钟"       "$(echo $memclk | xargs) MHz"
            say_kv "  PCIe"           "Gen$(echo $pcie_gen | xargs) x$(echo $pcie_width | xargs)"
        done

        # GPU 拓扑
        if nvidia-smi topo -m >/dev/null 2>&1; then
            say_info "GPU 拓扑矩阵:"
            nvidia-smi topo -m 2>/dev/null | while IFS= read -r l; do
                say_info "    $l"
            done
        fi
    fi

    # 持久化模式
    PMODE=$(nvidia-smi -q 2>/dev/null | grep -i "Persistence Mode" | head -1 | awk '{print $NF}')
    say_kv "持久化模式" "${PMODE:-未知}"

    # 计算模式
    CMODE=$(nvidia-smi -q 2>/dev/null | grep -i "Compute Mode" | head -1 | awk '{print $NF}')
    say_kv "计算模式" "${CMODE:-未知}"

    # CUDA 驱动 API 版本
    CUDA_DRV=$(nvidia-smi 2>/dev/null | grep -i "CUDA Version" | awk '{print $NF}')
    say_kv "CUDA 驱动版本" "${CUDA_DRV:-未知}"
else
    say_fail "nvidia-smi 不可用 — 未安装驱动"
fi

#===============================================================================
section "3. CUDA Toolkit"
#===============================================================================

run_cmd_quiet "nvcc 可用" command -v nvcc
if command -v nvcc >/dev/null 2>&1; then
    say_kv "nvcc 路径" "$(which nvcc)"
    say_kv "nvcc 版本" "$(nvcc --version 2>/dev/null | grep 'release' | awk '{print $5}' | tr -d ',')"
fi

# CUDA_HOME
if [ -n "$CUDA_HOME" ]; then
    say_pass "CUDA_HOME 环境变量已设置"
    say_kv "CUDA_HOME" "$CUDA_HOME"
else
    CUDA_GUESS="/usr/local/cuda"
    if [ -d "$CUDA_GUESS" ]; then
        say_pass "CUDA_HOME 未设置，但 $CUDA_GUESS 存在"
        CUDA_HOME="$CUDA_GUESS"
    else
        say_warn "CUDA_HOME 未设置，/usr/local/cuda 也不存在"
        CUDA_HOME=""
    fi
fi

if [ -n "$CUDA_HOME" ]; then
    run_cmd_quiet "cuda.h 头文件存在"     test -f "$CUDA_HOME/include/cuda.h"
    run_cmd_quiet "cuda_runtime.h 存在"   test -f "$CUDA_HOME/include/cuda_runtime.h"
    run_cmd_quiet "libcudart.so 存在"     find "$CUDA_HOME" -name "libcudart.so*" 2>/dev/null | head -1 >/dev/null
    run_cmd_quiet "libcuda.so 存在"       find /usr/lib* -name "libcuda.so*" 2>/dev/null | head -1 >/dev/null

    if command -v nvcc >/dev/null 2>&1; then
        # 检测 CUDA 版本
        CUDA_TOOLKIT_VER=$(nvcc --version 2>/dev/null | grep 'release' | awk '{print $5}' | tr -d ',')
        say_kv "CUDA Toolkit 版本" "$CUDA_TOOLKIT_VER"
    fi
fi

# /usr/local 下的 CUDA 多版本
CUDA_VERSIONS=$(ls -d /usr/local/cuda-* 2>/dev/null)
if [ -n "$CUDA_VERSIONS" ]; then
    say_info "已安装的 CUDA 版本:"
    for d in $CUDA_VERSIONS; do
        say_info "  $d -> $(readlink -f $d 2>/dev/null || echo $d)"
    done
else
    say_info "/usr/local 下无 cuda-* 目录"
fi

#===============================================================================
section "4. CUDA 核心库检测"
#===============================================================================

for lib in libcublas.so libcufft.so libcusparse.so libcurand.so libcusolver.so libnvrtc.so libnppc.so libnppial.so libnppicc.so libnppidei.so libnppif.so libnppig.so libnppim.so libnppist.so libnppisu.so libnppitc.so libnpps.so libnvblas.so libnvjpeg.so; do
    FOUND=$(ldconfig -p 2>/dev/null | grep -c "$lib" || find /usr/lib* /usr/local/cuda* -name "${lib}*" 2>/dev/null | head -1)
    if [ -n "$FOUND" ] && [ "$FOUND" != "0" ]; then
        say_pass "$lib"
    else
        say_warn "$lib (未找到)"
    fi
done

#===============================================================================
section "5. NVCC 编译 & 运行测试"
#===============================================================================

if command -v nvcc >/dev/null 2>&1; then
    TMP_CU=$(mktemp /tmp/cuda_compile_test_XXXX.cu)
    TMP_OUT=$(mktemp /tmp/cuda_compile_test_XXXX)

    cat > "$TMP_CU" << 'CUDAEOF'
#include <stdio.h>
#include <math.h>
#include <cuda_runtime.h>
#include <cublas_v2.h>

// ===== Kernel 1: 基础 hello world =====
__global__ void hello_kernel() {
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        printf("  [Kernel] Hello from GPU!\n");
    }
}

// ===== Kernel 2: 向量加法 (验证计算正确性) =====
__global__ void vec_add(const float *a, const float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

// ===== Kernel 3: SAXPY =====
__global__ void saxpy(int n, float alpha, const float *x, float *y) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) y[i] = alpha * x[i] + y[i];
}

int main() {
    // --- 设备信息 ---
    int nDevices;
    cudaError_t err = cudaGetDeviceCount(&nDevices);
    if (err != cudaSuccess) {
        printf("  [FAIL] cudaGetDeviceCount: %s\n", cudaGetErrorString(err));
        return 1;
    }
    printf("  CUDA 设备数量: %d\n", nDevices);
    if (nDevices == 0) {
        printf("  [FAIL] 没有可用的 CUDA 设备\n");
        return 1;
    }

    for (int d = 0; d < nDevices; d++) {
        cudaDeviceProp prop;
        cudaGetDeviceProperties(&prop, d);
        printf("  设备 %d: %s\n", d, prop.name);
        printf("    计算能力:           %d.%d\n", prop.major, prop.minor);
        printf("    多处理器 (SM):      %d\n", prop.multiProcessorCount);
        printf("    全局内存:           %.2f GB\n", prop.totalGlobalMem / (1024.0*1024.0*1024.0));
        printf("    共享内存/块:        %zu KB\n", prop.sharedMemPerBlock / 1024);
        printf("    寄存器/块:          %d\n", prop.regsPerBlock);
        printf("    最大线程/块:        %d\n", prop.maxThreadsPerBlock);
        printf("    最大块维度:         (%d, %d, %d)\n", prop.maxThreadsDim[0], prop.maxThreadsDim[1], prop.maxThreadsDim[2]);
        printf("    最大网格维度:       (%d, %d, %d)\n", prop.maxGridSize[0], prop.maxGridSize[1], prop.maxGridSize[2]);
        printf("    Warp 大小:          %d\n", prop.warpSize);
        printf("    常量内存:           %zu KB\n", prop.totalConstMem / 1024);
        printf("    L2 缓存:            %d KB\n", prop.l2CacheSize / 1024);
        printf("    峰值时钟频率:       %.2f GHz\n", prop.clockRate / 1e6);
        printf("    内存时钟频率:       %.2f GHz\n", prop.memoryClockRate / 1e3);
        printf("    内存总线宽度:       %d bit\n", prop.memoryBusWidth);
        printf("    内存带宽:           %.2f GB/s\n",
               2.0 * prop.memoryClockRate * (prop.memoryBusWidth / 8.0) / 1e6);
        printf("    并发内核执行:       %s\n", prop.concurrentKernels ? "是" : "否");
        printf("    异步引擎数:         %d\n", prop.asyncEngineCount);
        printf("    统一寻址:           %s\n", prop.unifiedAddressing ? "支持" : "不支持");
        printf("    托管内存:           %s\n", prop.managedMemory     ? "支持" : "不支持");
        printf("    页锁定内存映射:     %s\n", prop.canMapHostMemory  ? "支持" : "不支持");
        printf("    计算抢占:           %s\n", prop.computePreemptionSupported ? "支持" : "不支持");
        printf("    Tensor Cores:       %s\n", prop.major >= 7 ? "有" : "无");
    }

    // --- Kernel 1: Hello ---
    hello_kernel<<<1, 1>>>();
    cudaDeviceSynchronize();
    err = cudaGetLastError();
    if (err != cudaSuccess) {
        printf("  [FAIL] hello_kernel 失败: %s\n", cudaGetErrorString(err));
    }

    // --- Kernel 2: 向量加法 ---
    const int N = 1 << 20;  // 1M 元素
    size_t bytes = N * sizeof(float);
    float *h_a, *h_b, *h_c, *d_a, *d_b, *d_c;

    h_a = (float*)malloc(bytes);
    h_b = (float*)malloc(bytes);
    h_c = (float*)malloc(bytes);
    for (int i = 0; i < N; i++) { h_a[i] = 1.0f; h_b[i] = 2.0f; }

    cudaMalloc(&d_a, bytes); cudaMalloc(&d_b, bytes); cudaMalloc(&d_c, bytes);
    cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice);

    int threads = 256;
    int blocks = (N + threads - 1) / threads;
    vec_add<<<blocks, threads>>>(d_a, d_b, d_c, N);
    cudaMemcpy(h_c, d_c, bytes, cudaMemcpyDeviceToHost);

    int errors = 0;
    for (int i = 0; i < N; i++) { if (fabsf(h_c[i] - 3.0f) > 1e-5) errors++; }
    if (errors == 0)
        printf("  [PASS] 向量加法 (%d 元素, 结果 %.1f) — 全部正确\n", N, h_c[0]);
    else
        printf("  [FAIL] 向量加法 — %d 个错误\n", errors);

    // --- Kernel 3: SAXPY ---
    float *h_y = (float*)malloc(bytes);
    for (int i = 0; i < N; i++) h_y[i] = 1.0f;

    cudaMemcpy(d_b, h_y, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice);
    saxpy<<<blocks, threads>>>(N, 2.0f, d_a, d_b);
    cudaMemcpy(h_y, d_b, bytes, cudaMemcpyDeviceToHost);

    errors = 0;
    for (int i = 0; i < N; i++) { if (fabsf(h_y[i] - 3.0f) > 1e-5) errors++; }
    if (errors == 0)
        printf("  [PASS] SAXPY (%d 元素, 结果 %.1f) — 全部正确\n", N, h_y[0]);
    else
        printf("  [FAIL] SAXPY — %d 个错误\n", errors);

    // --- Kernel 4: 带宽测试 ---
    float bandwidth;
    cudaEvent_t start, stop;
    cudaEventCreate(&start); cudaEventCreate(&stop);

    cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice);

    cudaEventRecord(start, 0);
    vec_add<<<blocks, threads>>>(d_a, d_b, d_c, N);
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);

    float ms;
    cudaEventElapsedTime(&ms, start, stop);
    bandwidth = (3.0f * bytes) / (ms / 1000.0f) / 1e9;  // 读 a, b; 写 c
    printf("  内存带宽 (向量加法): %.2f GB/s (%.3f ms, %d 元素)\n", bandwidth, ms, N);

    // --- Kernel 5: cuBLAS SGEMM (矩阵乘法) ---
    cublasHandle_t handle;
    cublasCreate(&handle);

    const int M = 2048, K = 2048, N_B = 2048;
    float *d_A, *d_B, *d_C_blas;
    cudaMalloc(&d_A, M * K * sizeof(float));
    cudaMalloc(&d_B, K * N_B * sizeof(float));
    cudaMalloc(&d_C_blas, M * N_B * sizeof(float));

    // 填充
    float *h_A = (float*)malloc(M * K * sizeof(float));
    float *h_B_blas = (float*)malloc(K * N_B * sizeof(float));
    for (int i = 0; i < M * K; i++) h_A[i] = 1.0f;
    for (int i = 0; i < K * N_B; i++) h_B_blas[i] = 1.0f;
    cudaMemcpy(d_A, h_A, M * K * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B_blas, K * N_B * sizeof(float), cudaMemcpyHostToDevice);

    float alpha = 1.0f, beta = 0.0f;
    cudaDeviceSynchronize();
    cudaEventRecord(start, 0);
    cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, M, N_B, K,
                &alpha, d_A, M, d_B, K, &beta, d_C_blas, M);
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&ms, start, stop);

    float flops = 2.0f * M * K * N_B / (ms / 1000.0f);
    printf("  cuBLAS SGEMM (%dx%dx%d): %.2f GFLOPS (%.3f ms)\n", M, K, N_B, flops / 1e9, ms);

    cublasDestroy(handle);
    cudaFree(d_a); cudaFree(d_b); cudaFree(d_c);
    cudaFree(d_A); cudaFree(d_B); cudaFree(d_C_blas);
    free(h_a); free(h_b); free(h_c); free(h_y);
    free(h_A); free(h_B_blas);
    cudaEventDestroy(start); cudaEventDestroy(stop);

    printf("\n  [PASS] 所有 CUDA C/C++ 测试完成!\n");
    return 0;
}
CUDAEOF

    say_info "正在编译 CUDA 测试程序..."
    if nvcc -O3 -lcublas -o "$TMP_OUT" "$TMP_CU" 2>/tmp/cuda_compile_err.log; then
        say_pass "NVCC 编译成功"
        say_info "运行编译产物:"
        if "$TMP_OUT"; then
            say_pass "CUDA 运行时测试全部通过"
        else
            say_fail "CUDA 运行时测试失败"
        fi
    else
        say_fail "NVCC 编译失败"
        say_info "编译错误: $(cat /tmp/cuda_compile_err.log 2>/dev/null | head -5)"
        rm -f /tmp/cuda_compile_err.log
    fi
    rm -f "$TMP_CU" "$TMP_OUT"
else
    say_skip "nvcc 不可用，跳过编译测试"
fi

#===============================================================================
section "6. Python 环境"
#===============================================================================

# 寻找 Python
PY=""
for p in python3 python python3.11 python3.10 python3.9 python3.8; do
    if command -v $p >/dev/null 2>&1; then
        PY=$p
        break
    fi
done

if [ -n "$PY" ]; then
    say_pass "Python 解释器: $($PY --version 2>&1)"
    say_kv "路径" "$(which $PY)"

    PIP=""
    for p in pip3 pip pip3.11 pip3.10 pip3.9 pip3.8; do
        if command -v $p >/dev/null 2>&1; then
            PIP=$p
            break
        fi
    done
    if [ -n "$PIP" ]; then
        say_pass "pip 可用: $($PIP --version 2>&1 | head -1)"
    else
        say_fail "pip 不可用"
    fi

    # Conda
    if command -v conda >/dev/null 2>&1; then
        say_pass "conda 可用: $(conda --version 2>&1)"
        say_kv "conda 环境" "$(conda info --envs 2>/dev/null | grep '^\*' | awk '{print $2}' || echo '?')"
    else
        say_info "conda: 未安装"
    fi

    # Virtual env
    if [ -n "$VIRTUAL_ENV" ]; then
        say_pass "venv 已激活: $VIRTUAL_ENV"
    fi

    # NumPy
    NP_VER=$($PY -c "import numpy; print(numpy.__version__)" 2>/dev/null)
    if [ -n "$NP_VER" ]; then
        say_pass "NumPy $NP_VER"
    else
        say_warn "NumPy 未安装"
    fi

    # PyCUDA
    PYCUDA_VER=$($PY -c "import pycuda; print(pycuda.VERSION_TEXT)" 2>/dev/null)
    if [ -n "$PYCUDA_VER" ]; then
        say_pass "PyCUDA $PYCUDA_VER"
    else
        say_warn "PyCUDA 未安装"
    fi
else
    say_fail "Python 不可用"
fi

#===============================================================================
section "7. PyTorch"
#===============================================================================

if [ -n "$PY" ]; then
    TORCH_INFO=$($PY -c "
import sys
try:
    import torch
    print('OK')
    print('version', torch.__version__)
    print('cuda_available', torch.cuda.is_available())
    if torch.cuda.is_available():
        print('cuda_version', torch.version.cuda)
        try:    print('cudnn_version', torch.backends.cudnn.version())
        except: print('cudnn_version', '?')
        print('device_count', torch.cuda.device_count())
        for i in range(torch.cuda.device_count()):
            print(f'gpu{i}_name', torch.cuda.get_device_name(i))
            props = torch.cuda.get_device_properties(i)
            print(f'gpu{i}_cc', f'{props.major}.{props.minor}')
            print(f'gpu{i}_mem', f'{props.total_mem / 1024**3:.2f} GB')
            print(f'gpu{i}_sm', props.multi_processor_count)
        # 矩阵乘法性能
        try:
            x = torch.randn(4096, 4096, device='cuda', dtype=torch.float32)
            y = torch.randn(4096, 4096, device='cuda', dtype=torch.float32)
            torch.cuda.synchronize()
            start = torch.cuda.Event(enable_timing=True)
            end = torch.cuda.Event(enable_timing=True)
            start.record()
            z = torch.mm(x, y)
            end.record()
            torch.cuda.synchronize()
            ms = start.elapsed_time(end)
            gflops = 2.0 * 4096 * 4096 * 4096 / (ms / 1000) / 1e9
            print('matmul_ms', f'{ms:.2f}')
            print('matmul_gflops', f'{gflops:.2f}')
        except Exception as e:
            print('matmul_error', str(e))
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)

    if echo "$TORCH_INFO" | grep -q "^OK$"; then
        say_pass "PyTorch $(echo "$TORCH_INFO" | grep '^version ' | awk '{print $2}')"

        if echo "$TORCH_INFO" | grep -q "^cuda_available True$"; then
            say_pass "torch.cuda.is_available() = True"
        else
            say_warn "torch.cuda.is_available() = False (CPU only PyTorch?)"
        fi

        CUDA_VER=$(echo "$TORCH_INFO" | grep '^cuda_version ' | awk '{print $2}')
        [ -n "$CUDA_VER" ] && say_kv "CUDA 版本" "$CUDA_VER"

        CUDNN_VER=$(echo "$TORCH_INFO" | grep '^cudnn_version ' | awk '{print $2}')
        [ -n "$CUDNN_VER" ] && say_kv "cuDNN 版本" "$CUDNN_VER"

        GPU_COUNT=$(echo "$TORCH_INFO" | grep '^device_count ' | awk '{print $2}')
        [ -n "$GPU_COUNT" ] && say_kv "可见 GPU 数量" "$GPU_COUNT"

        for i in $(seq 0 7); do
            NAME=$(echo "$TORCH_INFO" | grep "^gpu${i}_name " | awk '{$1=""; print $0}' | xargs)
            [ -z "$NAME" ] && break
            say_pass "GPU $i: $NAME"
            CC=$(echo "$TORCH_INFO" | grep "^gpu${i}_cc " | awk '{print $2}')
            MEM=$(echo "$TORCH_INFO" | grep "^gpu${i}_mem " | awk '{print $2" "$3}')
            SM=$(echo "$TORCH_INFO" | grep "^gpu${i}_sm " | awk '{print $2}')
            say_kv "  计算能力" "$CC"
            say_kv "  显存"     "$MEM"
            say_kv "  SM 数量"  "$SM"
        done

        MMS=$(echo "$TORCH_INFO" | grep '^matmul_ms ' | awk '{print $2}')
        GFLOPS=$(echo "$TORCH_INFO" | grep '^matmul_gflops ' | awk '{print $2}')
        if [ -n "$MMS" ]; then
            say_pass "SGEMM (4096x4096): ${GFLOPS} GFLOPS (${MMS} ms)"
        fi
    elif echo "$TORCH_INFO" | grep -q "IMPORT_ERROR"; then
        say_warn "PyTorch 未安装"
    else
        say_fail "PyTorch 检测出错: $TORCH_INFO"
    fi
else
    say_skip "Python 不可用，跳过 PyTorch 测试"
fi

#===============================================================================
section "8. TensorFlow / Keras"
#===============================================================================

if [ -n "$PY" ]; then
    TF_INFO=$($PY -c "
try:
    import tensorflow as tf
    print('OK')
    print('version', tf.__version__)
    gpus = tf.config.list_physical_devices('GPU')
    print('gpu_count', len(gpus))
    for i, gpu in enumerate(gpus):
        print(f'gpu{i}', gpu.name, gpu.device_type)
    if gpus:
        with tf.device('/GPU:0'):
            a = tf.random.normal([4096, 4096])
            b = tf.random.normal([4096, 4096])
            import time
            t0 = time.time()
            c = tf.matmul(a, b)
            t1 = time.time()
            ms = (t1 - t0) * 1000
            gflops = 2 * 4096**3 / (ms / 1000) / 1e9
            print('matmul_ms', f'{ms:.2f}')
            print('matmul_gflops', f'{gflops:.2f}')
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)

    if echo "$TF_INFO" | grep -q "^OK$"; then
        say_pass "TensorFlow $(echo "$TF_INFO" | grep '^version ' | awk '{print $2}')"
        GPU_COUNT=$(echo "$TF_INFO" | grep '^gpu_count ' | awk '{print $2}')
        say_kv "识别到的 GPU 数量" "$GPU_COUNT"
        if [ "$GPU_COUNT" -gt 0 ]; then
            say_pass "TensorFlow 能使用 $GPU_COUNT 个 GPU"
        else
            say_warn "TensorFlow 未识别到 GPU"
        fi
        MMS=$(echo "$TF_INFO" | grep '^matmul_ms ' | awk '{print $2}')
        GFLOPS=$(echo "$TF_INFO" | grep '^matmul_gflops ' | awk '{print $2}')
        [ -n "$MMS" ] && say_pass "SGEMM (4096x4096): ${GFLOPS} GFLOPS (${MMS} ms)"
    elif echo "$TF_INFO" | grep -q "IMPORT_ERROR"; then
        say_warn "TensorFlow 未安装"
    else
        say_fail "TensorFlow 检测出错: $TF_INFO"
    fi
else
    say_skip "Python 不可用，跳过 TensorFlow 测试"
fi

#===============================================================================
section "9. JAX"
#===============================================================================

if [ -n "$PY" ]; then
    JAX_INFO=$($PY -c "
try:
    import jax
    print('OK')
    print('version', jax.__version__)
    devices = jax.devices('gpu')
    print('gpu_count', len(devices))
    for i, d in enumerate(devices):
        print(f'gpu{i}', d.device_kind, d.platform)
    if devices:
        import jax.numpy as jnp
        x = jnp.ones((4096, 4096))
        y = jnp.ones((4096, 4096))
        import time
        t0 = time.time()
        z = jnp.dot(x, y)
        z.block_until_ready()
        t1 = time.time()
        ms = (t1 - t0) * 1000
        gflops = 2 * 4096**3 / (ms / 1000) / 1e9
        print('matmul_ms', f'{ms:.2f}')
        print('matmul_gflops', f'{gflops:.2f}')
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)

    if echo "$JAX_INFO" | grep -q "^OK$"; then
        say_pass "JAX $(echo "$JAX_INFO" | grep '^version ' | awk '{print $2}')"
        GPU_COUNT=$(echo "$JAX_INFO" | grep '^gpu_count ' | awk '{print $2}')
        say_kv "JAX 可见 GPU 数" "$GPU_COUNT"
        if [ "$GPU_COUNT" -gt 0 ]; then
            say_pass "JAX 能使用 $GPU_COUNT 个 GPU"
        fi
        MMS=$(echo "$JAX_INFO" | grep '^matmul_ms ' | awk '{print $2}')
        GFLOPS=$(echo "$JAX_INFO" | grep '^matmul_gflops ' | awk '{print $2}')
        [ -n "$MMS" ] && say_pass "SGEMM (4096x4096): ${GFLOPS} GFLOPS (${MMS} ms)"
    elif echo "$JAX_INFO" | grep -q "IMPORT_ERROR"; then
        say_warn "JAX 未安装"
    else
        say_fail "JAX 检测出错: $JAX_INFO"
    fi
else
    say_skip "Python 不可用，跳过 JAX 测试"
fi

#===============================================================================
section "10. CuPy"
#===============================================================================

if [ -n "$PY" ]; then
    CUPY_INFO=$($PY -c "
try:
    import cupy as cp
    print('OK')
    print('version', cp.__version__)
    print('device_count', cp.cuda.runtime.getDeviceCount())
    for i in range(cp.cuda.runtime.getDeviceCount()):
        with cp.cuda.Device(i):
            props = cp.cuda.runtime.getDeviceProperties(i)
            print(f'gpu{i}', props['name'].decode())
            print(f'gpu{i}_mem', f'{props[\"totalGlobalMem\"]/1024**3:.2f} GB')
    x = cp.ones((4096, 4096), dtype=cp.float32)
    y = cp.ones((4096, 4096), dtype=cp.float32)
    import time
    t0 = time.time()
    z = cp.dot(x, y)
    cp.cuda.Stream.null.synchronize()
    t1 = time.time()
    ms = (t1 - t0) * 1000
    gflops = 2 * 4096**3 / (ms / 1000) / 1e9
    print('matmul_ms', f'{ms:.2f}')
    print('matmul_gflops', f'{gflops:.2f}')
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)

    if echo "$CUPY_INFO" | grep -q "^OK$"; then
        say_pass "CuPy $(echo "$CUPY_INFO" | grep '^version ' | awk '{print $2}')"
        DC=$(echo "$CUPY_INFO" | grep '^device_count ' | awk '{print $2}')
        say_kv "可见 GPU 数量" "$DC"
        MMS=$(echo "$CUPY_INFO" | grep '^matmul_ms ' | awk '{print $2}')
        GFLOPS=$(echo "$CUPY_INFO" | grep '^matmul_gflops ' | awk '{print $2}')
        [ -n "$MMS" ] && say_pass "SGEMM (4096x4096): ${GFLOPS} GFLOPS (${MMS} ms)"
    elif echo "$CUPY_INFO" | grep -q "IMPORT_ERROR"; then
        say_warn "CuPy 未安装"
    else
        say_fail "CuPy 检测出错: $CUPY_INFO"
    fi
else
    say_skip "Python 不可用，跳过 CuPy 测试"
fi

#===============================================================================
section "11. Numba (CUDA)"
#===============================================================================

if [ -n "$PY" ]; then
    NUMBA_INFO=$($PY -c "
try:
    import numba
    from numba import cuda
    print('OK')
    print('version', numba.__version__)
    print('cuda_available', cuda.is_available())
    if cuda.is_available():
        gpus = cuda.gpus
        for i, gpu in enumerate(gpus):
            print(f'gpu{i}', gpu.name.decode())
    # 简单 kernel 测试
    if cuda.is_available():
        @cuda.jit
        def add_kernel(a, b, c):
            i = cuda.grid(1)
            if i < a.size:
                c[i] = a[i] + b[i]
        n = 1024
        import numpy as np
        a = np.ones(n, dtype=np.float32)
        b = np.ones(n, dtype=np.float32) * 2
        c_out = np.zeros(n, dtype=np.float32)
        d_a = cuda.to_device(a)
        d_b = cuda.to_device(b)
        d_c = cuda.device_array_like(c_out)
        add_kernel[(n + 255) // 256, 256](d_a, d_b, d_c)
        cuda.synchronize()
        d_c.copy_to_host(c_out)
        if c_out[0] == 3.0:
            print('kernel_test', 'PASS')
        else:
            print('kernel_test', 'FAIL')
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)

    if echo "$NUMBA_INFO" | grep -q "^OK$"; then
        say_pass "Numba $(echo "$NUMBA_INFO" | grep '^version ' | awk '{print $2}')"
        if echo "$NUMBA_INFO" | grep -q "^cuda_available True$"; then
            say_pass "numba.cuda.is_available() = True"
        else
            say_warn "numba.cuda.is_available() = False (可能是 CPU only Numba)"
        fi
        if echo "$NUMBA_INFO" | grep -q "^kernel_test PASS$"; then
            say_pass "Numba CUDA Kernel 测试通过"
        fi
    elif echo "$NUMBA_INFO" | grep -q "IMPORT_ERROR"; then
        say_warn "Numba 未安装"
    else
        say_fail "Numba 检测出错: $NUMBA_INFO"
    fi
else
    say_skip "Python 不可用，跳过 Numba 测试"
fi

#===============================================================================
section "12. RAPIDS (cuDF / cuML)"
#===============================================================================

if [ -n "$PY" ]; then
    # cuDF
    CUDF_VER=$($PY -c "import cudf; print(cudf.__version__)" 2>/dev/null)
    if [ -n "$CUDF_VER" ]; then
        say_pass "cuDF $CUDF_VER"
    else
        say_warn "cuDF 未安装"
    fi

    # cuML
    CUML_VER=$($PY -c "import cuml; print(cuml.__version__)" 2>/dev/null)
    if [ -n "$CUML_VER" ]; then
        say_pass "cuML $CUML_VER"
    else
        say_warn "cuML 未安装"
    fi

    # cuDNN (Python)
    CUDNN_PY=$($PY -c "import cudnn; print(cudnn.__version__)" 2>/dev/null)
    if [ -n "$CUDNN_PY" ]; then
        say_pass "cudnn (Python) $CUDNN_PY"
    else
        say_warn "cudnn (Python 绑定) 未安装"
    fi

    # RMM
    RMM_VER=$($PY -c "import rmm; print(rmm.__version__)" 2>/dev/null)
    if [ -n "$RMM_VER" ]; then
        say_pass "RMM $RMM_VER"
    else
        say_warn "RMM 未安装"
    fi
else
    say_skip "Python 不可用，跳过 RAPIDS 测试"
fi

#===============================================================================
section "13. 深度学习相关库"
#===============================================================================

if [ -n "$PY" ]; then
    # ONNX Runtime GPU
    ORT_INFO=$($PY -c "
try:
    import onnxruntime as ort
    print('OK')
    print('version', ort.__version__)
    providers = ort.get_available_providers()
    print('providers', ','.join(providers))
    if 'CUDAExecutionProvider' in providers:
        print('cuda', 'YES')
    else:
        print('cuda', 'NO')
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)
    if echo "$ORT_INFO" | grep -q "^OK$"; then
        say_pass "ONNX Runtime $(echo "$ORT_INFO" | grep '^version ' | awk '{print $2}')"
        if echo "$ORT_INFO" | grep -q "^cuda YES$"; then
            say_pass "ONNX Runtime 支持 CUDA"
        else
            say_warn "ONNX Runtime 无 CUDA 支持"
        fi
    else
        say_warn "ONNX Runtime 未安装"
    fi

    # Transformers
    HF_VER=$($PY -c "import transformers; print(transformers.__version__)" 2>/dev/null)
    if [ -n "$HF_VER" ]; then
        say_pass "transformers $HF_VER"
    else
        say_warn "transformers 未安装"
    fi

    # vLLM
    VLLM_VER=$($PY -c "import vllm; print(vllm.__version__)" 2>/dev/null)
    if [ -n "$VLLM_VER" ]; then
        say_pass "vLLM $VLLM_VER"
    else
        say_warn "vLLM 未安装"
    fi

    # Flash Attention
    FA_VER=$($PY -c "import flash_attn; print(flash_attn.__version__)" 2>/dev/null)
    if [ -n "$FA_VER" ]; then
        say_pass "flash_attn $FA_VER"
    else
        say_warn "flash_attn 未安装"
    fi

    # bitsandbytes
    BNB_VER=$($PY -c "import bitsandbytes; print(bitsandbytes.__version__)" 2>/dev/null)
    if [ -n "$BNB_VER" ]; then
        say_pass "bitsandbytes $BNB_VER"
    else
        say_warn "bitsandbytes 未安装"
    fi

    # xformers
    XF_VER=$($PY -c "import xformers; print(xformers.__version__)" 2>/dev/null)
    if [ -n "$XF_VER" ]; then
        say_pass "xformers $XF_VER"
    else
        say_warn "xformers 未安装"
    fi

    # Triton
    TRITON_VER=$($PY -c "import triton; print(triton.__version__)" 2>/dev/null)
    if [ -n "$TRITON_VER" ]; then
        say_pass "Triton $TRITON_VER"
    else
        say_warn "Triton 未安装"
    fi

    # OpenCV
    CV2_VER=$($PY -c "import cv2; print(cv2.__version__)" 2>/dev/null)
    if [ -n "$CV2_VER" ]; then
        say_pass "OpenCV $CV2_VER"
        CV2_CUDA=$($PY -c "print(cv2.cuda.getCudaEnabledDeviceCount())" 2>/dev/null)
        if [ -n "$CV2_CUDA" ] && [ "$CV2_CUDA" -gt 0 ]; then
            say_pass "OpenCV CUDA 已启用 ($CV2_CUDA 个设备)"
        else
            say_warn "OpenCV CUDA 未启用"
        fi
    else
        say_warn "OpenCV (Python) 未安装"
    fi

    # scikit-learn (虽然不是 GPU，但是 ML 标配)
    SK_VER=$($PY -c "import sklearn; print(sklearn.__version__)" 2>/dev/null)
    if [ -n "$SK_VER" ]; then
        say_pass "scikit-learn $SK_VER"
    else
        say_warn "scikit-learn 未安装"
    fi

    # Pillow
    PIL_VER=$($PY -c "import PIL; print(PIL.__version__)" 2>/dev/null)
    if [ -n "$PIL_VER" ]; then
        say_pass "Pillow $PIL_VER"
    else
        say_warn "Pillow 未安装"
    fi

    # dataclasses / pydantic
    PD_VER=$($PY -c "import pydantic; print(pydantic.__version__)" 2>/dev/null)
    if [ -n "$PD_VER" ]; then
        say_pass "pydantic $PD_VER"
    else
        say_warn "pydantic 未安装"
    fi
else
    say_skip "Python 不可用，跳过其他库检测"
fi

#===============================================================================
section "14. NCCL (NVIDIA 集合通信库)"
#===============================================================================

FOUND_NCCL=false
for d in /usr/lib/x86_64-linux-gnu /usr/lib /usr/local/lib /usr/local/cuda/lib64 \
         /usr/local/cuda*/lib64 /usr/local/cuda*/targets/x86_64-linux/lib; do
    if [ -f "$d/libnccl.so" ] || [ -f "$d/libnccl.so.2" ]; then
        say_pass "NCCL 已安装 ($d)"
        if [ -f "$d/libnccl.so.2" ]; then
            NCL=$(ls -la "$d/libnccl.so.2" 2>/dev/null | awk '{print $NF}')
            say_kv "libnccl.so" "$NCL"
        fi
        FOUND_NCCL=true
        break
    fi
done
if ! $FOUND_NCCL; then
    say_warn "NCCL 未找到"
fi

# NCCL 环境变量
[ -n "$NCCL_SOCKET_IFNAME" ]  && say_kv "NCCL_SOCKET_IFNAME"  "$NCCL_SOCKET_IFNAME"
[ -n "$NCCL_IB_DISABLE" ]     && say_kv "NCCL_IB_DISABLE"     "$NCCL_IB_DISABLE"
[ -n "$NCCL_DEBUG" ]          && say_kv "NCCL_DEBUG"          "$NCCL_DEBUG"

#===============================================================================
section "15. cuDNN (系统级)"
#===============================================================================

FOUND_CUDNN=false
for d in /usr/lib/x86_64-linux-gnu /usr/lib /usr/local/lib /usr/local/cuda/lib64 \
         /usr/local/cuda*/lib64 /usr/local/cuda*/targets/x86_64-linux/lib; do
    if [ -f "$d/libcudnn.so" ] || [ -f "$d/libcudnn.so.8" ] || [ -f "$d/libcudnn.so.9" ]; then
        say_pass "cuDNN 已安装 ($d)"
        FOUND_CUDNN=true
        break
    fi
done
if ! $FOUND_CUDNN; then
    say_warn "cuDNN 未找到 (系统级)"
fi

CUDNN_H=$(find /usr/include /usr/local/cuda*/include -name "cudnn_version.h" 2>/dev/null | head -1)
if [ -n "$CUDNN_H" ]; then
    CUDNN_MAJOR=$(grep CUDNN_MAJOR "$CUDNN_H" 2>/dev/null | awk '{print $NF}')
    CUDNN_MINOR=$(grep CUDNN_MINOR "$CUDNN_H" 2>/dev/null | awk '{print $NF}')
    CUDNN_PATCH=$(grep CUDNN_PATCH "$CUDNN_H" 2>/dev/null | awk '{print $NF}')
    say_kv "cuDNN 版本" "${CUDNN_MAJOR}.${CUDNN_MINOR}.${CUDNN_PATCH}"
fi

#===============================================================================
section "16. TensorRT"
#===============================================================================

if [ -n "$PY" ]; then
    TRT_VER=$($PY -c "
try:
    import tensorrt as trt
    print('OK', trt.__version__)
except ImportError:
    print('IMPORT_ERROR')
except Exception as e:
    print('ERROR', str(e))
" 2>&1)
    if echo "$TRT_VER" | grep -q "^OK"; then
        say_pass "TensorRT $(echo "$TRT_VER" | awk '{print $2}')"
    else
        say_warn "TensorRT (Python) 未安装"
    fi
else
    say_skip "Python 不可用，跳过 TensorRT 检测"
fi

# 系统级 TensorRT
FOUND_TRT=false
for d in /usr/lib/x86_64-linux-gnu /usr/local/tensorrt/lib /opt/tensorrt/lib \
         /usr/local/cuda*/targets/x86_64-linux/lib; do
    if [ -f "$d/libnvinfer.so" ] || [ -f "$d/libnvinfer.so.8" ] || [ -f "$d/libnvinfer.so.10" ]; then
        say_pass "TensorRT 系统库已安装 ($d)"
        FOUND_TRT=true
        break
    fi
done
if ! $FOUND_TRT; then
    say_warn "TensorRT 系统库未找到"
fi

if command -v trtexec >/dev/null 2>&1; then
    say_pass "trtexec 可用: $(which trtexec)"
fi

#===============================================================================
section "17. Docker / 容器支持"
#===============================================================================

run_cmd_quiet "docker 可用" command -v docker
if command -v docker >/dev/null 2>&1; then
    say_kv "docker 版本" "$(docker --version 2>/dev/null)"
    run_cmd_quiet "nvidia-docker (nvidia-container-toolkit)" \
        docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1
    if docker info 2>/dev/null | grep -qi "runtimes.*nvidia"; then
        say_pass "nvidia runtime 已注册"
    fi
fi

run_cmd_quiet "nvidia-container-cli 可用" command -v nvidia-container-cli

#===============================================================================
section "18. CUDA 相关环境变量"
#===============================================================================

echo -e ""
for var in CUDA_HOME CUDA_PATH CUDA_VISIBLE_DEVICES CUDA_DEVICE_ORDER \
           CUDA_CACHE_PATH CUDA_CACHE_DISABLE CUDA_LAUNCH_BLOCKING \
           CUDNN_PATH LD_LIBRARY_PATH LD_PRELOAD \
           PATH PYTHONPATH CONDA_PREFIX VIRTUAL_ENV \
           TORCH_CUDA_ARCH_LIST TORCH_EXTENSIONS_DIR \
           NCCL_SOCKET_IFNAME NCCL_IB_DISABLE NCCL_DEBUG NCCL_DEBUG_SUBSYS \
           OMP_NUM_THREADS MKL_NUM_THREADS \
           TF_CPP_MIN_LOG_LEVEL XLA_FLAGS; do
    val="${!var}"
    if [ -n "$val" ]; then
        say_kv "$var" "$val"
    else
        say_kv "$var" "${Y}(未设置)${N}"
    fi
done

#===============================================================================
section "19. 内核模块 & /dev 设备"
#===============================================================================

run_cmd_quiet "nvidia 内核模块已加载" lsmod 2>/dev/null | grep -q nvidia
run_cmd_quiet "nvidia_uvm 已加载"       lsmod 2>/dev/null | grep -q nvidia_uvm
run_cmd_quiet "nvidia_drm 已加载"       lsmod 2>/dev/null | grep -q nvidia_drm
run_cmd_quiet "nvidia-modeset 已加载"   lsmod 2>/dev/null | grep -q nvidia_modeset

if lsmod 2>/dev/null | grep -q nvidia; then
    say_info "已加载的 nvidia 模块:"
    lsmod 2>/dev/null | grep nvidia | while IFS= read -r l; do
        say_info "  $l"
    done
fi

run_cmd_quiet "/dev/nvidia0 存在" test -c /dev/nvidia0
run_cmd_quiet "/dev/nvidiactl 存在" test -c /dev/nvidiactl
run_cmd_quiet "/dev/nvidia-uvm 存在" test -c /dev/nvidia-uvm
run_cmd "nvidia-persistenced 运行中" pgrep -x nvidia-persistenced

#===============================================================================
# 汇总
#===============================================================================

echo ""
echo -e "${C}╔══════════════════════════════════════════════╗${N}"
echo -e "${C}║${N}              测试结果汇总                    ${C}║${N}"
echo -e "${C}╚══════════════════════════════════════════════╝${N}"
echo ""
echo -e "  ${G}${OK}  通过:  ${pass}${N}"
echo -e "  ${R}${BAD}  失败:  ${fail}${N}"
echo -e "  ${Y}${WARN}  警告:  ${warn}${N}"
echo ""

total=$((pass + fail))
if [ "$fail" -eq 0 ] && [ "$warn" -eq 0 ]; then
    echo -e "  ${G}████████████████████████████████████████████████${N}"
    echo -e "  ${G}██  全部测试通过，CUDA 环境完美！           ██${N}"
    echo -e "  ${G}████████████████████████████████████████████████${N}"
elif [ "$fail" -eq 0 ]; then
    echo -e "  ${Y}████████████████████████████████████████████████${N}"
    echo -e "  ${Y}██  核心功能 OK，有 ${warn} 项可优化项              ██${N}"
    echo -e "  ${Y}████████████████████████████████████████████████${N}"
else
    echo -e "  ${R}████████████████████████████████████████████████${N}"
    echo -e "  ${R}██  有 ${fail} 项失败，请检查上方的 ✗ 项         ██${N}"
    echo -e "  ${R}████████████████████████████████████████████████${N}"
fi

echo ""
exit $fail