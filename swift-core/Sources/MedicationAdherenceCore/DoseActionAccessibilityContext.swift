import Foundation

/// Presentation-only identity for an action on one already-selected dose.
/// It neither resolves a task nor authorizes or records an action.
public struct DoseActionAccessibilityContext: Equatable, Sendable {
    public let medicationName: String
    public let scheduledTime: String

    public init(medicationName: String?, scheduledTime: String?) {
        self.medicationName = Self.concise(medicationName) ?? "未知药品"
        self.scheduledTime = Self.concise(scheduledTime) ?? "待核对"
    }

    public func label(for action: String) -> String {
        "\(action)，\(medicationName)，计划时间\(scheduledTime)"
    }

    private static func concise(_ value: String?) -> String? {
        let text = value?.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ") ?? ""
        return text.isEmpty ? nil : text
    }
}
