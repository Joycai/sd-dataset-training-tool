# DataSetTrainingTool 集成 LLM Agent 助手实施方案

> 目标：为 Flutter 桌面应用 **DataSetTrainingTool** 增加一个可对话的 **AI Agent 助手**。
> 用户配置任意 LLM 后端（OpenAI / Gemini / Anthropic 官方 API、newapi 等 OpenAI 兼容中转、Ollama 本地部署）后，
> 助手通过一组**工具（tool calling）**读取数据集、读写 caption、查询标签库、调用现有 WD14 打标能力，
> 完成"整体洗标签"（批量删除/替换/插入/排序）、数据集分析、逐张语义修改等任务。
> 多模态后端还可以直接"看图"。
> 分三期实施（§10）；本文档供 Claude Code 在本机（可运行 `flutter` / `dart`）执行。

---

## 0. 背景与设计原则

- 现有架构已提供了 agent 需要的几乎全部"执行层"：
  - `TagOps`（`lib/state/tag_ops.dart`）：数据集级批量改写（删除/替换/相邻插入/添加），**自带 undo/redo 快照**，
    并通过 `beforeMutate` 在写盘前 flush 编辑器、通过 `onCaptionsChanged` 通知 UI 重载。
  - `DatasetState`（`lib/state/dataset_state.dart`）：全数据集标签频次统计 `datasetTags`、逐图标签 `tagsOf()`、
    caption 状态、筛选表达式。
  - `AiTaggerService`（`lib/services/ai_tagger_service.dart`）：AiApiServer 的 HTTP 客户端（WD14 打标）。
  - `AppState`：公共标签库 `commonTags` 与分组 `tagGroups`。
- **核心设计原则：让 LLM 做决策，让确定性代码做执行。**
  绝大多数"洗标签"任务只需要 agent 看聚合统计（几 KB），决定规则后调用 `TagOps` 工具批量执行——
  不逐张过 LLM，token 成本低、结果可靠、且天然可撤销。只有逐张语义级修改才按需分页读取/看图。
- **所有写操作必须进入 undo 栈。** agent 的任何改动都能被用户一键 `Ctrl+Z` 撤销，这是安全底线。
- 与 AiApiServer 集成一样，service/models 层**刻意不 import Flutter**，方便单元测试。

---

## 1. LLM 后端接入策略

### 1.1 两种协议覆盖所有目标后端

| 后端 | 接入方式 | Base URL 预设 |
|------|----------|---------------|
| OpenAI 官方 | OpenAI Chat Completions | `https://api.openai.com/v1` |
| newapi / one-api 等中转 | OpenAI Chat Completions | 用户自填（如 `https://xxx.com/v1`） |
| Ollama 本地 | OpenAI Chat Completions（Ollama 自带 `/v1` 兼容层） | `http://127.0.0.1:11434/v1` |
| Google Gemini | OpenAI Chat Completions（官方兼容端点） | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Anthropic | 原生 Messages API（独立 adapter） | `https://api.anthropic.com` |

即：**主协议只实现一份 OpenAI-compatible client**（含 streaming + function calling + vision），
Anthropic 另写一个小 adapter（差异：`x-api-key`/`anthropic-version` 头、`system` 顶层字段、
`tool_use`/`tool_result` content block、`max_tokens` 必填、SSE 事件名不同）。
Gemini 原生 API 不做——官方 OpenAI 兼容端点已支持 chat/streaming/tools/vision。

### 1.2 Provider Profile（用户可存多套配置）

```dart
/// lib/models/llm_models.dart
enum LlmApiKind { openaiCompat, anthropic }

class LlmProviderProfile {
  final String id;            // 稳定 id（时间戳+计数器，同 TagGroup）
  final String name;          // 显示名，如 "GPT-5"、"本地 qwen3"
  final LlmApiKind kind;
  final String baseUrl;
  final String apiKey;        // Ollama 可为空
  final String model;         // 如 "gpt-5-mini" / "claude-sonnet-4-5" / "qwen3:14b"
  final bool supportsVision;  // 多模态开关（决定 view_image 工具是否注册）
  final int contextWindow;    // 上下文窗口（tokens），用户按模型填写，默认 32768
  final int maxOutputTokens;  // 默认 4096
  final double temperature;   // 默认 0.7
}
```

