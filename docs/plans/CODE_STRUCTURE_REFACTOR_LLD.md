# 代码结构规范化 —— 详细设计（LLD）

> 范围：`lib/`、`test/` 的分包、依赖方向、代码风格与工程配置，使其符合 Flutter / Effective Dart 惯例。
> **不改任何运行时行为**：除 `MyApp` 改名与一个常量下沉外，全部是文件移动、import 改写与格式化。
> 执行步骤、验收与提交拆分见 [CODE_STRUCTURE_REFACTOR_PLAN.md](CODE_STRUCTURE_REFACTOR_PLAN.md)；长期约定见 [../ARCHITECTURE.md](../ARCHITECTURE.md)。

---

## 1. 现状问题（改造前，基线 `e68c352`）

| # | 类别 | 问题 | 证据 |
| --- | --- | --- | --- |
| P1 | 依赖方向 | `models/` 依赖 `state/` | `models/caption_type.dart` import `state/dataset_state.dart`，只为读 `DatasetState.supportedExtensions` |
| P2 | 依赖方向 | `services/` 依赖 `state/` 与根目录 `AppState` | `services/data_transfer.dart` → `app_state.dart`；`services/agent/*` 中 6 个文件 → `state/dataset_state.dart`、`state/tag_ops.dart`、`state/ai_tagger_state.dart` |
| P3 | 依赖方向 | `widgets/` 依赖 `views/` | `icon_nav_rail.dart` → `views/settings_view.dart`、两个 dialog；`tag_context_menu.dart` → `tag_dictionary_dialog.dart` |
| P4 | 目录归属 | `ChangeNotifier` 放在 `lib/` 根 | `lib/app_state.dart`，而同类都在 `state/` |
| P5 | 目录归属 | 对话框与面板混放 | `views/panels/` 20 个文件里 12 个是 `*_dialog.dart` |
| P6 | 目录归属 | 只被工作台壳使用的组件放在通用 `widgets/` | `icon_nav_rail` / `workbench_top_bar` / `status_bar` 仅被 `workbench_view.dart` 引用 |
| P7 | 测试组织 | `test/` 下 73 个测试文件平铺 | 未按 `lib/` 镜像，难以定位被测对象 |
| S1 | 风格 | 49 个文件不符合 `dart format` | 绝大多数在 `test/` |
| S2 | 风格 | 71 处 import 分组/排序不规范 | 例如 `main.dart` 三组 import 之间无空行 |
| S3 | 风格 | 异步调用丢 Future | `agent_chat_panel.dart` 未 await/unawaited；`tag_library_panel.dart` 的 `void async` |
| S4 | 风格 | analyzer 2 个 warning | `test/tag_ai_group_test.dart` `unused_element_parameter`（参数只经重定向构造传入，属误报） |
| C1 | 工程配置 | `pubspec.yaml` 仍是模板描述 `"A new Flutter project."`；打包工具 `msix` 放在 `dependencies` | — |
| C2 | 工程配置 | 根 Widget 仍叫模板名 `MyApp`；`l10n.yaml` 残留一行注释掉的配置 | — |
| C3 | 工程配置 | CI 不校验格式；方案文档散落在仓库根目录 | `.github/workflows/dart.yml`；`AI_TAGGER_INTEGRATION_PLAN.md` 等 |

---

## 2. 目标结构

```text
lib/
├── main.dart                 # 入口 + DatasetToolkitApp
├── app_info.dart             # 版本号等常量（bump-version skill 维护）
├── l10n/                     # .arb + gen-l10n 生成物
├── models/                   # 纯数据与纯逻辑
│   └── image_formats.dart    # 新增：supportedImageExtensions
├── theme/                    # 设计 token 与主题
├── utils/                    # 纯工具函数
├── services/                 # I/O 与外部系统（不依赖 state）
│   └── llm/                  # LLM 客户端
├── agent/                    # ← 原 services/agent/：Agent 运行时与工具
├── state/                    # ChangeNotifier 与驱动它们的控制器
│   ├── app_state.dart        # ← 原 lib/app_state.dart
│   └── data_transfer.dart    # ← 原 services/data_transfer.dart
├── widgets/                  # 可复用 UI 组件（不依赖 views）
└── views/
    ├── workbench/            # 主窗口壳：workbench_view + 顶栏/导航栏/状态栏
    ├── panels/               # 停靠面板及其共享件（含 tag_context_menu）
    ├── dialogs/              # 全部 show…Dialog 模态框（settings 除外）
    ├── settings_view.dart    # SettingsView 页面 + showSettingsDialog 外壳，页面为主，留在根
    └── image_preview_window.dart

test/                         # 镜像 lib/，widget_test.dart 为 App 冒烟测试保留在根
├── agent/  models/  services/{,llm/}  state/  theme/  utils/  widgets/
└── views/{dialogs,panels}/
```

