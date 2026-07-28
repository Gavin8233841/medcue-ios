import Foundation
import SwiftData

enum TodayArchiveVisibilityAction: Equatable, Sendable {
    case archive(taskID: UUID, occurredAt: Date)
    case restore(taskID: UUID, occurredAt: Date)

    var taskID: UUID {
        switch self {
        case let .archive(taskID, _), let .restore(taskID, _):
            return taskID
        }
    }

    var occurredAt: Date {
        switch self {
        case let .archive(_, occurredAt), let .restore(_, occurredAt):
            return occurredAt
        }
    }

    var operation: StaticString {
        switch self {
        case .archive:
            return "today-archive-record"
        case .restore:
            return "today-restore-archived-record"
        }
    }
}

enum TodayArchiveVisibilityRejection: Equatable {
    case taskNotFound
    case readFailed
    case alreadyArchived
    case notArchived
}

enum TodayArchiveVisibilityCommandOutcome: Equatable {
    case committed(taskID: UUID)
    case rejected(TodayArchiveVisibilityRejection)
    case saveFailed
}

@MainActor
struct TodayArchiveVisibilityCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private static let archiveMarker = "用户已归档"
    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func perform(_ action: TodayArchiveVisibilityAction) -> TodayArchiveVisibilityCommandOutcome {
        let taskID = action.taskID
        var descriptor = FetchDescriptor<StoredDoseTask>(
            predicate: #Predicate<StoredDoseTask> { task in
                task.id == taskID
            }
        )
        descriptor.fetchLimit = 1

        let task: StoredDoseTask
        do {
            guard let storedTask = try modelContext.fetch(descriptor).first else {
                return .rejected(.taskNotFound)
            }
            task = storedTask
        } catch {
            return .rejected(.readFailed)
        }

        let wasArchived = task.reason.contains(Self.archiveMarker)
        switch action {
        case .archive where wasArchived:
            return .rejected(.alreadyArchived)
        case .restore where !wasArchived:
            return .rejected(.notArchived)
        default:
            break
        }

        let previousReason = task.reason
        let log: StoredDoseActionLog
        switch action {
        case .archive:
            log = StoredDoseActionLog(
                taskID: task.id,
                action: .archiveToday,
                previousStatus: task.status,
                previousDueAt: task.dueAt,
                previousRecordedAt: task.recordedAt,
                previousReason: previousReason,
                newStatus: task.status,
                occurredAt: action.occurredAt,
                undoExpiresAt: action.occurredAt,
                note: "用户将今日记录归档隐藏"
            )
            task.reason = [previousReason, Self.archiveMarker]
                .filter { !$0.isEmpty }
                .joined(separator: "；")
        case .restore:
            log = StoredDoseActionLog(
                taskID: task.id,
                action: .restoreArchive,
                previousStatus: task.status,
                previousDueAt: task.dueAt,
                previousRecordedAt: task.recordedAt,
                previousReason: previousReason,
                newStatus: task.status,
                occurredAt: action.occurredAt,
                undoExpiresAt: action.occurredAt,
                note: "用户恢复今日归档记录"
            )
            task.reason = previousReason
                .split(separator: "；")
                .map(String.init)
                .filter { $0 != Self.archiveMarker }
                .joined(separator: "；")
        }
        modelContext.insert(log)

        do {
            try saveOperation(modelContext)
            return .committed(taskID: task.id)
        } catch {
            task.reason = previousReason
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: action.operation)
            return .saveFailed
        }
    }
}
