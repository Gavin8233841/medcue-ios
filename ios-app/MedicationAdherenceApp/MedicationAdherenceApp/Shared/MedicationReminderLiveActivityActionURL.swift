import Foundation

enum MedicationReminderLiveActivityAction: String, Codable, CaseIterable {
    case markTaken
    case delay
    case skip
}

struct MedicationReminderLiveActivityActionRequest: Equatable {
    var taskID: UUID
    var action: MedicationReminderLiveActivityAction
}

enum MedicationReminderLiveActivityActionURL {
    private static let scheme = "medicationadherence"
    private static let host = "live-activity-dose-action"
    private static let taskIDQueryName = "taskID"
    private static let actionQueryName = "action"

    static func url(for taskID: UUID, action: MedicationReminderLiveActivityAction) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: taskIDQueryName, value: taskID.uuidString),
            URLQueryItem(name: actionQueryName, value: action.rawValue)
        ]
        return components.url ?? URL(string: "\(scheme)://\(host)")!
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
        return MedicationReminderLiveActivityActionRequest(taskID: taskID, action: action)
    }
}