序列化为 JSON 列表存 `SharedPreferences`（key `llmProviderProfiles`），
另存 `llmActiveProfileId`。**注意：SharedPreferences 是明文存储**，设置页要对 apiKey
做密码框展示 + 说明文案；后续可选迁移 `flutter_secure_storage`（本方案不做）。

### 1.3 统一消息模型（协议无关）

```dart
enum ChatRole { system, user, assistant, tool }

class ChatContentPart {            // 文本或图片二选一
  final String? text;
  final Uint8List? imageBytes;     // 已下采样压缩的 JPEG
  final String? imageMimeType;     // "image/jpeg"
}

class ChatToolCall {
  final String id;                 // 回传给 tool result 用
  final String name;
  final String argumentsJson;      // 原始 JSON 字符串，解析失败可原样反馈给模型
}

class ChatMessage {
  final ChatRole role;
  final List<ChatContentPart> parts;
  final List<ChatToolCall> toolCalls;   // assistant 消息可携带
  final String? toolCallId;             // tool 消息回填
}

class TokenUsage { final int prompt; final int completion; }

/// 流式增量：文本 delta、工具调用 delta、结束原因、usage
sealed class LlmStreamEvent {}
class TextDelta extends LlmStreamEvent { final String text; }
class ToolCallsReady extends LlmStreamEvent { final List<ChatToolCall> calls; }
class StreamDone extends LlmStreamEvent { final String finishReason; final TokenUsage? usage; }
```

### 1.4 抽象客户端接口

```dart
/// lib/services/llm/llm_client.dart —— 纯 Dart，不 import Flutter
abstract class LlmClient {
  /// 发送一轮对话，SSE 流式返回。tools 为 JSON Schema 定义（§4）。
  /// 实现内部负责协议格式转换与 SSE 解析。
  Stream<LlmStreamEvent> chat({
    required LlmProviderProfile profile,
    required List<ChatMessage> messages,
    required List<AgentToolSpec> tools,
    CancellationToken? cancel,
  });

  /// 连接测试：发一个 1-token 的极小请求，返回错误信息或 null。
  Future<String?> probe(LlmProviderProfile profile);
}
```

实现要点（两个子类共用一个 `sse.dart` 工具）：

- 用 `http.Client.send(http.Request)` 拿 `StreamedResponse`，按行解析 `data: {...}` / `data: [DONE]`；
  按 UTF-8 解码时注意 chunk 可能截断多字节字符（用 `utf8.decoder.bind(stream)` 再 `LineSplitter`）。
- OpenAI 流式 tool_call 是**分片**下发的（`tool_calls[i].function.arguments` 逐段拼接），需要按 index 累积，
  `finish_reason == "tool_calls"` 时发 `ToolCallsReady`。
- Anthropic 对应 `content_block_delta`（`input_json_delta`）与 `message_delta.stop_reason == "tool_use"`。
- 请求带 `stream_options: {"include_usage": true}`（OpenAI 系）以拿到 usage；拿不到就用本地估算（§5）。
- 超时：连接 30s；流式期间用"逐事件空闲超时"（如 120s 无数据即断）而非总时长超时。
- 取消：`CancellationToken` 触发时关闭底层 `http.Client`，loop 捕获后收尾。

---

## 2. Agent 运行时

### 2.1 工具定义与注册表

