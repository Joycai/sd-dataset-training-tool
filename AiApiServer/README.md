# AiApiServer

BooruDatasetTagManager 的 Python/Flask AI 后端（vendored 参考副本），为
DataSetTrainingTool 提供图片打标（WD14 等）、图片编辑（去背景）、翻译能力。
纯 HTTP + JSON 协议，DataSetTrainingTool 侧的客户端实现见
`lib/services/ai_tagger_service.dart`。

## 运行环境

- Python 3.12（建议 conda 独立环境，如 `bdtm`）
- NVIDIA GPU + CUDA 驱动（可选，无 GPU 时回退 CPU）

```bash
conda create -n bdtm python=3.12
conda activate bdtm
pip install -r requirements.txt
```

## 启动

```bash
python main.py
```

监听 `0.0.0.0:50051`。可用 `--device-id <n>` 指定 CUDA 设备。
接口冒烟用例见 [test.http](test.http)，或在 DataSetTrainingTool 仓库根目录运行
`dart run tool/ai_tagger_smoke.dart` 做端到端验证。

## 端点一览

| 端点 | 方法 | 用途 |
|------|------|------|
| `/getconfig` | GET | 列出全部模型（Interrogators / Editors / Translators 三桶） |
| `/listmodelsbytype?name=<type>` | GET | 按类型过滤模型（如 `wd`、`dd`） |
| `/getmodelparams` | POST | 查询模型可调参数（WD 系列只有 `threshold`） |
| `/interrogateimage` | POST | 识别图片、返回 tag / caption（核心） |
| `/editimage` | POST | 图片编辑（如 RMBG 去背景） |
| `/translate` | POST | 文本翻译 |

请求/响应 JSON 结构见 [modules/server_dataclasses.py](modules/server_dataclasses.py)，
字段一律 PascalCase。

## vips-dev-8.16 目录是什么？

服务端用 `pyvips` 做图像加载/预处理，它需要底层的 **libvips** 原生 DLL。
Linux 可以直接 `apt install libvips`，Windows 没有系统包管理器，所以要用
libvips 官方的 Windows 发行包（约 75MB，含 DLL、头文件及 glib/ImageMagick
等捆绑依赖）。

**不需要手动安装**：首次启动时
[modules/pyvips_dll_handler.py](modules/pyvips_dll_handler.py) 检测到
`vips-dev-8.16/` 不存在会自动从
[libvips/build-win64-mxe](https://github.com/libvips/build-win64-mxe/releases/tag/v8.16.0)
下载解压到本目录，并把其中 `bin/` 加入 DLL 搜索路径。该目录是二进制依赖，
不属于源码，已被仓库根 `.gitignore` 排除。

## 已知坑：onnxruntime 与 torch 的 CUDA 版本必须匹配

WD 系列 tagger 走 ONNX 推理。`onnxruntime-gpu` 与 `torch` 各自捆绑/依赖
特定大版本的 CUDA 运行库，二者不一致时 onnxruntime 的 CUDA provider 会
加载失败（控制台报 `Error loading ... cublasLt64_XX.dll which is missing`），
并**静默回退 CPU**——功能正常但 WD 打标变慢数倍。

例：`torch 2.13.0+cu126`（CUDA 12.6）配 `onnxruntime-gpu 1.27.0`（CUDA 13）
就会触发此问题。修复：降级到 CUDA 12 系的最后一个版本，与 torch 共用运行库：

```bash
pip install "onnxruntime-gpu==1.22.0"
```

装依赖时若 pip 解析出过新的 onnxruntime-gpu，参照 torch 的 `+cuXXX` 后缀
选择匹配的大版本即可。


### 图像预处理接口 v1

保留 `/editimage` 的历史格式行为。新的桌面图像预处理使用：

- `GET /v1/imageprocessing/capabilities`：返回 `version: 1`、
  `foreground_models`、`output_formats: ["png"]` 和
  `named_object_detection: false`。
- `POST /v1/imageprocessing/foreground`：JSON 字段为 `version: 1`、
  `model`（从 capabilities 选择）、`image`（base64 图片字节）。
  返回 `image`（RGBA PNG base64）、`mime_type: "image/png"`、
  `width`、`height`、`coordinate_frame: "exif_normalized_pixels"` 和
  `foreground_bounds`（左、上、右、下；无前景时为 null）。

接口先应用 EXIF 方向，拒绝多帧图像、超过 40 百万像素或 100 MiB 的输入。
PNG alpha 不受输入文件扩展名影响。当前仅支持前景蒙版；不声称支持任意
指定物体检测。客户端负责裁剪、调整尺寸、转换格式、预览和可恢复文件事务。
客户端取消 HTTP 后，已经开始的模型推理可能继续；返回结果不会自动写入数据集。

无需 GPU 的协议回归测试：

```bash
python -m unittest discover -s AiApiServer/tests -p 'test_*.py'
```

测试需要 Pillow；使用替身模型，不验证真实模型质量。
