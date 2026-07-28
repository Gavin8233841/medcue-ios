# 技术验证：Core AI 与 FoundationModels

## 结论摘要

当前可以推进端侧智能体，但要分两步：

1. **现在可落地**：基于 `FoundationModels.framework` 的本地智能体适配器。
2. **等工具链后可升级**：基于 Apple Core AI models repository 的自带 Qwen/Mistral `.aimodel`。

这不是概念替换，而是对现有架构的自然扩展：当前项目已有 `MedicalAIClient` 协议、`MedicalAIRequest`、`MedicalAIRequestPromptBuilder`、`MedicalAIResponseBoundaryGuard` 和授权范围控制。新增 `LocalFoundationMedicalAIClient` 后，可以复用这些边界。

## 官方资料依据

- Apple Developer 视频：`https://developer.apple.com/videos/play/wwdc2026/326/`
- Apple Core AI Models：`https://github.com/apple/coreai-models`
- Apple Foundation Models：`https://developer.apple.com/documentation/foundationmodels`
- Apple Background Assets：`https://developer.apple.com/documentation/backgroundassets`

WWDC26 326 页面摘要说明：Core AI 提供 Qwen、Mistral、SAM3 等开源模型的 Apple silicon 优化集合，可下载、运行、benchmark，并集成到 App；也介绍 model compilation、on-device specialization 和 Xcode Core AI tools。

视频 transcript 中的关键工程点：

- Core AI 能让用户数据留在设备本地，不需要服务器、token 成本或云端延迟。
- Core AI Models repository 提供模型、Python conversion utilities 和 Swift runtime libraries，减少模型特定的前后处理工作。
- 语言模型可以通过 `CoreAILanguageModel` 指向模型 bundle，再用 `FoundationModels.LanguageModelSession` 统一调用。
- 首次 specialization 可能很慢，应该放在功能首次介绍或用户主动开启流程中。
- 大模型不建议直接塞进 App 包；应使用 Background Assets，在用户主动开启功能后下载。
- AOT compilation 可以把昂贵的编译步骤提前到开发机完成，减少设备端首次等待。

## 本机 SDK 证据

执行环境：

```text
Xcode 26.5
Build version 17F42
iOS SDK 26.5
iOS Simulator SDK 26.5
```

SDK 文件存在：

```text
iPhoneOS.sdk/System/Library/Frameworks/FoundationModels.framework
iPhoneOS.sdk/System/Library/Frameworks/Vision.framework
iPhoneOS.sdk/System/Library/Frameworks/NaturalLanguage.framework
iPhoneSimulator.sdk/System/Library/Frameworks/FoundationModels.framework
iPhoneSimulator.sdk/System/Library/Frameworks/Vision.framework
iPhoneSimulator.sdk/System/Library/Frameworks/NaturalLanguage.framework
```

未发现：

```text
CoreAI.framework
```

Swift 编译器探针：

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  -e 'import FoundationModels; print("FoundationModels import ok")'
```

结果：

```text
FoundationModels import ok
```

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  -e 'import FoundationModels; print(LanguageModelSession.self); print(SystemLanguageModel.self)'
```

结果：

```text
LanguageModelSession
SystemLanguageModel
```

Swift interface 证据：

- `LanguageModelSession` 是公开 final class。
- 有 `respond(to:)`、`streamResponse(to:)`、`respond(generating:)`。
- 有 `@Generable`、`GenerationOptions`、`Tool`。
- 有 `SystemLanguageModel.default` 和 `SystemLanguageModel.default.availability`。

## 当前限制

Apple `apple/coreai-models` README 当前写明：

- running and app integration: macOS and iOS 27.0+
- Xcode 27.0+

本项目当前机器为 Xcode 26.5，所以不能直接把 Qwen/Mistral `.aimodel` 集成到主 App 并声称已可构建。若现在硬接 Core AI models repo，会大概率卡在工具链和 SDK 版本。

## 对本 App 的可行实现

短期可行方案：

- 新增 `LocalFoundationMedicalAIClient`。
- 使用 `FoundationModels.LanguageModelSession(model: .default, instructions: ...)`。
- 每次发送前检查 `SystemLanguageModel.default.availability`。
- 输入继续走 `MedicalAIRequestPromptBuilder`，输出继续走 `MedicalAIResponseBoundaryGuard`。
- 对用户展示“本机智能体”，不要展示模型、endpoint、key 或外部供应商配置。

适合本地模型承担：

- 说明书短句解释。
- 风险原因解释。
- 天气与用药计划的非诊断性提醒。
- 近 7 天/近 60 天服药记录摘要。
- 复诊沟通草稿。

不交给模型独立判断：

- 药物禁忌是否成立。
- 药物相互作用是否成立。
- 剂量是否应调整。
- 是否停药。
- 诊断、处方或疗效判断。

## 用户首次点击声明建议

第一次进入智能体或第一次启用本机智能体时显示：

```text
智能体会在本机处理你授权共享的用药记录、说明书摘要和风险提醒。图片不会上传给模型；如需识别图片，App 会先在本机提取文字，再用于本次解释。智能体只用于说明书可读化、用药记录总结和复诊沟通准备，不能替代医生或药师判断。
```

按钮：

- `启用本机智能体`
- `暂不使用`

如果 `SystemLanguageModel.default.availability` 不可用：

```text
本机智能体暂时不可用。你仍可使用本地提醒、记录、风险复核和复诊资料。
```