---

## 3. 分层与依赖矩阵

行 = 发起 import 的层，列 = 被 import 的层。✅ 允许，— 禁止，⚠ 允许但为设计上的双向依赖。

| from \ to | views | widgets | state | agent | services | models | theme | utils | l10n | app_info |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **views** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **widgets** | — | ✅ | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **state** | — | — | ✅ | ⚠ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **agent** | — | — | ⚠ | ✅ | ✅ | ✅ | — | ✅ | ✅ | ✅ |
| **services** | — | — | — | — | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| **models** | — | — | — | — | — | ✅ | — | — | — | — |
| **theme** | — | — | — | — | — | ✅ | ✅ | — | — | — |
| **utils** | — | — | — | — | — | ✅ | — | ✅ | — | — |

设计决策：

- **`services/` 不得依赖 `state/`**。service 是无 UI 状态的 I/O 封装，可被任意层复用；反向依赖会让 service 无法脱离 Provider 树单测。
- **`agent/` 与 `state/` 双向依赖是有意为之**：`AgentChatState` 持有 `AgentSession`，而 Agent 工具（改 caption、改标签库）必须经由 `DatasetState` / `TagOps` 落盘，才能进入撤销历史、触发 UI 刷新。它们本质是"应用层用例"，不是 service，因此独立成 `lib/agent/` 特性目录，而不是留在 `services/` 里破坏上一条规则。
- **`services/settings_service.dart` → `theme/` 保留**：它用 `AppMetrics.navigator/inspector` 作面板默认宽度。`theme/` 是不依赖任何上层的叶子层，此依赖不形成环。
- **`widgets/` 可以读 `state/`、`services/`**：本项目的 widgets 是"应用内可复用"，而非"跨项目可复用"，允许 `context.watch<AppState>()`；但不得知道任何具体页面/对话框（不依赖 `views/`）。

---

## 4. 模块级设计

### 4.1 `models/image_formats.dart`（新增，解决 P1）

```dart
/// Image file extensions the app treats as dataset images, lowercased with a
/// leading dot. A caption type can never claim one of these — see
/// `normalizeCaptionExtension`.
const Set<String> supportedImageExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp',
};
```

- `models/caption_type.dart`：`import '../state/dataset_state.dart'` → `import 'image_formats.dart'`；`normalizeCaptionExtension` 内 `DatasetState.supportedExtensions.contains` → `supportedImageExtensions.contains`。
- `state/dataset_state.dart`：保留 `static const supportedExtensions = supportedImageExtensions;` 作为别名，现有调用点（扫描目录）零改动，集合内容与原来逐项一致。

### 4.2 `lib/app_state.dart` → `lib/state/app_state.dart`（P4）

纯移动。`AppState` 是全局 `ChangeNotifier`，与 `DatasetState` 等同属状态层。影响 15 个 views、3 个 widgets、`state/agent_chat_state.dart`、`data_transfer.dart`、`main.dart` 及对应测试的 import。

### 4.3 `services/data_transfer.dart` → `state/data_transfer.dart`（P2）

`DataTransfer` 不做任何 I/O：它只读写 `AppState` 的公开 mutator（`updateLlmProviders`、`importLibraryJson`、`addPromptPresets`……），把应用状态与 `DataBundle` 互转。职责是"状态控制器"，归入 `state/`。同步修正 `models/data_bundle.dart` 文档注释里的路径。

### 4.4 `services/agent/` → `lib/agent/`（P2）

12 个文件整体平移，文件名不变：

`agent_session` `agent_tools` `caption_edit_tools` `caption_variant_tools` `character_sheet` `context_budget` `dataset_tools` `json_caption_tools` `media_tools` `merge_rule_tools` `tag_library_tools` `tag_translation_tools`

原先对 `../llm/…` 的相对引用改写为 `../services/llm/…`。

### 4.5 `views/` 重组（P3、P5、P6）

| 原路径 | 新路径 | 理由 |
| --- | --- | --- |
| `views/panels/{ai_params,batch_tag,caption_type,character_sheet,data_transfer,llm_probe,llm_profile,prompt_preset,tag_ai_group,tag_dictionary,tag_group,tag_merge}_dialog.dart`（12 个） | `views/dialogs/` | 模态框与停靠面板分开 |
| `views/workbench_view.dart` | `views/workbench/workbench_view.dart` | 主窗口壳自成一组 |
| `widgets/icon_nav_rail.dart` | `views/workbench/icon_nav_rail.dart` | 依赖 settings_view 与两个 dialog（P3），且只被工作台使用 |
| `widgets/workbench_top_bar.dart` | `views/workbench/workbench_top_bar.dart` | 只被工作台使用 |
| `widgets/status_bar.dart` | `views/workbench/status_bar.dart` | 只被工作台使用 |
| `widgets/tag_context_menu.dart` | `views/panels/tag_context_menu.dart` | 会打开 `tag_dictionary_dialog`（P3）；被 4 个面板共享 |

