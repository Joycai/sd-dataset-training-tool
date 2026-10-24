# LLM agent 协议、推理强度与图片输入审查

日期：2026-10-24。依据 `ai-agent-architecture` 技能的 00 审查流程、03 思考控制、22 能力矩阵、12 接入流程，并复核下列官方文档。

状态：原实现已通过 `fb1e519` 提交并推送，工作分支 `codex/llm-effort-audit`。已 fetch origin，开始工作时 HEAD 与 origin/main 一致；保留原有 macOS GeneratedPluginRegistrant.swift 修改。未发布。

## 范围与证据等级

本次覆盖客户端 LLM agent 的协议选择、effort 请求参数、推理历史、工具调用、图片输入，以及共用客户端的翻译、分组、连接测试和能力检测入口。未修改可选 Python 后端的打标模型清单。

- **代码证据 / 离线测试**：能确认应用发送的 JSON、解析结果、配置持久化和跨轮回传；不代表供应商或中转实际执行了某个档位。
- **官方文档（2026-10-24 核对）**：说明接口契约；未经本项目真实账号实测的行为均保留此等级。
- 技能里的网关实测只适用于其记录的平台、线路和模型，不推广为所有网关事实。
- 本次没有发起付费模型请求，没有读取或使用用户的 API 密钥。

## 协议盘点与覆盖

| 协议 | 请求入口 | 实现 | effort | 图片 / 工具结果图片 | 推理回传 |
| --- | --- | --- | --- | --- | --- |
| Chat Completions | `/chat/completions` | `lib/services/llm/openai_compat_client.dart:63` | `reasoning_effort`；DeepSeek/Qwen 独立开关 | `image_url` data URL；工具结果图片放在连续 tool 结果之后 | 原字段 `reasoning_content` / `reasoning`，保留中转扩展字段 |
| Responses | `/responses` | `lib/services/llm/responses_client.dart:38` | `reasoning.effort` | `input_image`；工具输出使用多模态 `function_call_output.output` | `store:false`，请求加密推理，原样回传完整 output items |
| Messages | `/v1/messages` | `lib/services/llm/anthropic_client.dart:49` | `thinking.type=adaptive`、`output_config.effort` | base64 image block，可嵌套在 tool_result | 保留完整有序 content blocks，包括 thinking signature 和 redacted_thinking |
| Gemini | `/models/<id>:streamGenerateContent?alt=sse` | `lib/services/llm/gemini_client.dart:110` | `generationConfig.thinkingConfig.thinkingLevel` | inlineData；函数结果图片嵌入 functionResponse.parts | 原样保留 parts 和 thoughtSignature；函数结果匹配 name / id |

四种协议均有流式对话、连接测试、模型列表及数值能力检测入口。Responses / Gemini 共用 HTTP 传输层，报文转换和流事件仍按协议分别实现。没有引入第三方模型 SDK 或新依赖。

## 已修复的发现

### 1. 静默丢失思考历史

原实现的 ReasoningDelta 仅供显示，AgentSession 不保存回传载体。DeepSeek 工具轮、Claude 签名、Responses 加密推理和 Gemini 签名不能靠显示文本重建。

修改：`lib/models/llm_models.dart:716` 的 LlmReplay 绑定配置 ID、协议、base URL、模型 ID；StreamDone 携带原始协议数据，AgentSession 将其保存到 assistant 历史。换端点、模型或协议时不回传旧载体。Messages / Responses / Gemini 保存完整内容顺序，不重新拼签名。

