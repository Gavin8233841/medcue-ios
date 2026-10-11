import Testing
@testable import MedicationAdherenceCore

@Test func doseActionLabelsDistinguishTwoMedicationsWithoutAdjacentHeadings() {
    let first = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "08:00")
    let second = DoseActionAccessibilityContext(medicationName: "药品乙", scheduledTime: "08:00")
    #expect(first.label(for: "已服用") == "已服用，药品甲，计划时间08:00")
    #expect(second.label(for: "已服用") == "已服用，药品乙，计划时间08:00")
    #expect(first.label(for: "已服用") != second.label(for: "已服用"))
}

@Test func doseActionLabelsDistinguishDifferentScheduledTimesForOneMedication() {
    let morning = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "08:00")
    let evening = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "20:00")
    #expect(morning.label(for: "稍后") == "稍后，药品甲，计划时间08:00")
    #expect(evening.label(for: "稍后") == "稍后，药品甲，计划时间20:00")
    #expect(morning.label(for: "稍后") != evening.label(for: "稍后"))
}

@Test func doseActionLabelsIdentifyUnknownAndBlankNamesExplicitly() {
    let missing = DoseActionAccessibilityContext(medicationName: nil, scheduledTime: "08:00")
    let blank = DoseActionAccessibilityContext(medicationName: " \n\t", scheduledTime: "08:00")
    #expect(missing.label(for: "忽略") == "忽略，未知药品，计划时间08:00")
    #expect(blank.label(for: "忽略") == "忽略，未知药品，计划时间08:00")
}

@Test func doseActionLabelsDoNotInventMissingScheduleOrUndoTarget() {
    let missing = DoseActionAccessibilityContext(medicationName: nil, scheduledTime: nil)
    let blank = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: " \n")
    #expect(missing.label(for: "撤销") == "撤销，未知药品，计划时间待核对")
    #expect(blank.label(for: "确认") == "确认，药品甲，计划时间待核对")
}

@Test func doseActionLabelsPreserveIdentityForConfirmCancelAndHandledActions() {
    let context = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "08:00")
    #expect(context.label(for: "确认") == "确认，药品甲，计划时间08:00")
    #expect(context.label(for: "取消") == "取消，药品甲，计划时间08:00")
    #expect(context.label(for: "撤销") == "撤销，药品甲，计划时间08:00")
    #expect(context.label(for: "归档记录") == "归档记录，药品甲，计划时间08:00")
    #expect(context.label(for: "恢复记录") == "恢复记录，药品甲，计划时间08:00")
}

@Test func doseActionLabelsKeepRTLMedicationTextAndCompactWhitespace() {
    let context = DoseActionAccessibilityContext(medicationName: "  دواء   ألف\n", scheduledTime: " 08:00 ")
    #expect(context.label(for: "撤销") == "撤销，دواء ألف，计划时间08:00")
}

@Test func doseActionLabelsDistinguishEqualClockTimesOnDifferentDates() {
    let today = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "2026年10月10日 08:00")
    let tomorrow = DoseActionAccessibilityContext(medicationName: "药品甲", scheduledTime: "2026年10月11日 08:00")
    #expect(today.label(for: "撤销") == "撤销，药品甲，计划时间2026年10月10日 08:00")
    #expect(tomorrow.label(for: "撤销") == "撤销，药品甲，计划时间2026年10月11日 08:00")
    #expect(today.label(for: "撤销") != tomorrow.label(for: "撤销"))
}
