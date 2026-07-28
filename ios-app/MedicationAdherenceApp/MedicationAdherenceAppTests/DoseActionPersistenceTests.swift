import Foundation
import MedicationAdherenceCore
import SwiftData
import Testing
@testable import MedicationAdherenceApp

@Suite(.serialized)
struct DoseActionPersistenceTests {
    @Test @MainActor
    func transitionPlannerFreezesSharedDoseActionSemantics() {
        let plannedDueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondaryDueAt = plannedDueAt.addingTimeInterval(20)
        let occurredAt = plannedDueAt.addingTimeInterval(60)
        let primaryLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000811")!
        let medicationID = UUID()
        let primaryTask = StoredDoseTask(
            medicationID: medicationID,
            dueAt: plannedDueAt,
            doseValue: 1,
            doseUnit: "片"
        )
        let secondaryTask = StoredDoseTask(
            medicationID: medicationID,
            dueAt: secondaryDueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .delayed
        )
        let specifications: [(DoseActionMutation, DoseActionKind, StoredDoseStatus)] = [
            (.markTaken, .markTaken, .taken),
            (.delay, .delay, .delayed),
            (.skip, .skip, .skipped)
        ]

        for (mutation, expectedAction, expectedStatus) in specifications {
            let transitions = DoseActionTransitionPlanner().makeTransitions(
                mutation: mutation,
                taskGroup: [primaryTask, secondaryTask],
                primaryTask: primaryTask,
                occurredAt: occurredAt,
                primaryReason: "主动作",
                mergedReason: "合并动作",
                primaryActionLogID: primaryLogID
            )

            #expect(transitions.count == 2)
            #expect(transitions.allSatisfy { $0.action == expectedAction })
            #expect(transitions.allSatisfy { $0.newStatus == expectedStatus })
            #expect(transitions.allSatisfy { $0.newRecordedAt == occurredAt })
            #expect(transitions.allSatisfy { $0.occurredAt == occurredAt })
            #expect(transitions.allSatisfy { $0.undoExpiresAt == occurredAt.addingTimeInterval(10 * 60) })
            #expect(transitions.first { $0.task.id == primaryTask.id }?.newReason == "主动作")
            #expect(transitions.first { $0.task.id == secondaryTask.id }?.newReason == "合并动作")
            #expect(transitions.first { $0.task.id == primaryTask.id }?.actionLogID == primaryLogID)
            #expect(transitions.first { $0.task.id == secondaryTask.id }?.actionLogID != primaryLogID)

            let expectedPrimaryDueAt = mutation == .delay
                ? DoseDelayPolicy.delayedDueAtFromPlannedTime(plannedDueAt)
                : plannedDueAt
            let expectedSecondaryDueAt = mutation == .delay
                ? DoseDelayPolicy.delayedDueAtFromPlannedTime(plannedDueAt)
                : secondaryDueAt
            #expect(transitions.first { $0.task.id == primaryTask.id }?.newDueAt == expectedPrimaryDueAt)
            #expect(transitions.first { $0.task.id == secondaryTask.id }?.newDueAt == expectedSecondaryDueAt)
        }
    }

    @Test @MainActor
    func successfulCommitPersistsDoseStateAndActionLogTogether() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let originalDueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let occurredAt = originalDueAt.addingTimeInterval(60)
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: originalDueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .pending,
            reason: "原始状态"
        )
        context.insert(task)
        try context.save()

        let logs = try DoseActionPersistence().commit(
            [
                DoseActionTransition(
                    task: task,
                    action: .markTaken,
                    newStatus: .taken,
                    newDueAt: originalDueAt,
                    newRecordedAt: occurredAt,
                    newReason: "用户标记已服用",
                    occurredAt: occurredAt,
                    undoExpiresAt: occurredAt.addingTimeInterval(10 * 60)
                )
            ],
            in: context
        )

        #expect(logs.count == 1)
        let verificationContext = ModelContext(container)
        let persistedTask = try #require(verificationContext.fetch(FetchDescriptor<StoredDoseTask>()).first)
        let persistedLog = try #require(verificationContext.fetch(FetchDescriptor<StoredDoseActionLog>()).first)
        #expect(persistedTask.status == .taken)
        #expect(persistedTask.recordedAt == occurredAt)
        #expect(persistedTask.reason == "用户标记已服用")
        #expect(persistedLog.taskID == task.id)
        #expect(persistedLog.actionRaw == DoseActionKind.markTaken.rawValue)
        #expect(persistedLog.newStatusRaw == StoredDoseStatus.taken.rawValue)
    }

    @Test @MainActor
    func failedCommitRestoresDoseStateAndDoesNotLeaveAnActionLog() throws {
        let container = try MedicationAdherenceModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let originalDueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let task = StoredDoseTask(
            medicationID: UUID(),
            dueAt: originalDueAt,
            doseValue: 1,
            doseUnit: "片",
            status: .pending,
            reason: "原始状态"
        )
        context.insert(task)
        try context.save()

        let occurredAt = originalDueAt.addingTimeInterval(60)
        let transition = DoseActionTransition(
            task: task,
            action: .markTaken,
            newStatus: .taken,
            newDueAt: originalDueAt,
            newRecordedAt: occurredAt,
            newReason: "用户标记已服用",
            occurredAt: occurredAt,
            undoExpiresAt: occurredAt.addingTimeInterval(10 * 60)
        )
        let persistence = DoseActionPersistence { _ in
            throw SyntheticDoseSaveError.unavailable
        }

        do {
            try persistence.commit([transition], in: context)
            Issue.record("Expected the dose action save to fail")
        } catch let error as DoseActionPersistenceError {
            #expect(error == .saveFailed)
            #expect(error.userMessage == "用药记录未能保存，请重试。")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(task.status == .pending)
        #expect(task.dueAt == originalDueAt)
        #expect(task.recordedAt == nil)
        #expect(task.reason == "原始状态")
        #expect(try context.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
        #expect(!context.hasChanges)

        let verificationContext = ModelContext(container)
        let persistedTask = try #require(verificationContext.fetch(FetchDescriptor<StoredDoseTask>()).first)
        #expect(persistedTask.status == .pending)
        #expect(persistedTask.dueAt == originalDueAt)
        #expect(persistedTask.recordedAt == nil)
        #expect(persistedTask.reason == "原始状态")
        #expect(try verificationContext.fetch(FetchDescriptor<StoredDoseActionLog>()).isEmpty)
    }
}

private enum SyntheticDoseSaveError: Error {
    case unavailable
}
