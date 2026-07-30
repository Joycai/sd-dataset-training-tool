# 数据集训练工具 (DataSet Training Tool)

<div align="center">
  <a href="https://flutter.dev" target="_blank">
    <img src="https://img.shields.io/badge/Framework-Flutter_3.35%2B-02569B?logo=flutter" alt="Flutter">
  </a>
  <a href="https://dart.dev" target="_blank">
    <img src="https://img.shields.io/badge/Language-Dart-0175C2?logo=dart" alt="Dart">
  </a>
  <a href="https://www.python.org" target="_blank">
    <img src="https://img.shields.io/badge/AI_Backend-Python_3.12-3776AB?logo=python&logoColor=white" alt="Python">
  </a>
  <a href="./LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/License-GPL_3.0-blue.svg" alt="License">
  </a>
  <br>
  <img src="https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Platform-macOS-000000?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux" alt="Linux">
</div>

![软件截图](./.images/preview_cn.png)

这是一个使用 Flutter 构建的桌面应用程序，用于高效管理和编辑图像数据集的描述文件（captions），并可搭配自带的 Python AI 后端（[AiApiServer](AiApiServer/)）完成 AI 自动打标，适用于 AI 模型训练的数据预处理阶段。

## ✨ 功能特性

### 三栏工作台

主界面为「资源浏览 → 预览/编辑 → 标签管理」的三栏布局，各栏宽度可拖动调整并自动记忆。

#### 左栏：资源面板
- **打开目录 / 刷新 / 包含子目录**：快速加载文件夹中的全部图片。
- **缩略图网格**：`contain` 模式完整显示，滑块实时调整列数。
- **标签筛选**：可按数据集标签过滤图库，只显示包含（或缺失）某标签的图片。
- **单击选中**加载到工作区；**双击**打开独立原生预览窗口。

#### 中栏：预览与 Caption 编辑
- **图片预览 + 编辑器上下分栏**，分割线可拖动。
- **Caption 编辑**：自动加载与图片同名的 `.txt` 文件（扩展名可配置），保存即写回。
- **标签化视图**：逗号分隔的 caption 可切换为标签（Chip）视图，支持双击编辑、删除、拖拽排序，改动与文本框双向同步。
- **标签补全**：手工输入标签时按 Danbooru 词典实时给出建议，按热度排序并区分分类；`↑`/`↓` 选择、`Tab` 或 `Enter` 补全、`F1` 打开该标签的 wiki。补全出的标签沿用你在 AI 参数里设定的书写风格（下划线转空格、括号转义），不会和 AI 打标结果写成两种拼法。
- **本地标签**：当前数据集里用过的、以及标签库里的标签，只要 Danbooru 词典没收录（自定义触发词、你自己的角色名等），同样进入补全候选，用空心圆点和「本地标签 · N 张图在用」标注，并保证占据列表末尾若干行——不会被一串同前缀的 Danbooru 标签挤掉。本地标签按你的原始拼写原样插入，不做风格转换。数据集里的标签需要至少出现在 **5 张图**上才会进入补全，免得把打错的字再喂回来；标签库里的标签是你手动挑的，不受这个门槛限制。
- **标签速查**：右键任意标签（编辑器或标签库）可查看其 Danbooru 收录量，并直达 wiki 或示例图搜索。词典里查不到的标签会写明「未收录 · 数据集中 N 张图在用」——用了几十张的是你自己的标签，只用过一次的多半是拼错了。
- **标签翻译**：给标签配上当前界面语言的译文，显示在标签旁（也可只在悬浮时显示，或完全关闭）。译文**只用于界面显示，绝不写入 caption 文件**；每种语言各存一份，独立于词典 CSV，可导入导出。补全列表和右键菜单里也能按译文反查标签——搜「长发」就能找到 `long_hair`。
- **AI 识别对比模式**：AI 结果与当前 caption 并排对比，逐个标签接受 / 拒绝后再写入，也可一键全部应用；顶栏提供全局退出对比。

### AI 辅助打标（AiApiServer）
- **本地 / 远程后端**：连接 [AiApiServer](AiApiServer/)（Flask HTTP 服务，默认 `http://127.0.0.1:50051`），支持 WD14 系列 tagger、多模态描述模型、RMBG 去背景、翻译等能力。
- **模型选择器**：按用途分组展示，附带服务端提供的元数据徽章（体量、语言、特性等）。
- **参数调节**：识别前可调整模型参数（如 threshold）。
- **批量打标**：对整个目录串行执行，支持**覆盖**与**追加**两种写入模式，带进度显示，可撤销。
- **批量仅识别**：只跑识别、结果进入各图片的对比模式，由你逐张审核后决定是否应用。

### 右栏：标签库与数据集标签

#### 标签库
- **公共标签库**：导入 / 增量添加 / 导出 / 清空，作为你的标准标签集。
- **分组管理**：标签可归入自定义颜色的分组，支持分组编辑模式、按组删除；导入导出携带分组信息。
- **智能对比**：当前图片**包含**的公共标签绿色高亮，**缺失**的橙色高亮；点击即可增删。
- **新标签发现**：图片中存在但库中没有的标签以灰色展示，单击快速入库。

