import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct DoseUndoBannerAccessibilityTests {
    @Test @MainActor
    func bannerKeepsOriginalIdentityAfterCurrentTaskChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let originalDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 10, hour: 8, minute: 0
        )))
        let nextDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 11, hour: 8, minute: 0
        )))
        let originalMedication = StoredMedication(displayName: "药品甲", kind: .prescription, inputSource: .manual)
        let nextMedication = StoredMedication(displayName: "药品乙", kind: .prescription, inputSource: .manual)
        let originalTask = StoredDoseTask(
            medicationID: originalMedication.id, dueAt: originalDate, doseValue: 1, doseUnit: "片"
        )
        var currentTask = originalTask
        var currentMedication = originalMedication
        let rollbackToken = DoseReopenRollbackToken(
            primaryTaskID: originalTask.id, taskStates: [], reactivatedActionLogIDs: [], closedActionLogIDs: []
        )
        let banner = DoseUndoBanner(
            taskID: currentTask.id,
            medicationName: userFacingMedicationName(for: currentMedication),
            accessibilityContext: todayDoseAccessibilityContext(task: currentTask, medication: currentMedication),
            rollbackToken: rollbackToken
        )

        currentTask = StoredDoseTask(
            medicationID: nextMedication.id, dueAt: nextDate, doseValue: 1, doseUnit: "片"
        )
        currentMedication = nextMedication
        #expect(todayDoseAccessibilityContext(task: currentTask, medication: currentMedication).label(for: "撤回")
            == "撤回，药品乙，计划时间2026年10月11日 08:00")
        #expect(banner.accessibilityContext.label(for: "撤回") == "撤回，药品甲，计划时间2026年10月10日 08:00")

        // Same drug, next day, same clock time must also leave the old banner intact.
        currentTask = StoredDoseTask(
            medicationID: originalMedication.id, dueAt: nextDate, doseValue: 1, doseUnit: "片"
        )
        currentMedication = originalMedication
        #expect(todayDoseAccessibilityContext(task: currentTask, medication: currentMedication).label(for: "撤回")
            == "撤回，药品甲，计划时间2026年10月11日 08:00")
        originalTask.dueAt = nextDate
        originalMedication.displayName = "更名后的药品"
        #expect(banner.accessibilityContext.label(for: "撤回") == "撤回，药品甲，计划时间2026年10月10日 08:00")
        #expect(banner.accessibilityContext.label(for: "已恢复到待处理，撤回")
            == "已恢复到待处理，撤回，药品甲，计划时间2026年10月10日 08:00")
        #expect(banner.taskID == originalTask.id)
        #expect(banner.rollbackToken == rollbackToken)
    }
}
