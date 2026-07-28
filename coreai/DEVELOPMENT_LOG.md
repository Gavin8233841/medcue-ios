# Core AI 本地智能体开发日志

## 2026-06-11 02:30 初始技术评估与资料包创建

- 目标：评估并推动用端侧 AI 替代智能体 Tab 外部 API 依赖；图片不直接发给模型，而是由本机 OCR 提取文字后交给语言模型。
- 已创建：项目根目录 `coreai/`，用于保存技术验证资料、开发日志、迁移计划、救援线程构建提示和最小探针源码。
- Apple 官方资料：
  - WWDC26 326《Integrate on-device AI models into your app using Core AI》说明 Core AI 可把 Qwen、Mistral、SAM3 等模型优化到 Apple silicon 端侧运行。
  - 该视频 transcript 明确提到：Core AI 端侧运行可让用户数据不离开设备、无服务器、无 token 成本、无云端延迟；可通过 Core AI Models repository 获得模型和 Swift runtime utilities；语言模型可结合 `FoundationModels` 的 `LanguageModelSession` 使用。
  - 视频也强调首次 model specialization 可能很慢，应放到功能首次介绍流程中，并可通过 Background Assets 和 AOT 编译降低首用等待。
- 本机证据：
  - Xcode：`26.5`，Build version `17F42`。
  - SDK：`iphoneos26.5` / `iphonesimulator26.5`。
  - iPhoneOS 与 iPhoneSimulator SDK 都包含 `FoundationModels.framework`、`Vision.framework`、`NaturalLanguage.framework`。
  - 未找到公开 `CoreAI.framework`。
  - Swift 编译器已验证：
    - `import FoundationModels` 成功。
    - `LanguageModelSession.self` 可识别。
    - `SystemLanguageModel.self` 可识别。
  - `FoundationModels.swiftinterface` 显示 `LanguageModelSession` 有 `respond(to:)`、`streamResponse(to:)`、`respond(generating:)` 等 API，并支持 `@Generable`、`GenerationOptions`、`Tool`、`SystemLanguageModel.default.availability`。
- Core AI models repository 证据：
  - `https://github.com/apple/coreai-models` README 写明运行和 app integration 需要 macOS/iOS 27.0+、Xcode 27.0+。
  - 当前主机只有 Xcode 26.5，因此不能直接把 Core AI `.aimodel` 路线当作当前可构建主线。
- 当前决策：
  - 短期：先实现 `FoundationModels` 本地智能体适配层，作为外部智能体替代方案的第一阶段。
  - 中期：在 Xcode 27 可用后，将同一适配层底层切换或扩展为 Core AI models repo 的 Qwen/Mistral `.aimodel`。
  - 不改动现有主 App 智能体源码，先交给“竞赛-救援接力”线程构建验证。

## 待验证清单

- [ ] 在救援线程编译最小 `FoundationModels` 适配器。
- [ ] 确认真机 `SystemLanguageModel.default.availability` 状态。
- [ ] 设计本地模型不可用时的用户提示，不再出现外部 API 配置感文案。
- [ ] 验证 `MedicalAIResponseBoundaryGuard` 对本地模型输出仍能保持 100 字、纯文本、安全边界。
- [ ] 用 OCR 文本输入路径替代“发送图片给模型”的入口。
- [ ] 确定是否保留豆包/百川备用开关；默认 UI 不展示外部供应商配置。
