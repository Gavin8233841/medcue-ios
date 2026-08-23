# 智能体 Tab 对话体验升级迁移方案（借鉴 CatPawAgent）

- 日期：2026-08-23
- 状态：提案（未实施）
- 参考实现：CatPawAgent（iOS SwiftUI 云端 Agent 聊天应用，本机 `/Users/Admin/xcodebuild_ws/CatPawAgent`）
- 关联文档：`coreai/LOCAL_AGENT_MIGRATION_PLAN.md`（端侧优先迁移计划）、`docs/25-token-broker-deployment-prerequisites-20260727.md`

## 1. 结论摘要

MedCue 智能体 Tab 的安全分层（Planner / Orchestrator / Finalizer / Command）和隐私边界已经扎实，缺的是对话体验层的四项能力：**流式渲染、多轮记忆、富文本表达、只读工具闭环**。这四项恰好在参考实现 CatPawAgent 中成熟且耦合度低。

本方案的核心决策是：**先建统一的双通道流式事件契约，让 UI 只面向内部事件渲染，本地 llama.cpp 流和云端 SSE 流都适配进同一契约**。这样最大的一步（流式上屏）不需要改任何后端——MedCue 本地通道今天就有逐 token 流，只是增量文本在 UI 层被丢弃了（`AIAssistantView.swift:526-531`）。

本方案与 `LOCAL_AGENT_MIGRATION_PLAN.md` 不冲突：该计划决定"模型跑在哪"（端侧优先），本方案决定"对话怎么渲染和交互"（通道无关）。两者可并行推进。

## 2. 现状评估（证据）

### 2.1 前端

- 消息列表为 `ScrollViewReader + LazyVStack` + `AIMessageBubble`（`Views/AIAssistantScreen.swift:121-166`），气泡是裸 `Text`，不支持 Markdown，且 prompt 明确禁止模型输出 Markdown（`Services/LocalMedicalResponsePolicy.swift:13,41,73`）。
- 本地流事件的 `thinkingDelta/answerDelta(String)` 增量文本到手即丢，UI 只更新状态文案（`Views/AIAssistantView.swift:526-531`）；云端三条通道均为一次性 `await` 阻塞返回（同文件 :607-611）。
- 滚动跟随只监听 `visibleMessages.count` 与 `isSending`（`Views/AIAssistantScreen.swift:184-203`），流式增长不会触发跟随。
- 错误以 `role: .system` 消息混入对话流，无内联错误样式与重试（`AIAssistantView.swift:572-580, 634-642`）。
- 归档状态用 `"|"` 拼接 UUID 存 `AppStorage`（`AIAssistantView.swift:27, 84-86`）。

### 2.2 消息模型与服务层

- `StoredAIChatMessage`（`Models/StoredModels.swift:995-1029`）只有单一 `text: String`，无消息状态、无工具调用/富内容结构；助手"思考过程"靠约定分隔符混在 text 中再在 UI 层拆分（`Views/AIAssistantConversationViews.swift:517-534`）。
- 发送请求**不带任何历史对话**（`swift-core/.../MedicalAIPromptBuilder.swift:6-59`），是无记忆单轮问答。
- 无 function calling；模型获知用药数据靠客户端预取快照塞 prompt，且用"今日/今天"关键词决定带当天还是全部任务（`Services/MedicalAIContextBuilder.swift:132`）。
- `MedicalAIClient` 协议（`swift-core/.../MedicalAIModels.swift:197`）只有非流式 `respond(to:)`；流式仅存在于 `LocalMedicalAIClient.streamResponse`（`Services/LocalMedicalAIClient.swift:44`）返回 `AsyncThrowingStream<LocalLLMGenerationEvent, Error>`，事件枚举见 `Services/LocalLLMStreamParser.swift:3-13`。
- 本地模型每次请求新建 context、全量加载模型，contextLength 仅 2048（`Services/LocalMedicalModelRuntime.swift:32,83`）。

