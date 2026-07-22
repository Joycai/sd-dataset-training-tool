# 环境配置与构建指南

本指南覆盖本项目两个组成部分的环境配置：

1. **Flutter 桌面客户端**（仓库根目录）— 主程序，Windows / macOS / Linux 三平台。
2. **AiApiServer**（[`AiApiServer/`](../AiApiServer/) 子目录）— 可选的 Python AI 后端，
   为客户端提供 AI 打标、去背景、翻译能力。不使用 AI 功能时无需配置。

---

## 一、Flutter 桌面客户端

### 1.1 通用要求

| 项目 | 要求 |
|------|------|
| Flutter SDK | **3.35 及以上**（Dart SDK `>=3.9.0`，见 [pubspec.yaml](../pubspec.yaml)） |
| 渠道 | stable |

获取依赖：

```bash
flutter pub get
```

开发调试直接运行：

```bash
flutter run -d windows   # 或 macos / linux
```

### 1.2 Windows

**环境要求**

- Windows 10 及以上
- Visual Studio 2022（或更高），勾选 **“使用 C++ 的桌面开发”** 工作负载
- 可用 `flutter doctor` 确认 `Visual Studio - develop Windows apps` 打勾

**打包构建**

```bash
flutter build windows --release
```

产物目录：`build\windows\x64\runner\Release\`（整个目录即绿色版程序，
`dataset_training_tool.exe` 与同目录 DLL、`data\` 需一起分发）。

### 1.3 macOS

**环境要求**

- 最新版 Xcode（含命令行工具：`xcode-select --install`）
- 本项目已**移除 CocoaPods**，原生依赖（`desktop_multi_window` 等）全部通过
  **Swift Package Manager** 管理，无需安装 Ruby / CocoaPods，首次构建时 Xcode
  会自动解析 Swift 包。

**打包构建**

```bash
flutter build macos --release
```

产物：`build/macos/Build/Products/Release/dataset_training_tool.app`。
如需分发给他人，还需自行完成签名与公证（codesign / notarytool）。

### 1.4 Linux

**环境要求**（以 Debian / Ubuntu 为例）：

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

**打包构建**

```bash
flutter build linux --release
```

产物目录：`build/linux/x64/release/bundle/`（整个 `bundle` 目录一起分发）。

---

## 二、AiApiServer Python 环境

AiApiServer 是一个 Flask HTTP 服务，监听 `0.0.0.0:50051`。客户端在
**设置 → AI 服务器地址** 中填入地址即可连接（默认 `http://127.0.0.1:50051`）。

### 2.1 Python 版本与虚拟环境

- **推荐 Python 3.12**
- 强烈建议使用独立虚拟环境（conda 或 venv），避免污染系统环境：

```bash
# conda（推荐）
conda create -n bdtm python=3.12
conda activate bdtm
```

```bash
# 或 venv
python3.12 -m venv .venv
# Windows: .venv\Scripts\activate    Linux/macOS: source .venv/bin/activate
```

### 2.2 平台 × 硬件安装矩阵

[requirements.txt](../AiApiServer/requirements.txt) 默认面向 **Windows / Linux + NVIDIA GPU（CUDA 12.6）**。
其它组合按下表调整：

| 平台 | 硬件 | onnxruntime | torch 来源 | 推理设备 |
|------|------|-------------|-----------|----------|
| Windows / Linux | NVIDIA GPU | `onnxruntime-gpu` | `whl/cu126` 源 | CUDA |
| Windows / Linux | 无 N 卡（CPU / AMD / 核显） | `onnxruntime` | `whl/cpu` 源 | CPU |
| macOS（Intel / Apple Silicon） | — | `onnxruntime` | PyPI 默认 | torch 模型走 MPS，ONNX 模型走 CPU |

> 设备选择是自动的：服务端启动时按 **CUDA → MPS → DirectML → CPU** 的顺序
> 探测（见 [modules/devices.py](../AiApiServer/modules/devices.py)），无 GPU 时自动回退 CPU，无需改代码。

### 2.3 GPU 安装（Windows / Linux + NVIDIA）

前置：安装好 NVIDIA 驱动（`nvidia-smi` 可用即可，CUDA Toolkit 不是必需的，
torch / onnxruntime 自带运行库）。

```bash
cd AiApiServer
pip install -r requirements.txt
```

**已知坑：onnxruntime-gpu 与 torch 的 CUDA 大版本必须一致。**
requirements 中 torch 来自 `cu126`（CUDA 12.6）源；若 pip 解析出的
`onnxruntime-gpu` 是 CUDA 13 系（如 1.27+），其 CUDA provider 会加载失败
（控制台报 `Error loading ... cublasLt64_XX.dll which is missing`）并
**静默回退 CPU**——功能正常但 WD 打标慢数倍。修复：降级到 CUDA 12 系的
最后一个版本：