依据：技能 03 §5、§7；[DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)、[OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning)、[Gemini thought signatures](https://ai.google.dev/gemini-api/docs/thought-signatures)。修复已通过模拟 SSE 和 agent 工具轮测试；真实端点仍属待实测。

### 2. 无 effort 配置且每次发送 temperature

修改：模型配置持久化 effort、推理参数类型和可选 protocol。设置界面用推理强度代替温度滑块；旧 temperature 值仍可读取和保存，所有四种客户端均不再发送 temperature，也不添加 top_p / top_k。

参数转换集中在 `lib/models/llm_reasoning.dart:69`。菜单只提供对应类型的有效档位，非法持久化组合显式报错，不重试时偷偷删掉 effort。未知或带自定义前缀的模型可手选参数类型；关闭字段与强度字段分开。

这里不把 temperature 宣称为所有 API 都已删除：其有效性依模型和思考模式而异。本项目采用省略采样参数的默认行为。

### 3. GPT agent 缺少 Responses 协议

官方 GPT-6.1 Sol / GPT-6 Astra 的工具调用需要 Responses；GPT-6 Sol / Luna 的 Chat 工具调用仅适用于 none effort。原有二选一分发无法覆盖。

修改：新增 ResponsesClient 和统一工厂。OpenAI 预设改为 Responses；官方 GPT-6 的不兼容 Chat+tools 组合给出明确切换提示，中转站不套用此官方限制。Responses 的函数工具显式发送 strict:false，避免自动严格 schema 改变现有工具参数约束。

依据：[OpenAI 最新模型迁移说明](https://developers.openai.com/api/docs/guides/latest-model)，官方文档等级。

### 4. 多模态工具结果位置与能力门控

Chat 原先在每条 tool 结果后立刻插入 user 图片，导致并行工具结果之间被 user 消息打断。现在连续工具结果先配对，再追加图片。

四种客户端都拒绝对禁用视觉的模型发送图片，避免切换到文本模型后静默丢图。视觉能力继续由用户按实际端点声明，不根据同名模型自动开启。现有图像读取仍经过 DatasetStore，视觉工具压缩为最长边 768px JPEG，历史最多保留 4 张图片；此次未扩大图片尺寸或数量。

Responses 与 Gemini 的工具返回图片采用原生多模态输出位置。测试检查了 MIME/base64、工具关联和签名留存。

### 5. 修改配置后会话仍使用旧参数

原先只比较配置 ID。现在同一 ID 的模型、协议、地址、effort 或其他解析后配置变化，也会使下一次发送重新建立会话，避免界面显示新参数而请求仍用旧值。

位置：`lib/state/agent_chat_state.dart:283`。共用模型的翻译、分组、连接测试、模型发现和能力检测均读取模型最终协议。旧数据的 protocol 缺省时继承供应商，保持兼容。

### 6. 原始回传载体绕过上下文估算

新增原始载体后，如果仍只计可见文本，长推理会绕过窗口预算。现在估算包含原始载体；旧的签名交换按完整 user/assistant/tool 组退出历史，避免只改可见文本而继续发送隐藏原文。保护区或 pinned 内容仍放不下时，带原始推理的会话停止并要求新建会话。

位置：`lib/agent/context_budget.dart:169`。已有取消路径工具结果配对、写入审批、运行轮数和 token 上限逻辑保留，并通过全套原有测试。

### 7. 错误处理

Chat 补上 SSE 顶层 error 检查；参数修复缓存绑定端点/模型/协议，避免同一配置改模型后误用旧修复。Responses / Gemini 拒绝缺少终态的流；Responses failed/incomplete 的非 token 截断、Gemini 安全拦截和签名失败进入异常路径。没有对已收到输出的请求自动重发。

## 请求模型的配置建议与核对结果

所有行都可以填写服务商的实际模型 ID，不受硬编码目录限制。表中是官方路径的文档口径，不是对任意中转别名的保证。图片输入需要在模型设置中开启“支持视觉”。

| 模型 | 协议 / 参数类型 | 可选 effort（另有端点默认） | 图片核对 |
| --- | --- | --- | --- |
| DeepSeek V4 / V4.1 Flash | Chat / DeepSeek | off、low、high、max；旧快照是否接受 low 需核对供应商 | 当前官方 deepseek-flash 已有图片输入；不能从现行 alias 推断旧 V4 快照支持 |
| Claude Opus / Sonnet 4.6 | Messages / Adaptive | low、medium、high、max | 原生 image block |
| Claude Opus 4.7、4.8、5、5.5；Sonnet 5、5.5 | Messages / Adaptive | low、medium、high、xhigh、max | 原生 image block |
| Claude Fable 5、5.1 | Messages / Adaptive | low、medium、high、xhigh、max | 原生 image block；实际账号和模型目录需验证 |
| Sonnet 4.7 / 4.8 | 可按供应商实际 ID 配置 Messages | 官方当前 effort 兼容表未列出；不标为已验证型号 | 待供应商核实 |
| GPT-5.6 系列 | Responses | off、low、medium、high、xhigh、max | input_image |
| GPT-6 Sol / Luna | Responses | off、low、medium、high、xhigh、max | input_image |
| GPT-6 Astra / GPT-6.1 Sol | Responses | low、medium、high、xhigh、max；无 off | input_image |
| Qwen 3.8 Max / Flash / 27B | Chat / Qwen 3.8 | off、low、medium、xhigh | 三者均支持图片；27B 不是纯文本模型 |
| Gemini 3.7 / 3.8 Flash | Gemini | low、medium、high；无假“关闭”菜单 | inlineData、带签名的函数调用、多模态函数结果 |

来源（均于 2026-10-24 阅读）：

- [Claude effort 兼容和档位](https://platform.claude.com/docs/en/build-with-claude/effort)
- [DeepSeek 当前模型元数据](https://api-docs.deepseek.com/api/list-models/)、[视觉](https://api-docs.deepseek.com/guides/vision/)
- [Qwen Chat 参数、档位映射](https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions)
- [Qwen 3.8 Max](https://www.alibabacloud.com/help/en/model-studio/qwen3-8-max)、[Qwen 3.8 27B](https://www.alibabacloud.com/help/en/model-studio/qwen3-8-27b)
- [Gemini 3.8 迁移说明](https://ai.google.dev/gemini-api/docs/generate-content/whats-new-gemini-3.8)、[generateContent REST schema](https://ai.google.dev/api/generate-content)
- [Google 更新记录](https://ai.google.dev/gemini-api/docs/changelog?release=09-18-2026)：2026-10-08 起，官方 Gemini 3.7 Flash 请求自动转到 3.8 Flash。本项目保留 3.7 ID，以兼容其他供应商。

## 尚未核实与明确边界

1. **用户实际中转地址、渠道、模型别名**尚未提供，无法证明其会遵从 effort、支持图片或保留签名。最小验收方法：对实际路径发送同题 low/high，各做一个带图片的两轮函数调用，检查原始返回字段、第二轮接受情况、usage 与图片问题答案。需先确认具体端点和计费范围再做真实调用。
2. **Sonnet 4.7 / 4.8**没有在所查官方兼容表中找到；应以实际服务商的模型列表和能力声明为准，不从 Opus 同版本推断。
3. **Gemini 文档命名差异**：迁移文案使用 call_id，generateContent REST schema 使用 id。本实现按 REST schema 的 functionCall.id / functionResponse.id 配对；不混用 Interactions API 的字段。
4. 此次没有添加 Gemini Interactions、服务端搜索/执行工具、视频/音频输入、独立 JSON schema 输出设置。客户端的 agent 使用现有本地函数工具；这些额外能力不应被四协议选项理解为自动支持。
5. 没有做上游 effort 回显与供应商账单的真实比对；离线测试不证明推理质量或价格。网关对 reasoning_details 的非标准分片语义也需按其实际协议验收。
6. 新发现和待验证项记录在本项目报告中，未把离线测试写成共享技能知识库的供应商实测事实。

## 验证记录

### 首轮 review 修复

- Gemini 缺少上游调用 ID 时生成跨轮、跨客户端唯一的内部 ID；按历史顺序绑定工具名，防止后续同 ID 调用覆盖旧结果。回传保持原始签名，functionResponse 仅使用上游真实 ID；上游省略时同样省略。
- 重试前比较当前完整模型配置。配置修改或移除后，终止旧会话、清除写操作许可并显示中英文提示，要求用户重新发送；不自动重复可能已完成的写操作。配置未变时保留原有续跑行为。
- 回归测试：缺失 ID、多轮重复上游 ID、签名保留；effort/协议/密钥变更、配置删除、未变配置续跑、新请求使用新配置且不带旧历史。
- 验证结果：Flutter 3.47.6 定向测试 24 项通过；完整测试 1042 项通过、4 项跳过；pub get、gen-l10n、格式检查（207 文件）、静态分析和分层检查全部通过。锁文件未变化，中英文本地化生成输出已核对。

### 原实现验证

使用独立 Flutter **3.47.6**（Dart **3.13.5**），未更改全局 3.47.7 SDK 或升级依赖。

- flutter pub get：通过；锁文件无变更。
- flutter gen-l10n：通过；再次生成前后哈希一致。两份 ARB 和三份生成 Dart 为本次有意变更，交付时需一同提交。
- dart format --output=none --set-exit-if-changed lib test tool：206 个文件，0 变更。
- flutter analyze：No issues found。
- dart run tool/check_layers.dart：violations: 0。
- flutter test --reporter failures-only：**1035 通过，4 跳过**。
- 新增回归覆盖四协议报文、effort 约束、旧配置兼容、原始推理跨轮、签名/密文、图片门控与工具结果、错误终态、签名历史压缩，以及中英文设置控件交互和持久化。