### 2.3 后端 broker

- `cloudfunctions/medcue-ai-broker` 为单文件单路由（`POST /v1/respond`，`src/broker.js:169`），只进 `prompt` 字符串、只出完整 `answer`，非流式（上游响应 64KB 整体读入，`broker.js:348-353`），无 messages 历史、无 tools 字段。
- 安全工程到位：fail-closed、拒绝重定向、字节级上限、30 req/min 限流、request_id 幂等、28/28 测试（基线 `d6aa4af` CI run 32640833807）。**迁移中必须保留这些边界。**

## 3. CatPawAgent 可迁移资产评估

| 组件 | 位置（CatPawAgent/CatPawAgent/） | 规模 | 耦合点 | 迁移难度 |
|---|---|---|---|---|
| SSEClient + HTTPClient | `Agent/Networking/` | 71 + 31 行 | 仅 `AppLogger`（os.Logger 封装） | **低，几乎原样搬** |
| AgentStreamEvent 内部契约 | `Agent/Event/AgentStreamEvent.swift:31-48` | 小 | 无 | **低，直接保留** |
| 事件解释器 + 轮次追踪 | `Agent/Event/AgentEventInterpreter.swift`、`CurrentTurnEventTracker.swift` | ~450 行 | `AgentEventType` 常量表是 CatPaw 协议单一事实来源 | 中，按目标协议重写分支 |
| A2UIBuffer | `Agent/Event/A2UIBuffer.swift` | 小 | 标记字符串可参数化 | 低（本方案暂不启用富卡片，可缓迁） |
| Markdown 三件套 | `Views/MessageViews/Markdown/`（Parser 360 + RenderCache 84 + Views 223 行） | 自包含 | 仅 `ChatTheme` 颜色 | **低，整体搬** |
| Tool 协议 + LocalToolCoordinator | `Agent/Tools/`（协议 5 个成员；coordinator 255 行，幂等表 + 后缀匹配 + 注入式结果回传） | 中 | `toCatPawCustomToolDefinition()` 可删 | 低-中 |
| Session 双写/恢复/合并 | `Agent/Session/` | 大 | 深度耦合 CatPaw 远端协议 | **不搬，只借鉴思路**（MedCue 已有 SwiftData） |
| ChatViewModel + ChatView | `ViewModels/`、`Views/` | 大 | 满是 CatPaw 概念 | 不搬，参考其"整条消息 struct 替换 + 稳定 id diff"更新粒度 |

流畅性核心心法（随 Markdown 三件套一起获得）：全量解析 + LRU 缓存（上限 48 条）+ "序号 + 内容指纹"块 id，流式增长时只有尾部块换身份重建，前文视图全部保留；不做逐字渐显动画，打字机效果是 chunk append 的自然结果。

## 4. 迁移路线（分五阶段）

### Phase 0：Markdown 三件套落地（纯 UI，零风险，1-2 天）

- 将 MarkdownParser / MarkdownRenderCache / MarkdownViews 拷入 `Views/AIAssistant/`，`ChatTheme` 颜色映射到 MedCue 现有主题与适老大字体（务必验证 Dynamic Type 下代码块横滚）。
- `AIMessageBubble` 的助手侧裸 `Text` 换成 Markdown 渲染；删除 `LocalMedicalResponsePolicy` 中"禁止 Markdown"的 prompt 约束（:13,41,73），改为"允许简单 Markdown：加粗、短列表，禁止表格与标题层级"。
- 验收：适老模式最大字体下，说明书摘要咨询的回答可读、无截断；`MarkdownParserTests` 一并迁入并通过。

### Phase 1：统一流式事件契约（核心，3-5 天）