```dart
/// lib/services/agent/agent_tools.dart
class AgentToolSpec {
  final String name;
  final String description;          // 面向模型的英文描述
  final Map<String, dynamic> parametersSchema; // JSON Schema (object)
}

class AgentToolResult {
  final String text;        // 回传给模型的文本（通常是紧凑 JSON）
  final bool isError;
  final List<ChatContentPart> extraParts; // view_image 用：携带图片
}

typedef AgentToolHandler = Future<AgentToolResult> Function(Map<String, dynamic> args);

class ToolRegistry {
  final List<(AgentToolSpec, AgentToolHandler)> _tools;
  // register() / specs / dispatch(name, argsJson)
  // dispatch 负责：JSON 解析失败 / 未知工具 / 参数校验失败 → 返回 isError 结果
  // （把错误文本回传给模型让它自行重试，而不是抛异常中断 loop）
}
```

ToolRegistry 由 UI 层组装（因为要闭包持有 `DatasetState` / `TagOps` / `AppState` /
`AiTaggerService` / `EditorSession` 的引用），但工具实现本身放在
`lib/services/agent/dataset_tools.dart`，以顶层函数 + 依赖注入的形式组织，便于测试。

### 2.2 Agent 循环（AgentSession）

```dart
/// lib/services/agent/agent_session.dart —— 纯 Dart
class AgentSession {
  // 依赖：LlmClient、ToolRegistry、LlmProviderProfile、ContextBudget（§5）
  // 状态：List<ChatMessage> history（含 system prompt）、TokenUsage 累计

  Stream<AgentUiEvent> run(String userInput) async* {
    history.add(userMessage(userInput));
    for (var turn = 0; turn < maxTurns; turn++) {        // maxTurns 默认 24
      budget.compact(history);                            // 上下文裁剪（§5）
      final events = client.chat(profile: p, messages: history, tools: registry.specs);
      // 转发 TextDelta 给 UI；收集完整 assistant 消息
      if (finishReason != 'tool_calls' && toolCalls.isEmpty) break;   // 自然结束
      history.add(assistantMessageWith(toolCalls));
      for (final call in toolCalls) {                     // 串行执行，避免并发写盘
        yield ToolStarted(call);
        final result = await registry.dispatch(call.name, call.argumentsJson);
        yield ToolFinished(call, result);
        history.add(toolMessage(call.id, result));
      }
    }
  }
}
```

要点：

- **工具串行执行**：`TagOps` 有 `_busy` 互斥，且磁盘写入不该并发；一轮多个 tool call 依次跑。
- **maxTurns 上限 + 会话 token 硬上限**（默认 1,000,000 累计 token，可设置）触发时终止并告知用户。
- 模型输出格式错误的 tool call（本地小模型常见）：dispatch 返回 `isError` 文本
  （如 `{"error":"invalid arguments: ..."}`），让模型自我纠正；连续 3 次失败则中止本轮。
- 用户可随时**停止**（取消 token），已执行的写操作留在 undo 栈里，不自动回滚（用户可 Ctrl+Z）。

### 2.3 System Prompt（要点）

固定英文骨架 + 动态注入（用户语言、数据集概况一行、caption 扩展名、写确认模式状态）：

- 角色：SDXL/anime LoRA 训练集整理助手，caption 是逗号分隔的 danbooru 风格 tag。
- 强调：先用 `get_tag_stats` / `get_dataset_overview` 了解全局，再决定操作；
  优先批量工具（一次调用改全库）而不是逐张 `write_caption`；
  破坏性操作前向用户复述计划；所有写操作可被用户撤销。
- 说明 trigger word / keep-first-N 惯例（数据集首 tag 常是触发词，排序类操作默认保留首位，除非用户明确要求）。

---

## 3. 上下文与多模态的成本控制

见 §5（上下文预算）与 §4 中 `view_image` / `read_captions` 的分页、截断参数设计。
原则重复一遍：**聚合优先，分页兜底，图片抽查**。

---

## 4. 工具清单（Phase 标注见 §10）

所有工具返回**紧凑 JSON 文本**（无缩进），列表类工具一律带 `limit`/`offset` 分页并在结果中
返回 `total` 与 `truncated` 标记。路径参数一律使用**相对数据集根目录的路径**（防目录穿越：
resolve 后必须仍在数据集根内，否则报错），减少 token 且避免模型抄错盘符。

