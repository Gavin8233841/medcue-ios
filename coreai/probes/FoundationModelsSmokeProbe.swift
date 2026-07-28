import FoundationModels

@available(iOS 26.0, *)
struct FoundationModelsSmokeProbe {
    func makeSession() -> LanguageModelSession {
        LanguageModelSession(
            model: .default,
            instructions: "你是本机端侧用药说明智能体，只解释用户授权共享的数据。"
        )
    }

    func availabilityDescription() -> String {
        "\(SystemLanguageModel.default.availability)"
    }
}