- 新增 `AIConversationStreamEvent` 内部枚举（借鉴 `AgentStreamEvent`）：`.answerDelta(String)`、`.thinkingDelta(String)`、`.statusChanged`、`.completed(message:)`、`.failed(Error)`。它是 UI 与通道之间的唯一契约。
- 适配器 A（本地，零后端改动）：把现有 `LocalLLMGenerationEvent` 逐项映射到内部契约——这是**当天可见的最大收益**，本地通道立刻从"状态轮转"变成逐字输出。
- 适配器 B（云端，占位）：`SSEClient + HTTPClient` 拷入 `Services/`，先写豆包 SSE 解析的适配层骨架，待 Phase 3 后端就绪后接通。
- 扩展 `MedicalAIClient`：新增可选流式能力（如 `protocol MedicalAIStreamingClient: MedicalAIClient { func streamEvents(to:) -> AsyncThrowingStream<AIConversationStreamEvent, Error> }`），不破坏现有非流式协议与 `LOCAL_AGENT_MIGRATION_PLAN.md` 的"不推翻 `MedicalAIClient`"原则；未来 `LocalFoundationMedicalAIClient` 同样实现该协议即可。
- 消息模型升级：`StoredAIChatMessage` 增加 `isStreaming`/`isFailed` 状态与独立的 `thinking` 字段，废除分隔符 hack（`AIAssistantConversationViews.swift:517-534`），旧数据迁移时按分隔符拆分一次。
- UI 更新粒度采用 CatPawAgent 方式：流式时就地替换目标消息 struct，列表 `ForEach(message.id)` 稳定身份，配合 Phase 0 的缓存块 id，无需节流。
- 滚动跟随改为监听最后一条消息的文本变化（参考 CatPawAgent `ChatView.swift:82-87`，锚点 0.86），并保留适老考虑：跟随动画用 `.easeOut(duration: 0.15)` 避免眩晕。
- 验收：本地通道提问"把这条说明书摘要讲清楚"，回答逐字流出、自动跟随滚动、Markdown 实时渲染不抖动。

### Phase 2：多轮记忆（1-2 天，需隐私评审）

- `MedicalAIRequestPromptBuilder` 升级为接收最近 N 轮（建议 N=6）历史消息，拼入 prompt；本地通道直接受益。
- 历史只来自本机 SwiftData，不出设备；云端通道若保留，历史进入 prompt 前必须复用现有 consent/scope 校验（`MedicalAIRequestValidator.missingRequiredScopes`，`swift-core/.../MedicalAIModels.swift:204`）并视为一次新的数据共享范围。
- 同时放宽本地模型限制：contextLength 2048 → 4096+，并评估 `LlamaCppContext` 复用以避免每次全量加载（`LocalMedicalModelRuntime.swift:32,83`）。
- 验收：连续追问"那明天呢？"能得到结合上文的回答；共享范围摘要正确记录。

### Phase 3：云端通道流式化（可选，2-3 天，取决于外部 API 去留）

- 若按 `LOCAL_AGENT_MIGRATION_PLAN.md` Phase 4 外部 API 将退出，则本阶段可跳过，仅保留适配器 B 骨架。
- 若保留 broker：`POST /v1/respond` 增加 `Accept: text/event-stream` 分支，上游豆包 Responses API 开启 stream，逐 chunk 转发为 SSE（`data: {"delta": "..."}` + `data: [DONE]`）；保留现有非流式路径与全部安全边界（字节上限改为"累计字符上限"、限流与幂等不变）。
- iOS 侧接通适配器 B，云端与本地走同一 UI 管线。
- 验收：云端通道逐字流出；断流时落内联错误气泡（不再是 system 消息）并提供"重试"按钮。

### Phase 4：只读工具闭环（中期，需安全评审，3-5 天）