### 4.1 只读工具（Phase 1）

| 工具 | 参数 | 实现映射 |
|------|------|----------|
| `get_dataset_overview` | — | `DatasetState`：目录、总数/有无 caption 数、当前筛选、caption 扩展名 |
| `get_tag_stats` | `sort`(count/alpha), `limit`=200, `offset` | `DatasetState.datasetTags`（注意 §11.6 的缓存失效） |
| `search_tags` | `query`(子串), `limit` | 在 `datasetTags` 上过滤 |
| `list_images` | `include_tags[]`, `exclude_tags[]`, `untagged_only`, `name_query`, `limit`=100, `offset` | 独立实现集合过滤（不复用 UI 的 `TagFilterGroup`，避免与用户当前筛选互踩） |
| `read_captions` | `paths[]`(≤50) | `DatasetState.tagsOf()` 逐图返回 tag 列表 |
| `get_tag_library` | — | `AppState.commonTags` + `tagGroups`（组名/颜色/成员）+ ungrouped |

### 4.2 写工具（Phase 2，全部进 undo 栈）

| 工具 | 参数 | 实现映射 |
|------|------|----------|
| `remove_tag_everywhere` | `tag` | `TagOps.deleteEverywhere(tag, label: 'AI: remove …')` |
| `replace_tag_everywhere` | `tag`, `replacement`(可逗号多值) | `TagOps.replaceEverywhere` |
| `insert_beside_tag` | `anchor_tag`, `tags`, `after`(bool) | `TagOps.insertBeside` |
| `add_tags_everywhere` | `tags`, `index?`, `include_tags[]?` 等过滤 | `TagOps.addEverywhere(files: …)` |
| `write_caption` | `path`, `caption`(完整文本) | 新增 `TagOps.rewriteOne()`（§6.1），含 undo |
| `undo_last_operation` | — | `TagOps.undo()`；返回被撤销操作的 label |

写工具返回改动统计（`{"changed": 37}`）；`label` 统一加 `AI: ` 前缀，
用户在状态栏 undo 提示里能看出是 agent 干的。

**写确认模式**（设置项，默认开）：开启时，agent 每次调用写工具，UI 弹出确认条
（显示工具名 + 参数摘要 + 预估影响张数），用户"允许 / 本次会话全部允许 / 拒绝"；
拒绝时给模型回传 `{"error":"user rejected this operation"}`。实现上是 ToolRegistry
dispatch 前的一个 `Future<bool> Function(call)` 回调，由 `AgentChatState` 接 UI。

### 4.3 AI 打标与多模态（Phase 3）

| 工具 | 参数 | 实现映射 |
|------|------|----------|
| `list_tagger_models` | — | `AiTaggerService.listTaggers()`（AiApiServer 不可达时返回 error 文本） |
| `run_wd_tagger` | `paths[]`(≤20), `model?`, `threshold?` | `interrogateTags()` 串行逐张（服务端有全局锁，并发无收益）；返回 per-image tags，**不直接写盘**——写入由模型再调写工具完成 |
| `view_image` | `paths[]`(≤4) | 读文件 → 下采样（最长边 768）+ JPEG(q80) → 以 `extraParts` 图片形式进入 tool result（仅 `supportsVision` 的 profile 注册此工具） |

`view_image` 的图片压缩用 `package:image`（新增依赖）在 isolate（`compute`）里做，避免卡 UI。
每张压缩后约 50–150KB，base64 后计入上下文预算（按 ~1600 tokens/张 估算，见 §5）。

---

## 5. 上下文预算管理（ContextBudget）

