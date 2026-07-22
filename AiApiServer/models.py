import torch

device = torch.device("cuda") if torch.cuda.is_available() else "cpu"

print("Have CUDA: ", torch.cuda.is_available())
print("CUDA Count: ", torch.cuda.device_count())

print("Using interrogator device:", device)

from modules import (
    tagger,
    captioning,
    paths,
    devices,
    editor,
    translator
)

paths.initialize()

BLIP2_CAPTIONING_NAMES = [
    "Salesforce/blip2-opt-2.7b",
    "Salesforce/blip2-opt-2.7b-coco",
    "Salesforce/blip2-opt-6.7b",
    "Salesforce/blip2-opt-6.7b-coco",
    "Salesforce/blip2-flan-t5-xl",
    "Salesforce/blip2-flan-t5-xl-coco",
    "Salesforce/blip2-flan-t5-xxl",
]

FLORENCE2_CAPTIONING_NAMES = [
    "microsoft/Florence-2-base-ft",
    "microsoft/Florence-2-base",
    "microsoft/Florence-2-large-ft",
    "microsoft/Florence-2-large",
    "thwri/CogFlorence-2.2-Large",
]

FLORENCE2PG_CAPTIONING_NAMES = [
    "MiaoshouAI/Florence-2-large-PromptGen-v2.0",
    "MiaoshouAI/Florence-2-base-PromptGen-v2.0",
]

MOONDREAM2_CAPTIONING_NAMES = [
    "vikhyatk/moondream2",
]

JOYCAPTION_CAPTIONING_NAMES = [
    "fancyfeast/llama-joycaption-alpha-two-hf-llava",
    "fancyfeast/llama-joycaption-beta-one-hf-llava",
    "NeoChen1024/llama-joycaption-beta-one-hf-llava-FP8-Dynamic"
]

QWEN25_CAPTIONING_NAMES = [
    ("Qwen/Qwen2.5-VL-3B-Instruct", True),
    ("huihui-ai/Qwen2.5-VL-3B-Instruct-abliterated", True),
    ("Qwen/Qwen2.5-VL-7B-Instruct", True),
    ("huihui-ai/Qwen2.5-VL-7B-Instruct-abliterated", True),
    ("unsloth/Qwen2.5-VL-7B-Instruct-unsloth-bnb-4bit", True),
    ("prithivMLmods/DeepCaption-VLA-7B", True),
    ("internlm/CapRL-3B", False),
]

KEYE_CAPTIONING_NAMES = [
    ("Kwai-Keye/Keye-VL-1_5-8B", True),
]

WD_TAGGER_NAMES = [
    "SmilingWolf/wd-v1-4-convnext-tagger",
    "SmilingWolf/wd-v1-4-convnext-tagger-v2",
    "SmilingWolf/wd-v1-4-convnextv2-tagger-v2",
    "SmilingWolf/wd-v1-4-swinv2-tagger-v2",
    "SmilingWolf/wd-v1-4-vit-tagger",
    "SmilingWolf/wd-v1-4-vit-tagger-v2",
    "SmilingWolf/wd-v1-4-moat-tagger-v2",
    "SmilingWolf/wd-vit-tagger-v3",
    "SmilingWolf/wd-swinv2-tagger-v3",
    "SmilingWolf/wd-convnext-tagger-v3",
    "SmilingWolf/wd-vit-large-tagger-v3",
    "SmilingWolf/wd-eva02-large-tagger-v3",
]

FLORENCE2PG_COMMANDS = [
    "<GENERATE_TAGS>",
    "<CAPTION>",
    "<DETAILED_CAPTION>",
    "<MORE_DETAILED_CAPTION>",
    "<ANALYZE>",
    "<MIXED_CAPTION>",
    "<MIXED_CAPTION_PLUS>",
]

FLORENCE2_COMMANDS = [
    "<CAPTION>",
    "<DETAILED_CAPTION>",
    "<MORE_DETAILED_CAPTION>",
    "<CAPTION_TO_PHRASE_GROUNDING>",
    "<OD>",
]

