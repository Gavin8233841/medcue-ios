# 发给竞赛-救援接力线程的提示词

请接手一个独立构建验证任务，不要覆盖主线程进展，不要清理工作区，不要删除文件。

项目路径：

`REDACTED_HOME_PATH`

背景：

主线程正在评估把智能体 Tab 从外部豆包/百川 API 迁移为端侧本机智能体。用户明确支持“本机 OCR 接语言模型”的方案：图片不直接发送给模型，只在本机 OCR 后把文字交给语言模型解释。你负责构建验证，不要改动当前主线 UI 行为。

请先读取：

- `coreai/README.md`
- `coreai/DEVELOPMENT_LOG.md`
- `coreai/TECHNICAL_VALIDATION.md`
- `coreai/LOCAL_AGENT_MIGRATION_PLAN.md`
- `coreai/probes/FoundationModelsSmokeProbe.swift`
- `swift-core/Sources/MedicationAdherenceCore/MedicalAIModels.swift`
- `swift-core/Sources/MedicationAdherenceCore/MedicalAIPromptBuilder.swift`
- `swift-core/Sources/MedicationAdherenceCore/MedicalAIResponseBoundary.swift`
- `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/AIAssistantView.swift`

核心结论：

- 当前 Xcode 26.5 可编译 `FoundationModels`，识别 `LanguageModelSession` 和 `SystemLanguageModel`。
- 当前未发现公开 `CoreAI.framework`。
- Apple `apple/coreai-models` README 写明 app integration 需要 macOS/iOS 27.0+ 和 Xcode 27.0+，所以现在不要硬接 Qwen/Mistral `.aimodel` 主线。
- 现在要先验证 `FoundationModels` 本地智能体路线。

任务范围：

1. 不改主 App 行为的前提下，新增一个最小本地客户端文件：
   `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Services/LocalFoundationMedicalAIClient.swift`
2. 该文件可先不被 `AIAssistantView` 使用，但必须能随 App target 编译。
3. `LocalFoundationMedicalAIClient` 应遵守当前 `MedicalAIClient` 协议，使用 `FoundationModels`。
4. 发送前必须检查 `SystemLanguageModel.default.availability`；不可用时抛出或返回产品化错误，不伪装成模型回复。
5. prompt 复用 `MedicalAIRequestPromptBuilder().buildPrompt(for:)`。
6. 输出必须经过 `MedicalAIResponseBoundaryGuard` 或至少保持 100 字、纯文本、不能替代医生或药师判断的边界。
7. 不要读取、打印或展示任何 API key。
8. 不要删除或回退豆包/百川适配器。
9. 不要接入图片模型；图片仍由现有 `VisionImportService` OCR。

建议最小 API 方向，请以 SDK swiftinterface 为准，不要猜不存在的名字：

```swift
import FoundationModels
import MedicationAdherenceCore

struct LocalFoundationMedicalAIClient: MedicalAIClient {
    func respond(to request: MedicalAIRequest) async throws -> MedicalAIResponse {
        let model = SystemLanguageModel.default
        // check model.availability
        let session = LanguageModelSession(
            model: model,
            instructions: "你是本机端侧用药说明智能体，只解释用户授权共享的数据，不能替代医生或药师判断。"
        )
        let prompt = MedicalAIRequestPromptBuilder().buildPrompt(for: request)
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 120)
        )
        // return MedicalAIResponse(...)
    }
}
```

验证命令：

```zsh
cd REDACTED_HOME_PATH
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
```

```zsh
cd REDACTED_HOME_PATH
./tools/ios-preflight-check.sh
```

再用 Build iOS Apps MCP：

- `session_show_defaults`
- `build_sim({ "extraArgs": ["CODE_SIGNING_ALLOWED=NO"] })`

请最终回报：

- 改了哪些文件。
- `FoundationModels` 编译是否通过。
- `SystemLanguageModel.default.availability` 是否能在模拟器或真机运行时检查。
- 是否存在 API 名称不匹配，需要主线程更新方案。
- 不要安装 Xcode 27，不要下载大模型，不要接真实 Core AI `.aimodel`。