```dart
/// lib/services/agent/context_budget.dart —— 纯 Dart
class ContextBudget {
  final int contextWindow;    // 来自 profile
  final int maxOutputTokens;  // 来自 profile
  int get inputBudget => contextWindow - maxOutputTokens - 1024; // 安全裕量

  /// 近似 token 估算：ASCII 按 chars/4，CJK 按 chars/1.7，图片按 1600/张。
  /// 刻意高估 10% —— 宁可提前裁剪，不可溢出报错。
  int estimate(List<ChatMessage> history);

  /// 超预算时的裁剪，按优先级：
  /// 1. 从最旧的 tool 消息开始，把结果正文替换为
  ///    "[tool result elided: <name>, <n> chars]"（保留消息结构，模型仍知道调过什么）；
  /// 2. 仍超则从最旧的 user/assistant 轮次开始折叠为单行摘要占位；
  /// 3. system prompt、最近 4 轮完整消息、最近一次 tool 结果永不折叠。
  void compact(List<ChatMessage> history);
}
```

服务端返回真实 usage 时（`StreamDone.usage`），用真实值校准显示，但裁剪判断始终用本地估算
（裁剪发生在发送前）。会话累计 token 显示在助手面板底部，超过会话硬上限（§2.2）即停。

---

## 6. 对现有代码的少量修改

### 6.1 `lib/state/tag_ops.dart`：新增单文件重写方法

```dart
/// Rewrites one image's caption to exactly [text], recording undo.
/// Returns false when the file content is already identical.
Future<bool> rewriteOne(String imagePath, String text, {required String label});
```

实现走现有私有基建：`beforeMutate` flush → 读旧文本 → 写新文本 → 构造 `CaptionEdit` →
入 `_undoStack` → `dataset.updateCaptionText` → `onCaptionsChanged`。
（与 `_rewriteAll` 共享错误处理风格：IO 失败返回 false，不抛。）

### 6.2 `lib/services/settings_service.dart`：追加 LLM 设置读写

`saveLlmProfiles(String json)` / `loadLlmProfiles()`、`saveLlmActiveProfileId` /
`loadLlmActiveProfileId`、`saveAgentConfirmWrites`(默认 true)、`saveAgentSessionTokenCap`(默认 1000000)。
风格与现有 AI 打标设置段一致。

### 6.3 `pubspec.yaml`

```yaml
  image: ^4.3.0        # view_image 下采样（仅 Phase 3 需要）
```

HTTP/SSE 全用已有 `http` 包 + `dart:convert`，**不新增 LLM SDK 依赖**。

### 6.4 UI 挂载

- `WorkbenchView` 右侧新增第四栏「AI 助手」，做成可折叠抽屉（顶栏加开关按钮，宽度可拖动、
  持久化 `agentPanelWidth`），不挤占现有三栏逻辑。
- `AgentChatState`（`lib/state/agent_chat_state.dart`，ChangeNotifier）持有 AgentSession、
  消息列表、运行状态、确认队列；在 workbench 组装处注入 `DatasetState`/`TagOps`/`AppState`/
  `AiTaggerService`/`EditorSession` 构建 ToolRegistry。
- 聊天面板（`lib/views/panels/agent_chat_panel.dart`）：消息气泡（纯文本即可，markdown 渲染后置）、
  流式追加、工具调用折叠卡片（名称+参数+结果摘要）、写确认条、停止按钮、token 计数、
  "新会话"按钮（清空 history）。
- agent 运行中：顶栏显示指示灯；数据集切换目录时强制终止会话并清空 history
  （工具闭包引用的 dataset 已变）。
- 所有新文案进 `l10n/app_en.arb` / `app_zh.arb`。

### 6.5 设置页

「LLM / AI 助手」新分区：profile 列表（增删改、设为默认）、编辑表单
（名称/协议类型/BaseURL 带预设下拉/APIKey 密码框/模型名/上下文窗口/最大输出/温度/vision 开关）、
「测试连接」按钮（调 `LlmClient.probe`，显示往返延迟或错误）、写确认模式开关、会话 token 上限。

---

## 7. 文件清单汇总

