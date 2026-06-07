import Foundation
import Security

struct MedicalAIConfiguration: Equatable, Sendable {
    static let baichuanProviderName = "百川智能"
    static let baichuanDefaultModelName = "Baichuan-M3-Plus"
    static let baichuanChatEndpoint = "https://api.baichuan-ai.com/v1/chat/completions"
    static let baichuanLicenseSummary = "百川医疗大模型 API；请求由用户授权后从 App 直连发送。"
    static let doubaoProviderName = "豆包"
    static let doubaoDefaultModelName = "doubao-seed-2-0-lite-260428"
    static let doubaoResponsesEndpoint = "https://ark.cn-beijing.volces.com/api/v3/responses"
    static let doubaoLicenseSummary = "火山引擎豆包模型 API；请求由用户授权后从 App 直连发送。"

    var providerName: String
    var modelName: String
    var endpointURLString: String
    var hasAPIKey: Bool

    var isReadyForDirectAPI: Bool {
        !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: endpointURLString) != nil
            && hasAPIKey
    }

    var sanitizedDebugSummary: String {
        let endpointHost = URL(string: endpointURLString)?.host ?? "invalid-endpoint"
        let providerSet = !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let modelSet = !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return "providerSet=\(providerSet) provider=\(providerName) modelSet=\(modelSet) endpointHost=\(endpointHost) hasAPIKey=\(hasAPIKey)"
    }
}

@MainActor
final class SecureAIConfigurationStore: ObservableObject {
    @Published private(set) var configuration: MedicalAIConfiguration
    @Published private(set) var statusMessage: String

    private let defaults = UserDefaults.standard
    private let providerNameKey = "medicalAI.providerName"
    private let modelNameKey = "medicalAI.modelName"
    private let endpointURLKey = "medicalAI.endpointURL"
    private let keychainService = "com.gwyy.appcontest2026.medicationadherence.medical-ai"
    private let keychainAccount = "api-key"
    private let injectedAPIKeyEnvironmentName = "BAICHUAN_MEDICAL_AI_API_KEY"
    private let injectedArkAPIKeyEnvironmentName = "ARK_API_KEY"

    init() {
        var injectionSummary = "none"
        if let injectedArkAPIKey = Self.injectedSecret(named: injectedArkAPIKeyEnvironmentName)
            ?? Self.bundledSecret(named: injectedArkAPIKeyEnvironmentName) {
            let status = Self.writeKeychainValue(injectedArkAPIKey, service: keychainService, account: keychainAccount)
            defaults.set(MedicalAIConfiguration.doubaoProviderName, forKey: providerNameKey)
            defaults.set(MedicalAIConfiguration.doubaoDefaultModelName, forKey: modelNameKey)
            defaults.set(MedicalAIConfiguration.doubaoResponsesEndpoint, forKey: endpointURLKey)
            injectionSummary = "\(injectedArkAPIKeyEnvironmentName) source=\(Self.injectionSourceDescription(for: injectedArkAPIKeyEnvironmentName)) keychainStatus=\(Self.securityStatusDescription(status))"
        } else if let injectedAPIKey = Self.injectedSecret(named: injectedAPIKeyEnvironmentName)
            ?? Self.bundledSecret(named: injectedAPIKeyEnvironmentName) {
            let status = Self.writeKeychainValue(injectedAPIKey, service: keychainService, account: keychainAccount)
            defaults.set(MedicalAIConfiguration.baichuanProviderName, forKey: providerNameKey)
            defaults.set(MedicalAIConfiguration.baichuanDefaultModelName, forKey: modelNameKey)
            defaults.set(MedicalAIConfiguration.baichuanChatEndpoint, forKey: endpointURLKey)
            injectionSummary = "\(injectedAPIKeyEnvironmentName) source=\(Self.injectionSourceDescription(for: injectedAPIKeyEnvironmentName)) keychainStatus=\(Self.securityStatusDescription(status))"
        }

        let hasKey = Self.readKeychainValue(service: keychainService, account: keychainAccount) != nil
            || Self.injectedSecret(named: injectedArkAPIKeyEnvironmentName) != nil
            || Self.bundledSecret(named: injectedArkAPIKeyEnvironmentName) != nil
            || Self.injectedSecret(named: injectedAPIKeyEnvironmentName) != nil
            || Self.bundledSecret(named: injectedAPIKeyEnvironmentName) != nil
        configuration = MedicalAIConfiguration(
            providerName: Self.defaulted(defaults.string(forKey: providerNameKey), fallback: MedicalAIConfiguration.doubaoProviderName),
            modelName: Self.defaulted(defaults.string(forKey: modelNameKey), fallback: MedicalAIConfiguration.doubaoDefaultModelName),
            endpointURLString: Self.defaulted(defaults.string(forKey: endpointURLKey), fallback: MedicalAIConfiguration.doubaoResponsesEndpoint),
            hasAPIKey: hasKey
        )
        statusMessage = hasKey ? "医疗 AI API 已配置，密钥保存在 Keychain。" : "医疗 AI endpoint 和模型已预填；添加 Keychain 密钥前不会外发用药数据。"
        Self.debugLog("init \(configuration.sanitizedDebugSummary) injected=\(injectionSummary)")
    }

