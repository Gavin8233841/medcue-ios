import Foundation

enum MedicationReminderLiveActivityAction: String, Codable, CaseIterable {
    case markTaken
    case delay
    case skip
}

struct MedicationReminderLiveActivityActionRequest: Equatable {
    var taskID: UUID
    var action: MedicationReminderLiveActivityAction
    var operationID: UUID?
    var expiresAt: Date?

    init(
        taskID: UUID,
        action: MedicationReminderLiveActivityAction,
        operationID: UUID? = nil,
        expiresAt: Date? = nil
    ) {
        self.taskID = taskID
        self.action = action
        self.operationID = operationID
        self.expiresAt = expiresAt
    }
}

enum MedicationReminderLiveActivityActionURL {
    private static let scheme = "medicationadherence"
    private static let host = "live-activity-dose-action"
    private static let taskIDQueryName = "taskID"
    private static let actionQueryName = "action"
    private static let operationIDQueryName = "operationID"
    private static let expiresAtQueryName = "expiresAt"

    static func url(
        for taskID: UUID,
        action: MedicationReminderLiveActivityAction,
        operationID: UUID? = nil,
        expiresAt: Date? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var queryItems = [
            URLQueryItem(name: taskIDQueryName, value: taskID.uuidString),
            URLQueryItem(name: actionQueryName, value: action.rawValue)
        ]
        if let operationID {
            queryItems.append(URLQueryItem(name: operationIDQueryName, value: operationID.uuidString))
        }
        if let expiresAt {
            queryItems.append(URLQueryItem(name: expiresAtQueryName, value: String(expiresAt.timeIntervalSince1970)))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            preconditionFailure("The bundled Live Activity action URL is invalid")
        }
        return url
    }

    static func request(from url: URL) -> MedicationReminderLiveActivityActionRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme,
              components.host == host
        else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        guard let rawTaskID = queryItems.first(where: { $0.name == taskIDQueryName })?.value,
              let taskID = UUID(uuidString: rawTaskID),
              let rawAction = queryItems.first(where: { $0.name == actionQueryName })?.value,
              let action = MedicationReminderLiveActivityAction(rawValue: rawAction)
        else {
            return nil
        }
        let rawOperationID = queryItems.first(where: { $0.name == operationIDQueryName })?.value
        let rawExpiresAt = queryItems.first(where: { $0.name == expiresAtQueryName })?.value
        if rawOperationID != nil, rawOperationID.flatMap(UUID.init(uuidString:)) == nil {
            return nil
        }
        if rawExpiresAt != nil, rawExpiresAt.flatMap(TimeInterval.init) == nil {
            return nil
        }
        return MedicationReminderLiveActivityActionRequest(
            taskID: taskID,
            action: action,
            operationID: rawOperationID.flatMap(UUID.init(uuidString:)),
            expiresAt: rawExpiresAt.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        )
    }
}
