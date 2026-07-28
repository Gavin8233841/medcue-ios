# 本地智能体迁移计划

## 迁移目标

把当前智能体 Tab 从“外部豆包/百川 API 为默认依赖”迁移为“本机端侧 AI 优先”。外部 API 不再作为核心演示路径，最多保留为隐藏备用或后续删除项。

## 架构原则

- 不推翻当前 `MedicalAIClient` 协议，新增本地实现即可。
- 不让语言模型成为药学规则来源。模型只解释已经由 App 本地规则和用户确认数据生成的事实。
- 不把图片发给模型。图片只进入本机 Vision OCR、条码识别或药品照片记忆位。
- 不在用户端展示 key、endpoint、模型配置、调试项或“API”字样。
- 首次启用本机智能体时做明确本地处理声明。

## 分阶段执行

### Phase 0：独立技术验证

负责人：救援接力线程。

目标：

- 在不改主 App 行为的前提下，新增最小 `FoundationModels` 编译探针或本地客户端文件。
- 验证 `FoundationModels` 在 iOS Simulator Debug build 中可编译。
- 如果模拟器不能运行模型，至少编译通过并在真机检查 `SystemLanguageModel.default.availability`。

建议文件：

- `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Services/LocalFoundationMedicalAIClient.swift`
- `swift-core` 不直接 import `FoundationModels`，保持跨平台纯 Swift。

### Phase 1：本地客户端适配

新增 `LocalFoundationMedicalAIClient`：

- 遵守 `MedicalAIClient`。
- 输入：`MedicalAIRequest`。
- prompt：复用 `MedicalAIRequestPromptBuilder().buildPrompt(for:)`。
- session：`LanguageModelSession(model: .default, instructions: ...)`。
- options：`GenerationOptions(temperature: 0.2, maximumResponseTokens: 120)`，最终仍由 `MedicalAIResponseBoundaryGuard` 收束到用户端可读内容。
- availability：如果不可用，返回用户端系统状态，不伪装为模型回复。

### Phase 2：智能体页接入

修改 `AIAssistantView` 的 client selection：

- 默认使用本机客户端。
- 本机不可用时显示本机不可用提示。
- 外部豆包/百川保留为 Debug 或隐藏备用，不再作为用户默认体验。

用户首次声明：

- 复用现有第三方智能体 notice 的时机，但文案改为“本机智能体”。
- 加入“图片不会上传给模型，本机 OCR 后只发送文字”的说明。

### Phase 3：图片入口降级

当前图片咨询入口保留按钮，但语义改为：

- `识别图片文字`
- 选择图片后走 `VisionImportService`。
- 只把 OCR 文本和用户问题送到本地模型。
- 如果 OCR 没读出文字，提示用户手动输入药名、规格、说明书片段。

### Phase 4：外部 API 退出策略

- 保留 `DoubaoMedicalAIClient` / `BaichuanMedicalAIClient` 文件，直到本地真机链路稳定。
- UI 不再展示外部供应商。
- docs 标注外部 API 为历史演示备用。
- 最终版本可移除 `AISecrets.plist` 注入和相关 preflight 项，但这一步必须另起任务，不在当前验证阶段删除。

## 验收标准

- `swift test` 通过。
- `build_sim` 通过。
- 智能体 Tab 可发送以下三类问题：
  - “把这条说明书摘要讲清楚。”
  - “今天的天气对我的用药有什么影响？”
  - “最近一周我的服药记录有什么要复诊时说明？”
- 不展示 key、endpoint、API、调试项。
- 本机不可用时不假回答。
- 图片不会上传给语言模型。