    func save(providerName: String, modelName: String, endpointURLString: String, apiKey: String) {
        let trimmedProvider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedProvider, forKey: providerNameKey)
        defaults.set(trimmedModel, forKey: modelNameKey)
        defaults.set(trimmedEndpoint, forKey: endpointURLKey)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let status = Self.writeKeychainValue(trimmedKey, service: keychainService, account: keychainAccount)
            Self.debugLog("manual-save keychainStatus=\(Self.securityStatusDescription(status))")
        }
        reload(status: "配置已保存。密钥仅保存在 Keychain；发送前仍会校验用户授权范围。")
    }

    func apiKey() -> String? {
        Self.readKeychainValue(service: keychainService, account: keychainAccount)
            ?? Self.injectedSecret(named: injectedArkAPIKeyEnvironmentName)
            ?? Self.bundledSecret(named: injectedArkAPIKeyEnvironmentName)
            ?? Self.injectedSecret(named: injectedAPIKeyEnvironmentName)
            ?? Self.bundledSecret(named: injectedAPIKeyEnvironmentName)
    }

    func clearAPIKey() {
        Self.deleteKeychainValue(service: keychainService, account: keychainAccount)
        reload(status: "API 密钥已从 Keychain 移除。")
    }

    func clearAll() {
        defaults.removeObject(forKey: providerNameKey)
        defaults.removeObject(forKey: modelNameKey)
        defaults.removeObject(forKey: endpointURLKey)
        Self.deleteKeychainValue(service: keychainService, account: keychainAccount)
        reload(status: "已恢复默认医疗 AI endpoint 和模型；Keychain 密钥已移除。")
    }

    private func reload(status: String) {
        configuration = MedicalAIConfiguration(
            providerName: Self.defaulted(defaults.string(forKey: providerNameKey), fallback: MedicalAIConfiguration.doubaoProviderName),
            modelName: Self.defaulted(defaults.string(forKey: modelNameKey), fallback: MedicalAIConfiguration.doubaoDefaultModelName),
            endpointURLString: Self.defaulted(defaults.string(forKey: endpointURLKey), fallback: MedicalAIConfiguration.doubaoResponsesEndpoint),
            hasAPIKey: apiKey() != nil
        )
        statusMessage = status
    }

    private static func defaulted(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func injectedSecret(named name: String) -> String? {
        if let value = trimmedNonEmpty(ProcessInfo.processInfo.environment[name]) {
            return value
        }
        if let value = trimmedNonEmpty(UserDefaults.standard.string(forKey: name)) {
            return value
        }
        let assignmentPrefix = "\(name)="
        return ProcessInfo.processInfo.arguments.compactMap { argument in
            guard argument.hasPrefix(assignmentPrefix) else {
                return nil
            }
            return trimmedNonEmpty(String(argument.dropFirst(assignmentPrefix.count)))
        }
        .first
    }

    private static func bundledSecret(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: "AISecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return trimmedNonEmpty(plist[name] as? String)
    }

    private static func injectionSourceDescription(for name: String) -> String {
        if trimmedNonEmpty(ProcessInfo.processInfo.environment[name]) != nil {
            return "environment"
        }
        if trimmedNonEmpty(UserDefaults.standard.string(forKey: name)) != nil {
            return "user-defaults"
        }
        let assignmentPrefix = "\(name)="
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix(assignmentPrefix) }) {
            return "argument"
        }
        if bundledSecret(named: name) != nil {
            return "bundle"
        }
        return "none"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    @discardableResult
    private static func writeKeychainValue(_ value: String, service: String, account: String) -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status
    }

    private static func readKeychainValue(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainValue(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func securityStatusDescription(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            "success"
        case errSecItemNotFound:
            "item-not-found"
        case errSecMissingEntitlement:
            "missing-entitlement"
        default:
            "status-\(status)"
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[MedicalAIConfig] \(message)")
        #endif
    }
}