| 操作 | 路径 | 阶段 |
|------|------|------|
| 新建 | `lib/models/llm_models.dart` | P1 |
| 新建 | `lib/services/llm/llm_client.dart` | P1 |
| 新建 | `lib/services/llm/sse.dart` | P1 |
| 新建 | `lib/services/llm/openai_compat_client.dart` | P1 |
| 新建 | `lib/services/llm/anthropic_client.dart` | P1 |
| 新建 | `lib/services/agent/agent_tools.dart` | P1 |
| 新建 | `lib/services/agent/dataset_tools.dart` | P1（只读部分）/ P2（写）/ P3（打标+看图） |
| 新建 | `lib/services/agent/context_budget.dart` | P1 |
| 新建 | `lib/services/agent/agent_session.dart` | P1 |
| 新建 | `lib/state/agent_chat_state.dart` | P1 |
| 新建 | `lib/views/panels/agent_chat_panel.dart` | P1 |
| 修改 | `lib/services/settings_service.dart` | P1 |
| 修改 | `lib/views/settings_view.dart` | P1 |
| 修改 | `lib/views/workbench_view.dart`（第四栏挂载） | P1 |
| 修改 | `lib/state/tag_ops.dart`（`rewriteOne`） | P2 |
| 修改 | `pubspec.yaml`（`image`） | P3 |
| 修改 | `lib/l10n/app_en.arb` / `app_zh.arb` | 各期 |
| 新建 | `test/` 下对应单元测试（SSE 解析、budget、tool dispatch、rewriteOne undo） | 各期 |

---

## 8. 典型任务流示例（验证场景）

1. **"把所有出现少于 3 次的标签列出来，然后删掉其中的质量类标签"**
   → `get_tag_stats(sort:count)` → 模型筛选 → 逐个 `remove_tag_everywhere` →（写确认）→ 汇报。
2. **"把 1girl 统一替换成 1woman，并保证它排在触发词后面第一位"**
   → `replace_tag_everywhere` → `get_tag_stats` 验证 → 必要时逐张 `write_caption` 修正顺序。
3. **"帮我检查前 10 张图的 caption 和画面是否相符"**（多模态）
   → `list_images(limit:10)` → `view_image`（分批 ≤4）+ `read_captions` → 报告差异，建议修改。
4. **"对没打标的图跑一遍 WD 打标，去掉黑名单标签后写入"**
   → `list_images(untagged_only)` → `run_wd_tagger` → 模型过滤 → `write_caption` 逐张写入。

---

## 9. 坑与注意事项

1. **本地小模型 tool calling 不可靠**：Ollama 上 7B/8B 模型常给出格式错误的调用或幻觉工具名。
   dispatch 全链路"报错回传而非抛异常"；工具总数控制在 ~12 个内、schema 保持扁平；
   文档/设置页注明推荐 ≥14B 且带 tools 能力的模型。
2. **SSE 解析**：多字节 UTF-8 截断（先 `utf8.decoder` 后分行）；`data:` 前缀可能带/不带空格；
   OpenAI 兼容实现里 usage chunk 可能在 `[DONE]` 前单独出现且 `choices` 为空数组——别按索引取。
3. **Gemini 兼容端点差异**：个别 OpenAI 参数不支持（如部分 `stream_options`），请求失败时降级重试
   一次"无 stream_options"版本；`tool_choice` 用默认 auto 即可，不下发花式值。
4. **Anthropic**：`max_tokens` 必填；system 是顶层字段不是消息；tool 结果是 user 消息里的
   `tool_result` block。adapter 内做好双向转换，`AgentSession` 完全无感。
5. **写冲突**：一切写路径必须过 `TagOps`（享受 `beforeMutate` flush + undo）；agent 运行中
   用户仍可手动编辑——`rewriteOne`/`_rewriteAll` 读盘时以磁盘为准，冲突窗口极小，可接受。
6. **`datasetTags` 缓存**：`TagOps` 写盘后已通过 `updateCaptionTexts` 失效缓存，agent 只读工具
   直接读 getter 即可，无需 rescan；但 `run_wd_tagger` 不写盘，不影响缓存。