- 迁入 `Tool` 协议与 `LocalToolCoordinator`（幂等表、后缀匹配、注入式 `ToolResultReporter` 回传），实现两个**只读**工具：`query_today_doses`（今日待服/已服状态）、`query_medication_history`（近 N 天服药记录），内部走 SwiftData `ModelContext` 查询。
- 工具结果只作为事实注入模型上下文，模型无任何写路径——严格遵守 CONTEXT.md 红线：AI 输出不得创建/停止/更改药物或剂量。
- 该能力首先服务本地通道（FoundationModels 的 `Tool` API，`coreai/TECHNICAL_VALIDATION.md:89` 已提及）；云端通道不做工具闭环，避免把"模型可发起查询"的 loop 暴露给静态 token 鉴权的 broker。
- 替代收益：淘汰 `MedicalAIContextBuilder.swift:132` 的"关键词猜今天"预取逻辑，改为模型按需查询。
- 验收：问"我今天还有什么没吃？"，工具返回真实 SwiftData 数据，模型只做解读；`swift test` 与 `build_sim` 通过。

## 5. 必须守住的红线（迁移全程）

1. 模型永远不是药学规则来源，只解释本地规则与用户确认数据生成的事实（`LOCAL_AGENT_MIGRATION_PLAN.md:10`）。
2. 工具只读；requires_action 式循环不开放写操作。
3. 图片不进模型，只走本机 Vision OCR（同计划 :11）；本方案不引入附件上传。
4. 云端共享保持 opt-in 可撤销；多轮历史进入云端 prompt 前过 consent 校验。
5. UI 不暴露 key、endpoint、供应商名、"API"字样（同计划 :12）。
6. broker 的 fail-closed、限流、字节上限、幂等、测试矩阵在流式化后保持等价强度。
7. 适老优先：所有流式动画克制动效，最大 Dynamic Type 下不截断、不抖动。

## 6. 技术适配注意

- 工程为 iOS 17.0 / Swift 6.0：CatPawAgent 代码基于 `@MainActor ObservableObject + @Published`，iOS 17 兼容；迁入后需过 Swift 6 严格并发检查（actor 隔离、`Sendable` 标注），`SSEClient` 的 `AsyncThrowingStream` continuation 注意 `@Sendable` 闭包捕获。
- 不引入第三方依赖：SSEClient/HTTPClient/Markdown 三件套均为纯 Foundation + SwiftUI。
- MedCue 已有 SwiftData，CatPawAgent 的 `SessionStore`（JSON 文件双写）不迁移；如需"恢复中断轮次"，参考 `SessionRecoveryService` 思路用 SwiftData 查询实现即可。

## 7. 风险与未决项

- 本地模型流式解析靠启发式猜"推理句"（`LocalLLMStreamParser.swift:232-249`），Phase 1 上屏后该脆弱性会被用户直接感知，建议随 Phase 1 收敛为只信 `<think>/<answer>` 显式标签。
- FoundationModels 通道（iOS 26）与 llama.cpp 通道并存期间的流式协议统一，待 `LocalFoundationMedicalAIClient` 落地时验证。
- broker 流式化的云函数并发与成本未评估；若竞赛后外部 API 退出，本项自然消解。
- 多轮记忆对医疗场景的副作用（旧上下文误导）需在 Phase 2 隐私评审中一并评估，必要时提供"清空上下文"入口。

## 附录 A：与仓库开放 Issue 的对照（2026-08-23 评估）

逐一核对全部 24 个开放 issue 正文后，参考实现 CatPawAgent 的代码/架构对其中 4 个 issue 有直接帮助、3 个有间接参考价值。执行本方案各 Phase 时可顺带关闭对应 issue，建议将 issue 退出条件并入各 Phase 验收清单。

### A.1 直接帮助

**#6 [P1][Reliability] Propagate local AI cancellation through the llama token loop**

- 该 issue 要求取消外层任务即停 token 循环、重复 cancel/retry 不允许旧请求覆盖新请求、UI 请求状态只完成一次。
- CatPawAgent 现成的三重机制可对照：`ActiveTurnGuard`（`Agent/ActiveTurnGuard.swift:8-32`）以 `Token` 身份标识当前轮次，`begin/isCurrent/finish/cancelCurrent` 保证旧轮次迟到事件被丢弃——正是"旧请求不得覆盖新请求"的解法；`SSEClient` 的 `for try await` 流循环天然响应结构化并发取消；`Agent.run`（`Agent/Agent.swift:217-235`）演示了 SSE 任务与轮询任务的取消编排与单次完成语义。
- MedCue 需要新增的只是把同等取消语义穿进 llama.cpp 的 per-token 回调。

