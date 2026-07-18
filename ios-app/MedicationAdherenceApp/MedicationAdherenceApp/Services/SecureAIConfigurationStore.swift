import Foundation
import Security

enum MedicalAIProviderKind: String, Sendable {
    case doubao
    case baichuan
}

struct MedicalAITransportReadiness: Equatable, Sendable {
    var canSend: Bool
    var userFacingMessage: String?
    var diagnosticSummary: String
}

struct MedicalAIConfiguration: Equatable, Sendable {
    static let baichuanProviderName = "百川智能"
    static let baichuanDefaultModelName = "Baichuan-M3-Plus"
    static let baichuanChatEndpoint = "https://api.baichuan-ai.com/v1/chat/completions"
    static let baichuanLicenseSummary = "百川医疗智能体；仅在用户授权后处理本次咨询。"
    static let doubaoProviderName = "豆包"
    static let doubaoDefaultModelName = "doubao-seed-2-0-lite-260428"
    static let doubaoResponsesEndpoint = "https://ark.cn-beijing.volces.com/api/v3/responses"
    static let doubaoLicenseSummary = "火山引擎豆包智能体；仅在用户授权后处理本次咨询。"

    var providerName: String
    var modelName: String
    var endpointURLString: String
    var hasAPIKey: Bool

    var providerKind: MedicalAIProviderKind {
        Self.providerKind(providerName: providerName, endpointURLString: endpointURLString)
    }

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
        return "providerSet=\(providerSet) provider=\(providerName) providerKind=\(providerKind.rawValue) modelSet=\(modelSet) endpointHost=\(endpointHost) hasAPIKey=\(hasAPIKey)"
    }

    static func providerKind(providerName: String, endpointURLString: String) -> MedicalAIProviderKind {
        let host = URL(string: endpointURLString)?.host
        let doubaoHost = URL(string: doubaoResponsesEndpoint)?.host
        if host == doubaoHost || providerName == doubaoProviderName {
            return .doubao
        }
        return .baichuan
    }
}

@MainActor
final class SecureAIConfigurationStore: ObservableObject {
    @Published private(set) var configuration: MedicalAIConfiguration
    @Published private(set) var statusMessage: String

    private let defaults = UserDefaults.standard
    private static let providerNameKey = "medicalAI.providerName"
    private static let modelNameKey = "medicalAI.modelName"
    private static let endpointURLKey = "medicalAI.endpointURL"
    private static let keychainService = "com.gwyy.appcontest2026.medicationadherence.medical-ai"
    private static let legacyKeychainAccount = "api-key"
    private static let doubaoKeychainAccount = "api-key.doubao"
    private static let baichuanKeychainAccount = "api-key.baichuan"
    private static let injectedAPIKeyEnvironmentName = "BAICHUAN_MEDICAL_AI_API_KEY"
    private static let injectedArkAPIKeyEnvironmentName = "ARK_API_KEY"

    init() {
        let injectionSummary = Self.syncBestAvailableSecret(into: defaults)

        let providerName = Self.defaulted(defaults.string(forKey: Self.providerNameKey), fallback: MedicalAIConfiguration.doubaoProviderName)
        let modelName = Self.defaulted(defaults.string(forKey: Self.modelNameKey), fallback: MedicalAIConfiguration.doubaoDefaultModelName)
        let endpointURLString = Self.defaulted(defaults.string(forKey: Self.endpointURLKey), fallback: MedicalAIConfiguration.doubaoResponsesEndpoint)
        let providerKind = MedicalAIConfiguration.providerKind(providerName: providerName, endpointURLString: endpointURLString)
        let keyLookup = Self.lookupAPIKey(for: providerKind)
        configuration = MedicalAIConfiguration(
            providerName: providerName,
            modelName: modelName,
            endpointURLString: endpointURLString,
            hasAPIKey: keyLookup.key != nil
        )
        statusMessage = keyLookup.key != nil ? "医疗智能体已就绪；发送前仍会校验用户授权范围。" : "医疗智能体暂时不可用；不会外发用药数据。"
        Self.debugLog("init \(configuration.sanitizedDebugSummary) keySource=\(keyLookup.sourceDescription) injected=\(injectionSummary)")
    }