7. **切换数据集目录**：必须终止 agent 会话（§6.4），否则工具闭包读到新目录、history 里却是旧目录的事实。
8. **API key 安全**：明文存储要在设置页醒目提示；日志/异常文本里**永不打印** apiKey（URL 打印前脱敏）。
9. **成本**：多模态看图是最贵路径，`view_image` 单次 ≤4 张 + 提示模型"抽查而非全量"；
   会话 token 硬上限兜底。
10. **首次请求慢**（Ollama 加载模型 / 中转排队）：流式空闲超时给足 120s，UI 显示"思考中"。

---

## 10. 分期实施与待办清单

### Phase 1：LLM 接入 + 聊天 + 只读工具（可独立发布）

- [ ] 1. `lib/models/llm_models.dart`：消息/工具/Profile/usage 模型（§1.2、§1.3）。
- [ ] 2. `lib/services/llm/sse.dart` + `openai_compat_client.dart` + `anthropic_client.dart` + `llm_client.dart`（§1.4）。
- [ ] 3. `context_budget.dart`（§5）＋单元测试（估算与裁剪边界）。
- [ ] 4. `agent_tools.dart`（Spec/Registry/dispatch 容错）＋ `dataset_tools.dart` 只读六件套（§4.1）＋测试。
- [ ] 5. `agent_session.dart` 主循环（§2.2）＋ system prompt（§2.3）。
- [ ] 6. `settings_service.dart` 追加 LLM 设置；`settings_view.dart` 新分区含 probe（§6.5）。
- [ ] 7. `agent_chat_state.dart` + `agent_chat_panel.dart` + workbench 第四栏挂载（§6.4）＋ l10n。
- [ ] 8. `flutter analyze` 零报错；对至少一个 OpenAI 兼容端点 + 一个 Ollama 实测流式问答与只读工具调用。

**验收**：能连接三类后端（官方/中转/Ollama）；能流式对话；能正确回答
"数据集里出现最多的 20 个标签是什么"这类只读问题；断网/错 key/错 URL 有清晰错误提示。

### Phase 2：写工具 + 确认与撤销闭环

- [ ] 1. `tag_ops.dart` 新增 `rewriteOne`（§6.1）＋单测（undo 字节级还原）。
- [ ] 2. `dataset_tools.dart` 写六件套（§4.2），label 带 `AI: ` 前缀。
- [ ] 3. 写确认模式：设置项 + 确认条 UI + dispatch 回调（§4.2）。
- [ ] 4. 状态栏/顶栏的 agent 运行指示；切目录终止会话。
- [ ] 5. 实测 §8 场景 1、2；确认每步都可 Ctrl+Z 撤销。

**验收**："统一删掉 watermark 类标签"一句话任务端到端完成，确认条正常拦截，撤销逐级还原。

### Phase 3：多模态 + WD 打标桥接

- [ ] 1. `pubspec.yaml` 加 `image`；isolate 压缩管线。
- [ ] 2. `view_image`（仅 vision profile 注册）＋ `list_tagger_models` + `run_wd_tagger`（§4.3）。
- [ ] 3. 图片 token 计入 budget；多模态消息在两个 client 里的格式支持。
- [ ] 4. 实测 §8 场景 3、4。

**验收**：多模态后端能看图指出 caption 与画面不符；WD 打标结果经模型清洗后写入且可撤销。

---

## 11. 验证清单（完成标准，全局）

- `flutter analyze` 零 error/warning；新增 service/models 层不 import Flutter。
- 单元测试覆盖：SSE 解析（含分片 tool_call 拼接）、ContextBudget 裁剪、ToolRegistry 容错、
  `rewriteOne` undo 还原。
- 三类后端（OpenAI 兼容官方、newapi 中转、Ollama）+ Anthropic 原生实测通过 §8 全部场景。
- agent 的任何写操作都出现在 undo 栈且可完整撤销；apiKey 不出现在任何日志输出。