`widgets/resize_handle.dart` 虽然也只被工作台用，但它是通用拖拽手柄，不依赖任何业务，保留在 `widgets/`。

### 4.6 测试镜像（P7）

**映射规则**：测试文件放到其"主要被测文件"在 `lib/` 中对应的目录下，文件名不变。

- 主要被测文件 = 测试 import 的 `package:dataset_training_tool/...` 中，与测试文件名最相近的那个（先按脚本做名称相似度匹配，再人工复核）。
- 人工修正的 5 例（名称匹配命中错误的层）：

| 测试 | 脚本猜测 | 最终 | 依据 |
| --- | --- | --- | --- |
| `dataset_tags_view_test` | `state/` | `views/panels/` | 测的是标签库面板的"数据集"标签页 |
| `glass_backdrop_group_test` | `theme/` | `widgets/` | 被测对象是 `widgets/panel_widgets.dart` 的 `GlassSurface` |
| `toolbar_overflow_test` | `state/` | `views/panels/` | 测 `CaptionPanel` 工具栏布局 |
| `agent_turn_limit_test` | `state/` | `views/panels/` | 测 `agent_chat_panel` 的续跑卡片 UI |
| `llm_cost_repair_test` | `models/` | `services/llm/` | 测两个 LLM 客户端的 4xx 修复重放 |

- `test/widget_test.dart` 是 App 冒烟测试（pump 整个 `DatasetToolkitApp`），按 Flutter 模板惯例留在 `test/` 根。
- 结果分布：agent 14、models 13、services 4、services/llm 3、state 8、theme 2、utils 1、views/dialogs 8、views/panels 15、widgets 4，根目录 1。

测试一律使用 `package:` import，移动后仅需改写指向被移动 `lib/` 文件的 URI；测试中没有依赖 `test/…` 相对路径或 `Platform.script` 的夹具，移动不影响资源定位（`flutter test` 的工作目录始终是包根）。

---

## 5. import 改写算法

所有移动由一个一次性脚本完成（输入为 `旧路径 新路径` 映射表），保证 `git mv` 与 import 改写原子一致：

1. 枚举 `lib/`、`test/`、`tool/` 下全部 `.dart` 文件。
2. 对每个文件的每条 `import` / `export` / `part` 指令：
   - `dart:` 与第三方 `package:` 原样保留；
   - `package:dataset_training_tool/X` 解析为 `lib/X`；相对 URI 按**文件旧位置**解析为仓库路径；
   - 目标路径若在映射表中则替换为新路径；
   - 按原风格重新生成 URI：`package:` 仍写 `package:`，相对路径按**文件新位置**重新计算 `relpath`。
3. 写回全部文件后，逐个 `git mv`（保留重命名历史）。
4. `dart fix --apply --code=directives_ordering` 修正改写后的排序，再 `dart format`。

这样同时覆盖三种情况：别人引用被移动文件、被移动文件引用未移动文件、两个都被移动。

---

## 6. 风格与静态检查

### 6.1 `analysis_options.yaml`

在 `package:flutter_lints/flutter.yaml` 之上新增：

| 分组 | 规则 | 改造前违例数 | 处理 |
| --- | --- | --- | --- |
| 风格 | `always_declare_return_types` `prefer_single_quotes` `prefer_final_in_for_each` `type_annotate_public_apis` `use_super_parameters` `prefer_relative_imports` | 0 | 固化现状 |
| 风格 | `directives_ordering` | 71 | `dart fix` 自动修复 |
| 风格 | `prefer_final_locals` | 4 | `dart fix` 自动修复 |
| 异步正确性 | `unawaited_futures` | 2 | 手动包 `unawaited(...)` |
| 异步正确性 | `avoid_void_async` | 1 | `void … async` → `Future<void>` |
| 资源 | `cancel_subscriptions` `close_sinks` | 0 | 固化现状 |

`analyzer.exclude` 排除 `lib/l10n/app_localizations*.dart`（gen-l10n 生成物，CI 另有"生成物与 arb 一致"校验）。同时排除 `build/**` 与 `windows/**`、`macos/**`、`linux/**`：`flutter pub get` 会在 `windows/flutter/ephemeral/.plugin_symlinks`、`linux/flutter/ephemeral/.plugin_symlinks` 下以符号链接挂出插件源码（本机实测各约 160 个 `.dart` 文件），不排除则本地 analyze 会扫到第三方插件代码；这些目录不进 git，CI 上不受影响。