#### 数据集标签面板
- **全局聚合**：统计当前数据集全部标签及出现频次，支持排序切换。
- **点击筛选**：选中标签即过滤左栏图库。
- **全局批量编辑**：跨整个数据集重命名 / 删除某个标签，操作可**撤销**。

### 快捷键
| 快捷键 | 功能 |
|--------|------|
| `Ctrl+S` | 保存当前 caption |
| `Ctrl+E` | 对当前图片执行 AI 识别 |
| `Ctrl+F` | 聚焦标签库筛选框 |
| `←` / `→` | 切换上一张 / 下一张图片 |
| `Ctrl+Z` / `Ctrl+Shift+Z`（或 `Ctrl+Y`） | 撤销 / 重做批量标签操作 |
| `↑` / `↓`、`Tab`、`F1` | 标签补全列表：选择 / 补全 / 打开 wiki（仅在补全列表弹出时生效） |

### 图片预览窗口
- **独立原生窗口**：可随意缩放、拖动。
- 滚轮缩放、左键平移、左右按钮切换图片、一键复位（Fit to Screen）、另存图片。

### 设置
- **多语言**：内置中文和英文。
- **主题**：亮色 / 暗色 / 跟随系统。
- **界面字体**：系统默认 / HarmonyOS Sans / MiSans，选择后按需自动下载。
- **标签词典**：内置约 1.1 万条 Danbooru 标签（随包发布，离线可用，与 WD tagger 输出的词表一致）；也可一键下载按热度排序的前 10 万条完整词典，额外带别名、画师与作品分类。
- **编辑词典**：在设置里打开词典管理，可编辑任意标签的译文与注释、添加 Danbooru 没有的标签（带分类，会进入补全并排在最前）、导入导出译文，以及一键清除 AI 生成的译文（手写的会保留）。
- **从 Danbooru 获取**：粘贴 Danbooru 地址（wiki 页 / 投稿搜索 / 标签列表都行）或直接填标签名，读取其公开 API 拿到分类、收录量、`other_names`（Danbooru 自带的其他语言名称，多为日文）和 wiki 摘要。这些都只是**候选**，点一下才会填进译文或注释，不会自动写入。内置词典没收录但 Danbooru 有的标签，可一键按其真实分类加入词典。
- **让 AI 助手批量翻译**：直接跟助手说「把数据集里没翻译的标签翻成中文」即可。它会先按使用量列出待翻译的标签，角色 / 作品 / 画师会去查 Danbooru 的 `other_names` 而不是自己编，然后每次最多写 200 条。默认**不覆盖**已有译文，写入的每条都记为 AI 来源，不满意可一键全清而手写的保留。这些工具完全不碰 caption 文件。
- **AI 服务器地址**、**caption 扩展名**均可自定义。
- **数据导入导出**：把三样手工攒出来的东西打包成一个 JSON —— **LLM 后端配置**（可选是否含 API 密钥）、**自定义标签库**（分组、分组内外的标签、你自己加进词典的标签、以及**所有语言**的译文）、**预置提示词**。换机器或重装时导入即可恢复；内置词表和下载的 Danbooru 全量词典不在其中（这两样随时能重新获取）。导入时可选「保留本机已有」或「以文件为准」，**两种方式都只新增或更新，绝不删除**。
- **持久化**：语言、主题、窗口布局、目录、标签库等全部自动保存；支持一键重置。

## 🚀 快速开始

```sh
git clone <your-repository-url>
cd DataSetTrainingTool
flutter pub get
flutter run -d windows   # 或 macos / linux
```

各平台的完整环境要求、打包构建步骤，以及 AiApiServer 的 Python 环境配置（含无 GPU 时的 CPU 方案），请参阅指南文档：

> 📖 **[环境配置与构建指南](docs/ENVIRONMENT_GUIDE.md)**

## 🤖 AiApiServer（AI 后端）

AI 打标能力由子目录 [AiApiServer](AiApiServer/) 提供：Python 3.12 + Flask 的 HTTP 服务，支持 Windows / macOS / Linux，有 NVIDIA GPU 时走 CUDA 加速，无 GPU 时自动回退 CPU。

```sh
cd AiApiServer
pip install -r requirements.txt
python main.py    # 监听 0.0.0.0:50051
```

环境配置详情见 [环境配置与构建指南](docs/ENVIRONMENT_GUIDE.md)，端点协议见 [AiApiServer/README.md](AiApiServer/README.md)。

## 📚 更多文档

- [环境配置与构建指南](docs/ENVIRONMENT_GUIDE.md) — 各平台打包构建、AiApiServer Python 环境
- [入门指南](wiki/入门指南-CN.md) / [使用详解](wiki/使用详解-CN.md) / [设置说明](wiki/设置-CN.md)
- English README: [README.en.md](README.en.md)

## 📄 许可协议

本项目基于 **GNU General Public License v3.0** 许可协议。详情请参阅 [LICENSE](LICENSE) 文件。

## 👥 作者

- **[Joycai](https://github.com/Joycai)** - 初始想法与贡献
- **Gemini (Google)** / **Claude (Anthropic)** - 编码与实现
