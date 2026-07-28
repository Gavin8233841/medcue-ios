import Foundation
import SwiftData

struct DoseRecordCorrectionInput: Equatable, Sendable {
    let taskID: UUID
    let status: StoredDoseStatus
    let plannedAt: Date
    let recordedAt: Date
    let note: String
    let confirmedEarlyRecord: Bool
    let occurredAt: Date
}

struct DoseRecordCorrectionCommit: Equatable, Sendable {
    let primaryTaskID: UUID
    let taskIDs: [UUID]
}

enum DoseRecordCorrectionRejection: Equatable {
    case taskNotFound
    case readFailed
}

enum DoseRecordCorrectionCommandOutcome: Equatable {
    case committed(DoseRecordCorrectionCommit)
    case rejected(DoseRecordCorrectionRejection)
    case saveFailed
}

@MainActor
struct DoseRecordCorrectionCommand {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let modelContext: ModelContext
    private let saveOperation: SaveOperation

    init(
        modelContext: ModelContext,
        saveOperation: @escaping SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveOperation = saveOperation
    }

    func perform(_ input: DoseRecordCorrectionInput) -> DoseRecordCorrectionCommandOutcome {
        let taskID = input.taskID
        var primaryDescriptor = FetchDescriptor<StoredDoseTask>(
            predicate: #Predicate<StoredDoseTask> { task in
                task.id == taskID
            }
        )
        primaryDescriptor.fetchLimit = 1

        let primaryTask: StoredDoseTask
        do {
            guard let storedTask = try modelContext.fetch(primaryDescriptor).first else {
                return .rejected(.taskNotFound)
            }
            primaryTask = storedTask
        } catch {
            return .rejected(.readFailed)
        }

        let medicationID = primaryTask.medicationID
        let minuteStart = Date(
            timeIntervalSince1970: floor(primaryTask.dueAt.timeIntervalSince1970 / 60) * 60
        )
        let minuteEnd = minuteStart.addingTimeInterval(60)
        let nearbyTasks: [StoredDoseTask]
        do {
            nearbyTasks = try modelContext.fetch(
                FetchDescriptor<StoredDoseTask>(
                    predicate: #Predicate<StoredDoseTask> { task in
                        task.medicationID == medicationID
                            && task.dueAt >= minuteStart
                            && task.dueAt < minuteEnd
                    }
                )
            )
        } catch {
            return .rejected(.readFailed)
        }

        let matchingTasks = DoseLogicalGroup.group(containing: primaryTask, in: nearbyTasks)
        let group = matchingTasks.isEmpty ? [primaryTask] : matchingTasks
        let snapshots = group.map(DoseRecordCorrectionTaskSnapshot.init)
        let trimmedNote = input.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedReason = DoseCorrectionPolicy.taskReasonForSavedStatus(
            previousStatus: primaryTask.status,
            newStatus: input.status,
            trimmedNote: trimmedNote
        )
        let primaryNote = correctionLogNote(
            userNote: trimmedNote,
            confirmedEarlyRecord: input.confirmedEarlyRecord
        )

        for task in group {
            let logNote = task.id == primaryTask.id
                ? primaryNote
                : groupedCorrectionLogNote(primaryNote: primaryNote)
            modelContext.insert(
                StoredDoseActionLog(
                    taskID: task.id,
                    action: .correct,
                    previousStatus: task.status,
                    previousDueAt: task.dueAt,
                    previousRecordedAt: task.recordedAt,
                    previousReason: task.reason,
                    newStatus: input.status,
                    occurredAt: input.occurredAt,
                    undoExpiresAt: input.occurredAt.addingTimeInterval(10 * 60),
                    note: logNote
                )
            )
            task.status = input.status
            task.dueAt = input.plannedAt
            task.recordedAt = input.status == .pending ? nil : min(input.recordedAt, input.occurredAt)
            task.reason = savedReason
        }

        do {
            try saveOperation(modelContext)
            return .committed(
                DoseRecordCorrectionCommit(
                    primaryTaskID: primaryTask.id,
                    taskIDs: group.map(\.id)
                )
            )
        } catch {
            snapshots.forEach { $0.restore() }
            modelContext.rollback()
            AppPersistenceCommitter.reportFailure(operation: "records-update")
            return .saveFailed
        }
    }

    private func correctionLogNote(userNote: String, confirmedEarlyRecord: Bool) -> String {
        var parts = [userNote].filter { !$0.isEmpty }
        if confirmedEarlyRecord {
            parts.append("用户确认提前服用。")
        }
        return parts.joined(separator: "；")
    }

    private func groupedCorrectionLogNote(primaryNote: String) -> String {
        let mergeNote = "同一剂量重复提醒已随本次记录修正合并。"
        guard !primaryNote.isEmpty else {
            return mergeNote
        }
        return "\(mergeNote)；\(primaryNote)"
    }
}

private struct DoseRecordCorrectionTaskSnapshot {
    let task: StoredDoseTask
    let status: StoredDoseStatus
    let dueAt: Date
    let recordedAt: Date?
    let reason: String

    init(_ task: StoredDoseTask) {
        self.task = task
        status = task.status
        dueAt = task.dueAt
        recordedAt = task.recordedAt
        reason = task.reason
    }

    func restore() {
        task.status = status
        task.dueAt = dueAt
        task.recordedAt = recordedAt
        task.reason = reason
    }
}