```bash
pip install "onnxruntime-gpu==1.22.0"
```

### 2.4 CPU 替代方案（无可用 GPU 时）

无 NVIDIA 显卡（纯 CPU、AMD、核显）时，把 GPU 专用包替换为 CPU 版即可，
其余依赖完全相同：

1. 复制一份 `requirements.txt` 为 `requirements-cpu.txt`，做两处修改：
   - `onnxruntime-gpu>=1.18.1` 改为 `onnxruntime>=1.18.1`
   - 删除末尾的 `--extra-index-url https://download.pytorch.org/whl/cu126`
     以及 `torch`、`torchvision`、`torchaudio` 四行
2. 先装 CPU 版 torch，再装其余依赖：

```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements-cpu.txt
```

> Windows 下 PyPI 默认的 torch 即 CPU 版，但 Linux 下 PyPI 默认 torch 捆绑
> CUDA 运行库（体积大数 GB），因此统一显式指定 `whl/cpu` 源最稳妥。

CPU 模式下 WD 系列打标依然完全可用，单张耗时从零点几秒涨到数秒；
大型多模态模型（Qwen-VL 等描述模型）在 CPU 上会非常慢，建议只用 WD 系 tagger。

### 2.5 macOS 安装

macOS 无 CUDA，安装方式与 CPU 方案类似，但 torch 直接用 PyPI 默认版
（Apple Silicon 上自动支持 MPS 加速）：

1. 同 2.4 制作 `requirements-cpu.txt`（`onnxruntime-gpu` → `onnxruntime`，
   删除 cu126 源及 torch 三行）
2. 安装：

```bash
pip install torch torchvision torchaudio
pip install -r requirements-cpu.txt
```

注意事项：

- torch 系模型（描述、去背景）会自动使用 **MPS**；WD 系 ONNX 模型走 CPU。
- 个别依赖在 macOS（尤其 Apple Silicon）上可能装不上，如 `bitsandbytes`
  （量化，仅 CUDA 有意义）、`qwen-vl-utils[decord]` 的 `decord`（视频解码）。
  它们只服务于部分大模型路径，安装失败可从 requirements 中移除，不影响
  WD 打标 / 去背景 / 翻译等核心功能。

### 2.6 libvips 原生依赖

服务端用 `pyvips` 做图像加载，需要底层 **libvips** 动态库：

| 平台 | 做法 |
|------|------|
| Windows | **无需手动安装**。首次启动时自动从 [libvips 官方发行包](https://github.com/libvips/build-win64-mxe/releases/tag/v8.16.0) 下载解压到 `AiApiServer/vips-dev-8.16/`（约 75MB） |
| Linux | `sudo apt install libvips`（部分发行版包名为 `libvips42` 或 `libvips-dev`） |
| macOS | `brew install vips` |

### 2.7 启动与验证

```bash
cd AiApiServer
python main.py                 # 监听 0.0.0.0:50051
python main.py --device-id 1   # 多卡时指定 CUDA 设备
```

- 首次使用某个模型时会从 Hugging Face 自动下载权重；网络受限时可设置镜像：
  `HF_ENDPOINT=https://hf-mirror.com`（Windows PowerShell:
  `$env:HF_ENDPOINT="https://hf-mirror.com"`）。
- 接口冒烟用例见 [AiApiServer/test.http](../AiApiServer/test.http)；
  或在仓库根目录运行端到端验证：

```bash
dart run tool/ai_tagger_smoke.dart
```

- 客户端连接：打开应用 **设置**，确认 AI 服务器地址为
  `http://127.0.0.1:50051`（或远程机器地址），工作台顶栏即可选择模型并打标。

### 2.8 常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| WD 打标突然变慢数倍 | onnxruntime-gpu 与 torch CUDA 版本不匹配，静默回退 CPU，见 2.3 |
| 启动报 pyvips / vips 相关错误 | libvips 未装好，见 2.6；Windows 上删掉 `vips-dev-8.16/` 重启可触发重新下载 |
| 模型下载超时 | 设置 `HF_ENDPOINT` 镜像，见 2.7 |
| 客户端连不上服务器 | 确认 `python main.py` 正在运行、端口 50051 未被防火墙拦截；远程访问时服务端监听的是 `0.0.0.0`，填服务器局域网 IP 即可 |

更多服务端细节（端点协议、数据结构、模型清单）见
[AiApiServer/README.md](../AiApiServer/README.md)。