MOONDREAM2_COMMANDS = [
    "Short_caption",
    "Normal_caption",
    "Visual_query",
    "Object_detection",
    "Pointing",
]

BG_REMOVAL = [
    "briaai/RMBG-2.0",
    "ZhengPeng7/BiRefNet",
    "ZhengPeng7/BiRefNet_HR",
    "zhengpeng7/BiRefNet_lite",
    "ZhengPeng7/BiRefNet_lite-2K",
    "ZhengPeng7/BiRefNet-matting",
    "ZhengPeng7/BiRefNet_512x512",
]

SEED_X = [
    "ByteDance-Seed/Seed-X-PPO-7B",
    "ByteDance-Seed/Seed-X-PPO-7B-GPTQ-Int8",
    "ByteDance-Seed/Seed-X-PPO-7B-AWQ-Int4",
]

BG_REMOVAL_RESOLUTION = [
    (1024, 1024),
    (1024, 1024),
    (2048, 2048),
    (1024, 1024),
    (2560, 1440),
    (1024, 1024),
    (512, 512),
]

WD_TAGGER_THRESHOLDS = [
    0.35,
    0.35,
    0.35,
    0.35,
    0.35,
    0.35,
    0.35,
    0.25,
    0.25,
    0.25,
    0.26,
    0.52,
]  # v1: idk if it's okay  v2: P=R thresholds on each repo https://huggingface.co/SmilingWolf

INTERROGATORS = (
        [captioning.BLIP("blip")]
        + [captioning.BLIP2(name, "blip2") for name in BLIP2_CAPTIONING_NAMES]
        + [captioning.GITLarge("gitlarge")]
        + [captioning.Florence2(name, FLORENCE2_COMMANDS, "", False, "florence2") for name in
           FLORENCE2_CAPTIONING_NAMES]
        + [captioning.Florence2(name, FLORENCE2PG_COMMANDS, "", False, "florence2") for name in
           FLORENCE2PG_CAPTIONING_NAMES]
        + [captioning.Moondream2(name, MOONDREAM2_COMMANDS, "", False, "moondream2") for name in
           MOONDREAM2_CAPTIONING_NAMES]
        + [captioning.JoyCaption(name, "", False, "joycaption") for name in JOYCAPTION_CAPTIONING_NAMES]
        + [captioning.Qwen25Caption(name, "", False, video, "qwen25") for name, video in QWEN25_CAPTIONING_NAMES]
        + [captioning.KeyeCaption(name, "", False, video, "keye") for name, video in KEYE_CAPTIONING_NAMES]
        + [tagger.DeepDanbooru(0.5, "dd")]
        + [
            tagger.WaifuDiffusion(name, WD_TAGGER_THRESHOLDS[i], "wd")
            for i, name in enumerate(WD_TAGGER_NAMES)
        ]
)

INTERROGATOR_NAMES = [it.name() for it in INTERROGATORS]

INTERROGATOR_MAP = dict(zip(INTERROGATOR_NAMES, INTERROGATORS))

EDITORS = (
    [
        editor.RMBG2(name, BG_REMOVAL_RESOLUTION[i], "rmbg2")
        for i, name in enumerate(BG_REMOVAL)
    ]
)

EDITOR_NAMES = [it.name() for it in EDITORS]

EDITOR_MAP = dict(zip(EDITOR_NAMES, EDITORS))

TRANSLATORS = (
    [
        translator.seed_x(name, "seedx")
        for i, name in enumerate(SEED_X)
    ]
)

TRANSLATOR_NAMES = [it.name() for it in TRANSLATORS]

TRANSLATOR_MAP = dict(zip(TRANSLATOR_NAMES, TRANSLATORS))

# Maps a model's type tag to the picker category exposed via /getconfig.
# Anything not listed is a natural-language captioning model.
MODEL_CATEGORIES = {
    "wd": "tag",
    "dd": "tag",
    "rmbg2": "edit",
    "seedx": "translate",
}

