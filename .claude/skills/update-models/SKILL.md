---
name: update-models
description: 向 AiApiServer 添加/更新/下架 AI 模型(打标、描述、抠图、翻译)的完整流程:改哪些清单、写什么元数据、有哪些接入约束、如何校验。用户说"加模型"、"更新模型清单"、"有没有新模型"、"下架某模型"时使用。
---

# AiApiServer 模型清单更新流程

模型清单与元数据全部集中在 `AiApiServer/models.py`,是唯一数据源。Flutter 端
(`lib/views/panels/ai_params_dialog.dart` 的分组选择器)只消费 `/getconfig`
返回的字段,加模型**不需要动 app 端代码**,badge 与分组自动生效。

## 1. 调研阶段(加新模型前必做)

- 以 HuggingFace repo 页为准:确认确切 repo id(大小写照抄)、发布日期、
  参数量、license、加载接口(transformers 类名、是否 trust_remote_code)。
- **先查加载约束再决定加不加**,见第 3 节。`requirements.txt` 里 transformers
  是钉死的版本——要求更高版本的模型不能加,除非单独开分支升级依赖。
- 多个候选时按"训练数据新鲜度 / license / 显存 / 接口成本"权衡,优先
  Apache/MIT license;GPL、BSL、带 MAU 条款的 license 要在元数据 advice
  或 PR 描述里注明。

## 2. 改哪里:按模型类型对号入座

全部在 `AiApiServer/models.py`:

| 模型类型 | 清单常量 | 备注 |
|---|---|---|
| WD 风格 tagger (ONNX) | `WD_TAGGER_NAMES` | **与 `WD_TAGGER_THRESHOLDS` 按下标一一对应**,两个列表必须同步插入 |
| BLIP2 | `BLIP2_CAPTIONING_NAMES` | legacy 系,一般只减不增 |
| Florence-2 | `FLORENCE2_CAPTIONING_NAMES` / `FLORENCE2PG_CAPTIONING_NAMES` | PG = PromptGen,指令集不同 |
| Moondream | `MOONDREAM2_CAPTIONING_NAMES` | |
| JoyCaption (llava) | `JOYCAPTION_CAPTIONING_NAMES` | |
| Qwen2.5-VL 家族 | `QWEN25_CAPTIONING_NAMES` | 元素是 `(name, video_supported)` 元组 |
| Keye-VL | `KEYE_CAPTIONING_NAMES` | 同上元组格式 |
| 背景移除 | `BG_REMOVAL` | **与 `BG_REMOVAL_RESOLUTION` 按下标一一对应**;动态分辨率模型默认填 `(1024, 1024)` |
| 翻译 | `SEED_X` | |

新模型家族(现有加载器都不适配)需要在 `AiApiServer/modules/interrogators/`
(或 editors/translators)下新写加载模块、在 `captioning.py`/`tagger.py`/
`editor.py`/`translator.py` 包一层、在 `models.py` 的 `INTERROGATORS`
组装处接入、并在 `main.py` 的 `taggers_params()` 里加参数分支——这属于
大改动,单独开分支。

## 3. 加载约束(容易踩的坑)

- **transformers 版本钉死**在 `requirements.txt`(当前 4.56.1)。
  Qwen3-VL 家族(含 CapRL-Qwen3VL、Qwen3-VL abliterated 微调)要求
  ≥ 4.57 且用 `Qwen3VLForConditionalGeneration`,**不能**塞进
  `QWEN25_CAPTIONING_NAMES`——现有 qwen25 模块用的是
  `Qwen2_5_VLForConditionalGeneration`。基于 Qwen2.5-VL 的微调
  (如 DeepCaption-VLA 系)可以直接进 qwen25 清单。
- **WD tagger 假设 ONNX 格式**:`waifu_diffusion_tagger.py` 按
  `model.onnx` + `selected_tags.csv` 下载。第三方 tagger(如 pixai-tagger
  的 deepghs ONNX 移植)的标签文件格式未必一致,接入前先核对。
- repo id 大小写照 HF 页面抄,清单内保持一致(HF 解析不区分大小写,
  但清单里混用会显得混乱)。
- `name()` 返回 repo path,但 BLIP/GIT-large-COCO/DeepDanbooru 三个是
  硬编码短名——元数据表的 key 要用实际 `name()` 值。

## 4. 元数据表 `MODEL_METADATA`

每个 interrogator 都必须有条目(校验脚本强制);editor/translator 可选但
建议写。字段(全部可省,省略即中性默认):

- `recommended: True` — 同组同显存档的首选,**每组保持 1-3 个**,别通胀
- `uncensored: True` — abliterated / JoyCaption 系
- `legacy: True` — 被更新版本取代;**新版上位时旧版要同步标 legacy**,
  且 advice 指向新版(例:V1 → "已被 V2.0 取代,建议改用 xxx")
- `vram_gb` — fp16/默认精度的粗略估算,给用户选型用,不必精确
- `description` — 一两句中文:是什么、什么架构、特点
- `advice` — 一句中文使用建议:什么场景选它 / 为什么别用
- 文案**只写中文单语**(设计决策);要双语时加 `DescriptionEn` 字段而不是改结构

分组(tag/caption/edit/translate)由 `MODEL_CATEGORIES` 按 type tag 自动
推导,不写在元数据里。

## 5. 校验(改完必跑)

```bash
python .claude/skills/update-models/scripts/check_metadata.py
python -m py_compile AiApiServer/models.py AiApiServer/main.py
```

脚本校验:interrogator 元数据全覆盖、无陈旧 key、字段名合法、
平行列表(names/thresholds、removal/resolution)长度一致。

Flutter 端回归(选择器测试):

```bash
flutter test test/ai_params_dialog_test.dart
```

如果服务端在跑,`GET /getconfig` 肉眼确认新字段;模型真实加载验证
(下载权重、跑一张图)需要 GPU 环境,PR 里注明是否做过。

## 6. 下架模型

优先做法是**标 `legacy: True` 而不是删除**(旧配置里存的模型名还指向它,
删除会让 interrogate 请求 404)。确要删除时:清单行、平行列表对应行、
元数据条目三处同删,然后跑校验脚本。