**#10 [P2][Architecture] Move AI request lifecycle behind a tested conversation session**

- CatPawAgent 的 `AgentRuntime` 即该 issue 所需 application session 的完整蓝本：拥有 send/cancel/重试、事件解释、提交顺序与恢复；View 只渲染状态、发出用户意图。
- issue 退出条件中的 stale-result suppression / duplicate completion / late events 三个测试点，分别对应 `ActiveTurnGuard`、`LocalToolCoordinator` 的 toolUseID 幂等表（`Agent/Tools/LocalToolCoordinator.swift:109-124`）、`CurrentTurnEventTracker` 的 baseline 去重，均有现成实现可对照编写测试。
- 注意依赖：#12 须先于 #10 关闭，且 #10 依赖 #1、#6。

**#11 [P2][Performance] Bound AI observation and load conversation history on demand**

- CatPawAgent `SessionStore`（`Agent/Session/SessionStore.swift:21-38`）的轻量索引与消息体分文件方案即"bounded window + on-demand load"的存储侧答案：`SessionSummary` 刻意不含 `messages`，注释明示"这是分文件方案的收益来源"。
- UI 侧 `AssistantMessageDisplayModel` 的内容指纹 diff 回答了"如何减少无关写导致的整面失效"。
- MedCue 落地时映射为 SwiftData：索引 @Model + 消息 @Model 分表 + 谓词投影。

**#9 [P2][Medical AI] Make LocalMedicalResponsePolicy a cohesive tested boundary**

- issue 痛点是解析知识散落在 policy 与 stream parser 两处。CatPawAgent 的组织方式是单一所有权：`AgentEventType` 集中全部事件常量、`AgentEventInterpreter` 是解析的唯一事实来源。
- 结合本方案 Phase 1 的统一事件契约，让 `<think>/<answer>` 标签解析只归 `LocalLLMStreamParser` 一处所有，policy 不再触碰解析，即满足退出条件"一种格式一个 owner"。

### A.2 间接参考

- **#12 [P1][Privacy] 同意撤销单一事务路径**：幂等验收条件可借用 `LocalToolCoordinator` 按意图 ID 去重的幂等表思路；事务/回滚部分 MedCue 现有 Command 模式已足够。
- **#8 [P1][Performance] 真机性能预算**：测量类 issue，代码帮不上；CatPawAgent 的 LRU 渲染缓存与稳定 id diff 是流式渲染路径过预算时的备选优化手段，"无逐字动画"设计本身即适老场景的帧率保障。
- **#22 [P1][Feature] 助手双语化**：主线为安全审查英语化，与参考实现无关；仅迁入 Markdown 渲染后中英混排显示不再受裸 `Text` 限制。

### A.3 与本方案阶段的对应关系

| 方案阶段 | 可顺带关闭的 issue |
|---|---|
| Phase 1（统一流式事件契约） | #6、#9（解析权收拢部分） |
| Phase 1 + 会话对象化 | #10 |
| Phase 2（多轮记忆 + 历史窗口） | #11 |
| —（独立小改） | #12 的幂等部分 |

其中 #6 为 P1、被 #28 明确排除在其范围外、当前无人认领，是最值得优先用 CatPawAgent 模式攻坚的 issue。

### A.4 确认无关的 issue

#2、#4、#5、#7、#13、#14、#15、#16、#17、#18、#19、#20、#21、#28、#33 涉及 Live Activity 鉴权、发布打包、用药旅程自动化测试、PDF 隐私、锁屏可见性、数据恢复、部署密钥治理、真机验收矩阵、Today/Add Medication 架构、双语与文档治理等，与参考实现的能力范围无关，不在本方案覆盖之内。