**评估后未启用**（违例多且收益存疑，避免无意义 churn）：`avoid_dynamic_calls`（20，集中在 JSON 解析）、`sort_constructors_first`（23）、`unnecessary_lambdas`（24）、`omit_local_variable_types`（7，与现有显式类型风格冲突）、`prefer_const_constructors`（2，flutter_lints 已不再默认启用）。

### 6.2 个别修复

- `views/panels/agent_chat_panel.dart`：`_startCharacterSheet` 中 `chat.startCharacterSheet(...)` 是有意的即发即弃（进度由 `AgentChatState` 通知），包 `unawaited()`。
- `views/panels/tag_library_panel.dart`：`_showTagMenu` 返回类型 `void` → `Future<void>`。
- `services/danbooru_api.dart`：格式化后 `if` 单行体换行，补花括号以满足 `curly_braces_in_flow_control_structures`。
- `test/services/tag_ai_group_test.dart`（C1 时位于 `test/tag_ai_group_test.dart`）：`_FakeLlm` 的 `toolCall` / `toolCallBatch` 由重定向构造改为各自的初始化列表，消除 `unused_element_parameter` 误报；行为不变（两个命名构造均有测试在用）。
- `test/widgets/glass_backdrop_group_test.dart`：`showDialog` 包 `unawaited()`。

---

## 7. 工程配置

| 文件 | 变更 |
| --- | --- |
| `pubspec.yaml` | `description` 改为真实描述；`msix` 从 `dependencies` 移到 `dev_dependencies`（`dart run msix:create` 对 dev 依赖同样可用，且不再被计入 App 依赖） |
| `lib/main.dart`、`test/widget_test.dart` | `MyApp` → `DatasetToolkitApp`（与 msix `display_name: Dataset Toolkit` 对应） |
| `l10n.yaml` | 删除残留注释行 |
| `.github/workflows/dart.yml` | analyze 之前新增 `dart format --output=none --set-exit-if-changed lib test tool` |
| 根目录方案文档 | `AI_TAGGER_INTEGRATION_PLAN.md`、`LLM_AGENT_INTEGRATION_PLAN.md` → `docs/plans/`（历史文档，正文中的旧路径不改写） |
| `.claude/skills/update-models/SKILL.md` | `ai_params_dialog.dart` 路径同步为 `views/dialogs/` |
| `docs/ARCHITECTURE.md` | 新增：分层规则与约定的长期入口 |

---

## 8. 兼容性与风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 外部代码按旧路径 import | 无：`publish_to: 'none'`，只有本仓库使用 | — |
| 进行中的分支与本次移动冲突 | 其他分支对被移动文件的修改在合并时变为 rename 冲突 | 尽快合入；冲突时 git 通常能识别 rename，按新路径解决 |
| CI Flutter 版本（3.44.7）与本地（3.47.5）的 formatter 结果不一致 | 新增的格式检查在 CI 上失败 | formatter 输出由语言版本（`sdk: >=3.9.0`）决定，风险低；若发生，在 CI 版本下重跑 `dart format` 后提交 |
| `DatasetState.supportedExtensions` 被改动 | 扫描不到图片 | 保留为指向同一常量的别名，集合逐项一致 |
| 大量文件被格式化导致 blame 噪声 | `git blame` 可读性 | 风格改动单独一个提交，可加入 `.git-blame-ignore-revs` |

---

## 9. 不在本次范围

- **超大文件拆分**：`views/dialogs/tag_dictionary_dialog.dart`（约 4000 行，其中 `_TagDictionaryDialogState` 约 1270 行）、`views/panels/tag_library_panel.dart`（约 2300 行）、`views/panels/agent_chat_panel.dart`（约 1900 行）。Flutter/Effective Dart 不设文件行数上限，框架自身也有数千行的文件；拆分核心 State 类属于行为级重构，另立任务。可行切分点：tag_dictionary 的工具条组件族（`_ToolbarSegment` … `_ToolbarButton`，约 500 行）、四个表单（`_TranslationForm` / `_NewTagForm` / `_FetchForm` / `_BatchForm`）；agent_chat 的各类卡片（`_ToolCard` / `_RulesCard` / `_ReasoningCard` …）。
- **`test/theme/chip_dim_test.dart` 两个像素比对用例失败**：基线 `e68c352` 上同样失败（差值约 0.036，阈值 0.03），与本次改造无关，已另开任务排查（Flutter 版本渲染差异或 chip 去 Opacity 提交）。