# Picker metadata keyed by model name (the INTERROGATOR_MAP key). Missing
# entries and missing fields fall back to neutral defaults in ModelBaseInfo,
# so adding a model without annotating it here is harmless — it just shows
# without badges. VramGB is a rough fp16/default-precision estimate.
MODEL_METADATA = {
    # --- WD taggers, v3: current generation ---
    "SmilingWolf/wd-eva02-large-tagger-v3": {
        "recommended": True, "vram_gb": 2,
        "description": "EVA02 骨干的 WD 打标模型,v3 系列中准确率最高,训练数据截至 2024 年,输出 Danbooru 风格标签。",
        "advice": "动漫图打标首选。注意其默认阈值 0.52 与其它模型不同,一般无需手动调整。",
    },
    "SmilingWolf/wd-vit-large-tagger-v3": {
        "vram_gb": 2,
        "description": "ViT-Large 骨干的 WD v3 打标模型,准确率仅次于 EVA02 版,速度略快。",
        "advice": "EVA02 结果不理想时的备选,可与之交叉对比。",
    },
    "SmilingWolf/wd-vit-tagger-v3": {
        "vram_gb": 1,
        "description": "ViT 骨干的 WD v3 标准打标模型,速度与准确率均衡。",
        "advice": "批量打标时速度优先的选择。",
    },
    "SmilingWolf/wd-swinv2-tagger-v3": {
        "vram_gb": 1,
        "description": "SwinV2 骨干的 WD v3 标准打标模型,与 ViT 版水平相当,标签倾向略有差异。",
        "advice": "可与 ViT v3 交叉对比,取并集或交集。",
    },
    "SmilingWolf/wd-convnext-tagger-v3": {
        "vram_gb": 1,
        "description": "ConvNeXt 骨干的 WD v3 标准打标模型。",
        "advice": "与其它 v3 标准档水平相当,按习惯选用即可。",
    },
    # --- WD taggers, v1.4: superseded by v3 ---
    "SmilingWolf/wd-v1-4-moat-tagger-v2": {
        "legacy": True, "vram_gb": 1,
        "description": "MoAT 骨干的 WD v1.4 打标模型,曾是 v2 时代最准的一档,训练数据较旧。",
        "advice": "建议改用 v3 系列,新角色和新画风标签覆盖更全。",
    },
    "SmilingWolf/wd-v1-4-convnext-tagger": {
        "legacy": True, "vram_gb": 1,
        "description": "ConvNeXt 骨干的 WD v1.4 初版打标模型。",
        "advice": "已被 v2/v3 取代,仅为兼容保留。",
    },
    "SmilingWolf/wd-v1-4-convnext-tagger-v2": {
        "legacy": True, "vram_gb": 1,
        "description": "ConvNeXt 骨干的 WD v1.4 v2 打标模型。",
        "advice": "建议改用 wd-convnext-tagger-v3。",
    },
    "SmilingWolf/wd-v1-4-convnextv2-tagger-v2": {
        "legacy": True, "vram_gb": 1,
        "description": "ConvNeXtV2 骨干的 WD v1.4 v2 打标模型。",
        "advice": "建议改用 v3 系列。",
    },
    "SmilingWolf/wd-v1-4-swinv2-tagger-v2": {
        "legacy": True, "vram_gb": 1,
        "description": "SwinV2 骨干的 WD v1.4 v2 打标模型。",
        "advice": "建议改用 wd-swinv2-tagger-v3。",
    },
    "SmilingWolf/wd-v1-4-vit-tagger": {
        "legacy": True, "vram_gb": 1,
        "description": "ViT 骨干的 WD v1.4 初版打标模型。",
        "advice": "已被 v2/v3 取代,仅为兼容保留。",
    },
    "SmilingWolf/wd-v1-4-vit-tagger-v2": {
        "legacy": True, "vram_gb": 1,
        "description": "ViT 骨干的 WD v1.4 v2 打标模型。",
        "advice": "建议改用 wd-vit-tagger-v3。",
    },
    "DeepDanbooru": {
        "legacy": True, "vram_gb": 1,
        "description": "最早的 Danbooru 标签模型,准确率已明显落后于 WD 系列。",
        "advice": "仅为兼容保留,不建议新任务使用。",
    },
    # --- Florence-2 family ---
    "MiaoshouAI/Florence-2-large-PromptGen-v2.0": {
        "recommended": True, "vram_gb": 2,
        "description": "专为训练集打标微调的 Florence-2,支持 <GENERATE_TAGS> 直接输出标签、<MIXED_CAPTION> 输出标签加自然语言混合描述。",
        "advice": "轻量快速,低显存机器做自然语言打标的首选。",
    },
    "MiaoshouAI/Florence-2-base-PromptGen-v2.0": {
        "vram_gb": 1,
        "description": "PromptGen 的 base 档,体积更小速度更快,描述细节略逊于 large。",
        "advice": "追求批量速度时选它,质量优先选 large。",
    },
    "microsoft/Florence-2-large-ft": {
        "vram_gb": 2,
        "description": "微软 Florence-2 large 指令微调版,支持多档粒度描述与物体检测,极小极快。",
        "advice": "通用描述用它;做训练集打标建议用 PromptGen 版。",
    },
    "microsoft/Florence-2-large": {
        "vram_gb": 2,
        "description": "微软 Florence-2 large 预训练版,未做指令微调。",
        "advice": "一般建议用 -ft 微调版,输出更稳定。",
    },
    "microsoft/Florence-2-base-ft": {
        "vram_gb": 1,
        "description": "微软 Florence-2 base 指令微调版,0.23B 参数,速度极快。",
        "advice": "CPU 也能勉强跑,适合快速过一遍粗描述。",
    },
    "microsoft/Florence-2-base": {
        "vram_gb": 1,
        "description": "微软 Florence-2 base 预训练版,未做指令微调。",
        "advice": "一般建议用 -ft 微调版,输出更稳定。",
    },
    "thwri/CogFlorence-2.2-Large": {
        "vram_gb": 2,
        "description": "社区用 CogVLM 生成数据再微调的 Florence-2 large,描述更长更细。",
        "advice": "想要比官方版更详细的描述时选它。",
    },
    # --- Moondream2 ---
    "vikhyatk/moondream2": {
        "vram_gb": 4,
        "description": "约 2B 的小型视觉语言模型,除描述外还支持视觉问答与物体检测。",
        "advice": "需要用自定义问题问图片内容时很好用。",
    },
    # --- JoyCaption ---
    "fancyfeast/llama-joycaption-beta-one-hf-llava": {
        "uncensored": True, "vram_gb": 18,
        "description": "基于 Llama 3.1 8B 的社区打标模型,专为扩散模型训练集设计,描述详尽且不回避 NSFW 内容。",
        "advice": "显存 24G 以上选原版;显存紧张请用 FP8 量化版。",
    },
    "NeoChen1024/llama-joycaption-beta-one-hf-llava-FP8-Dynamic": {
        "recommended": True, "uncensored": True, "vram_gb": 10,
        "description": "JoyCaption beta-one 的 FP8 量化版,显存约省一半,质量损失很小。",
        "advice": "10-16G 显存做详细自然语言打标的首选。",
    },
    "fancyfeast/llama-joycaption-alpha-two-hf-llava": {
        "legacy": True, "uncensored": True, "vram_gb": 18,
        "description": "JoyCaption 的早期 alpha 版本。",
        "advice": "建议改用 beta-one 或其 FP8 量化版。",
    },
    # --- Qwen2.5-VL family ---
    "Qwen/Qwen2.5-VL-7B-Instruct": {
        "vram_gb": 16,
        "description": "阿里通义开源视觉语言模型 7B 版,通用理解与指令跟随能力强,中文支持好,支持视频。",
        "advice": "16G 以上显存、需要按自定义指令输出描述时的主力选择。",
    },
    "Qwen/Qwen2.5-VL-3B-Instruct": {
        "vram_gb": 7,
        "description": "Qwen2.5-VL 的 3B 轻量版,能力弱于 7B 但显存需求减半。",
        "advice": "8G 显存跑通用视觉语言模型的选择。",
    },
    "huihui-ai/Qwen2.5-VL-7B-Instruct-abliterated": {
        "uncensored": True, "vram_gb": 16,
        "description": "Qwen2.5-VL-7B 的去审查版,移除了拒答行为,其余能力与原版一致。",
        "advice": "原版对内容拒答时改用它。",
    },
    "huihui-ai/Qwen2.5-VL-3B-Instruct-abliterated": {
        "uncensored": True, "vram_gb": 7,
        "description": "Qwen2.5-VL-3B 的去审查版,移除了拒答行为。",
        "advice": "低显存且需要无审查输出时选它。",
    },
    "unsloth/Qwen2.5-VL-7B-Instruct-unsloth-bnb-4bit": {
        "vram_gb": 6,
        "description": "Qwen2.5-VL-7B 的 4bit 量化版,显存压到约 6G,质量略有下降。",
        "advice": "想在低显存上用 7B 能力时的折中选择。",
    },
    "prithivMLmods/DeepCaption-VLA-7B": {
        "vram_gb": 16,
        "description": "基于 Qwen2.5-VL 微调、专攻精细属性描述的打标模型。",
        "advice": "需要强调服饰、材质等细节属性时可以试试。",
    },
    "internlm/CapRL-3B": {
        "vram_gb": 7,
        "description": "用强化学习训练描述质量的 3B 模型,小体积但描述水平对标更大模型。不支持视频。",
        "advice": "低显存下追求描述质量的备选。",
    },
    # --- Keye ---
    "Kwai-Keye/Keye-VL-1_5-8B": {
        "vram_gb": 17,
        "description": "快手开源的 8B 视觉语言模型,主打视频理解,短视频内容场景表现好。",
        "advice": "视频素材打标优先考虑;纯图片场景 Qwen2.5-VL 更通用。",
    },
    # --- Legacy captioners ---
    "BLIP": {
        "legacy": True, "vram_gb": 2,
        "description": "早期图像描述模型,速度快但描述简短笼统。",
        "advice": "已被 Florence-2 等全面超越,仅为兼容保留。",
    },
    "GIT-large-COCO": {
        "legacy": True, "vram_gb": 2,
        "description": "微软早期图像描述模型,与 BLIP 同时代。",
        "advice": "仅为兼容保留,不建议新任务使用。",
    },
    "Salesforce/blip2-opt-2.7b": {
        "legacy": True, "vram_gb": 8,
        "description": "BLIP2 接 OPT-2.7B 解码器的版本,描述能力一般。",
        "advice": "同显存下 Florence-2 或 Qwen2.5-VL-3B 是更好的选择。",
    },
    "Salesforce/blip2-opt-2.7b-coco": {
        "legacy": True, "vram_gb": 8,
        "description": "BLIP2 OPT-2.7B 在 COCO 上微调的版本,描述风格更贴近人工标注短句。",
        "advice": "仅为兼容保留。",
    },
    "Salesforce/blip2-opt-6.7b": {
        "legacy": True, "vram_gb": 16,
        "description": "BLIP2 接 OPT-6.7B 解码器的版本,显存需求大。",
        "advice": "同显存下 Qwen2.5-VL-7B 全面更强。",
    },
    "Salesforce/blip2-opt-6.7b-coco": {
        "legacy": True, "vram_gb": 16,
        "description": "BLIP2 OPT-6.7B 的 COCO 微调版。",
        "advice": "仅为兼容保留。",
    },
    "Salesforce/blip2-flan-t5-xl": {
        "legacy": True, "vram_gb": 10,
        "description": "BLIP2 接 Flan-T5-XL 解码器的版本,指令遵循略好于 OPT 版。",
        "advice": "仅为兼容保留。",
    },
    "Salesforce/blip2-flan-t5-xl-coco": {
        "legacy": True, "vram_gb": 10,
        "description": "BLIP2 Flan-T5-XL 的 COCO 微调版。",
        "advice": "仅为兼容保留。",
    },
    "Salesforce/blip2-flan-t5-xxl": {
        "legacy": True, "vram_gb": 24,
        "description": "BLIP2 最大的版本,接 Flan-T5-XXL 解码器,显存需求极大。",
        "advice": "不建议使用,同显存下有大量更强的现代模型。",
    },
}


def init():
    devices.init_interrogator()