    @discardableResult
    func refreshInjectedSecretsIfAvailable() -> MedicalAIConfiguration {
        let injectionSummary = Self.syncBestAvailableSecret(into: defaults)
        let providerName = Self.defaulted(defaults.string(forKey: Self.providerNameKey), fallback: MedicalAIConfiguration.doubaoProviderName)
        let endpointURLString = Self.defaulted(defaults.string(forKey: Self.endpointURLKey), fallback: MedicalAIConfiguration.doubaoResponsesEndpoint)
        let providerKind = MedicalAIConfiguration.providerKind(providerName: providerName, endpointURLString: endpointURLString)
        let keyLookup = Self.lookupAPIKey(for: providerKind)
        reload(status: keyLookup.key == nil ? Self.unavailableUserMessage : "医疗智能体已就绪；发送前仍会校验用户授权范围。")
        Self.debugLog("refresh \(configuration.sanitizedDebugSummary) keySource=\(keyLookup.sourceDescription) injected=\(injectionSummary)")
        return configuration
    }

    func save(providerName: String, modelName: String, endpointURLString: String, apiKey: String) {
        let trimmedProvider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedProvider, forKey: Self.providerNameKey)
        defaults.set(trimmedModel, forKey: Self.modelNameKey)
        defaults.set(trimmedEndpoint, forKey: Self.endpointURLKey)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            let providerKind = MedicalAIConfiguration.providerKind(providerName: trimmedProvider, endpointURLString: trimmedEndpoint)
            let status = Self.writeKeychainValue(
                trimmedKey,
                service: Self.keychainService,
                account: Self.keychainAccount(for: providerKind)
            )
            Self.debugLog("manual-save providerKind=\(providerKind.rawValue) keychainStatus=\(Self.securityStatusDescription(status))")
        }
        reload(status: "医疗智能体已更新；发送前仍会校验用户授权范围。")
    }

    func apiKey() -> String? {
        apiKey(for: configuration)
    }

    func apiKey(for configuration: MedicalAIConfiguration) -> String? {
        Self.lookupAPIKey(for: configuration.providerKind).key
    }

    func apiKeySourceDescription(for configuration: MedicalAIConfiguration) -> String {
        Self.lookupAPIKey(for: configuration.providerKind).sourceDescription
    }

    func readiness(for configuration: MedicalAIConfiguration) -> MedicalAITransportReadiness {
        if configuration.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MedicalAITransportReadiness(
                canSend: false,
                userFacingMessage: Self.unavailableUserMessage,
                diagnosticSummary: "missing-provider"
            )
        }
        if configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MedicalAITransportReadiness(
                canSend: false,
                userFacingMessage: Self.unavailableUserMessage,
                diagnosticSummary: "missing-model providerKind=\(configuration.providerKind.rawValue)"
            )
        }
        if URL(string: configuration.endpointURLString) == nil {
            return MedicalAITransportReadiness(
                canSend: false,
                userFacingMessage: Self.unavailableUserMessage,
                diagnosticSummary: "invalid-endpoint providerKind=\(configuration.providerKind.rawValue)"
            )
        }
        let keyLookup = Self.lookupAPIKey(for: configuration.providerKind)
        guard keyLookup.key != nil else {
            return MedicalAITransportReadiness(
                canSend: false,
                userFacingMessage: Self.unavailableUserMessage,
                diagnosticSummary: "missing-api-key providerKind=\(configuration.providerKind.rawValue) keySource=\(keyLookup.sourceDescription)"
            )
        }
        return MedicalAITransportReadiness(
            canSend: true,
            userFacingMessage: nil,
            diagnosticSummary: "ready providerKind=\(configuration.providerKind.rawValue) keySource=\(keyLookup.sourceDescription)"
        )
    }

    func clearAPIKey() {
        Self.deleteKeychainValue(service: Self.keychainService, account: Self.keychainAccount(for: configuration.providerKind))
        reload(status: "医疗智能体已断开；不会外发用药数据。")
    }

    func promoteCurrentAPIKeyIfNeeded(for configuration: MedicalAIConfiguration) {
        let lookup = Self.lookupAPIKey(for: configuration.providerKind)
        guard let key = lookup.key else {
            return
        }
        let status = Self.writeKeychainValue(
            key,
            service: Self.keychainService,
            account: Self.keychainAccount(for: configuration.providerKind)
        )
        Self.debugLog("promote-key providerKind=\(configuration.providerKind.rawValue) from=\(lookup.sourceDescription) keychainStatus=\(Self.securityStatusDescription(status))")
        reload(status: statusMessage)
    }

    func clearAll() {
        defaults.removeObject(forKey: Self.providerNameKey)
        defaults.removeObject(forKey: Self.modelNameKey)
        defaults.removeObject(forKey: Self.endpointURLKey)
        Self.deleteKeychainValue(service: Self.keychainService, account: Self.keychainAccount(for: .doubao))
        Self.deleteKeychainValue(service: Self.keychainService, account: Self.keychainAccount(for: .baichuan))
        Self.deleteKeychainValue(service: Self.keychainService, account: Self.legacyKeychainAccount)
        reload(status: "医疗智能体已重置；不会外发用药数据。")
    }

    private func reload(status: String) {
        let providerName = Self.defaulted(defaults.string(forKey: Self.providerNameKey), fallback: MedicalAIConfiguration.doubaoProviderName)
        let modelName = Self.defaulted(defaults.string(forKey: Self.modelNameKey), fallback: MedicalAIConfiguration.doubaoDefaultModelName)
        let endpointURLString = Self.defaulted(defaults.string(forKey: Self.endpointURLKey), fallback: MedicalAIConfiguration.doubaoResponsesEndpoint)
        let providerKind = MedicalAIConfiguration.providerKind(providerName: providerName, endpointURLString: endpointURLString)
        let keyLookup = Self.lookupAPIKey(for: providerKind)
        configuration = MedicalAIConfiguration(
            providerName: providerName,
            modelName: modelName,
            endpointURLString: endpointURLString,
            hasAPIKey: keyLookup.key != nil
        )
        statusMessage = status
        Self.debugLog("reload \(configuration.sanitizedDebugSummary) keySource=\(keyLookup.sourceDescription)")
    }

    private static func defaulted(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static var unavailableUserMessage: String {
        "医疗智能体暂时无法连接，未发送任何用药数据。请稍后重试。"
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

    private static func syncBestAvailableSecret(into defaults: UserDefaults) -> String {
        if let REDACTED_TOKEN = injectedSecret(named: injectedArkAPIKeyEnvironmentName)
            ?? bundledSecret(named: injectedArkAPIKeyEnvironmentName) {
            let status = writeKeychainValue(
                REDACTED_TOKEN,
                service: keychainService,
                account: keychainAccount(for: .doubao)
            )
            defaults.set(MedicalAIConfiguration.doubaoProviderName, forKey: providerNameKey)
            defaults.set(MedicalAIConfiguration.doubaoDefaultModelName, forKey: modelNameKey)
            defaults.set(MedicalAIConfiguration.doubaoResponsesEndpoint, forKey: endpointURLKey)
            return "\(injectedArkAPIKeyEnvironmentName) source=\(injectionSourceDescription(for: injectedArkAPIKeyEnvironmentName)) keychainStatus=\(securityStatusDescription(status))"
        }

        if let baichuanAPIKey = injectedSecret(named: injectedAPIKeyEnvironmentName)
            ?? bundledSecret(named: injectedAPIKeyEnvironmentName) {
            let status = writeKeychainValue(
                baichuanAPIKey,
                service: keychainService,
                account: keychainAccount(for: .baichuan)
            )
            defaults.set(MedicalAIConfiguration.baichuanProviderName, forKey: providerNameKey)
            defaults.set(MedicalAIConfiguration.baichuanDefaultModelName, forKey: modelNameKey)
            defaults.set(MedicalAIConfiguration.baichuanChatEndpoint, forKey: endpointURLKey)
            return "\(injectedAPIKeyEnvironmentName) source=\(injectionSourceDescription(for: injectedAPIKeyEnvironmentName)) keychainStatus=\(securityStatusDescription(status))"
        }

        return "none"
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func keychainAccount(for providerKind: MedicalAIProviderKind) -> String {
        switch providerKind {
        case .doubao:
            return doubaoKeychainAccount
        case .baichuan:
            return baichuanKeychainAccount
        }
    }

    private static func secretName(for providerKind: MedicalAIProviderKind) -> String {
        switch providerKind {
        case .doubao:
            return injectedArkAPIKeyEnvironmentName
        case .baichuan:
            return injectedAPIKeyEnvironmentName
        }
    }

    private static func lookupAPIKey(for providerKind: MedicalAIProviderKind) -> (key: String?, sourceDescription: String) {
        let secretName = secretName(for: providerKind)
        if let key = injectedSecret(named: secretName) {
            return (key, "runtime-\(secretName)")
        }
        if let key = bundledSecret(named: secretName) {
            return (key, "bundle-\(secretName)")
        }
        if let key = readKeychainValue(service: keychainService, account: keychainAccount(for: providerKind)) {
            return (key, "keychain-\(providerKind.rawValue)")
        }
        if let key = readKeychainValue(service: keychainService, account: legacyKeychainAccount) {
            return (key, "keychain-legacy")
        }
        return (nil, "none")
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
