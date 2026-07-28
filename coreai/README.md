# Core AI / 本地智能体验证包

本目录用于推进“用端侧 AI 替代智能体 Tab 外部 API 依赖”的技术验证与交接。当前不直接改主 App 源码，先把可行路线、证据、构建提示和迁移边界固定下来，避免未验证方案污染稳定主线。

## 当前结论

- 当前 Xcode 26.5 / iOS 26.5 SDK 已包含 `FoundationModels.framework`，并且本机 Swift 编译器可以导入 `FoundationModels`，识别 `LanguageModelSession` 与 `SystemLanguageModel`。
- Apple WWDC26 326 视频介绍的 Core AI models repository 路线可以让 Qwen、Mistral、SAM3 等开源模型以 Core AI 格式在设备端运行，但 Apple 官方 `apple/coreai-models` README 当前写明 app integration 需要 macOS/iOS 27.0+ 与 Xcode 27.0+。
- 因此当前最稳妥路线是先用 `FoundationModels` 做“本地智能体”适配层，验证说明书解释、风险解释、天气与记录问答；等 Xcode 27 / iOS 27 工具链就绪后，再把同一适配层底层切换到自带 Qwen/Mistral `.aimodel`。

## 产品策略

- 智能体 Tab 目标：本地 AI 优先，外部豆包/百川仅作为隐藏备用或后续删除项。
- 图片能力策略：不再向模型发送图片。图片仅走本机 Vision OCR / 条码 / 用户确认照片，提取出的文本或已确认说明书摘要再交给本地语言模型解释。
- 医疗安全边界：本地模型只负责说明书可读化、记录摘要、风险原因解释和复诊沟通草稿；禁忌、相互作用、剂量变化、是否停药仍由本地规则、说明书证据和用户确认数据驱动。

## 文件说明

- `DEVELOPMENT_LOG.md`：本地智能体验证和迁移日志。
- `TECHNICAL_VALIDATION.md`：Apple 官方资料、本机 SDK 证据、可行性与限制。
- `LOCAL_AGENT_MIGRATION_PLAN.md`：从外部医疗智能体迁移到端侧智能体的分阶段计划。
- `RESCUE_THREAD_BUILD_PROMPT.md`：发给“竞赛-救援接力”线程的构建提示词。
- `probes/FoundationModelsSmokeProbe.swift`：最小 Swift API 探针源码，用于先验证 `FoundationModels` 编译入口。

## 下一步

1. 救援线程先在独立分支/工作区构建 `FoundationModels` 最小适配器，不碰现有豆包/百川链路。
2. 通过后新增 `LocalMedicalAIClient`，实现当前 `MedicalAIClient` 协议，输入仍用 `MedicalAIRequestPromptBuilder`。
3. 智能体页面首次点击时提示：该功能使用本机端侧智能模型处理，图片只在本机识别文字，不上传图片。
4. 运行 `swift test`、`build_sim`、模拟器发送“说明书解释 / 天气影响 / 服药记录摘要”三类问题。
5. 如果真机 `SystemLanguageModel.default.availability` 不可用，则保留清晰的本机不可用提示和外部备用策略。
