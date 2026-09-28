import Foundation
import MedicationAdherenceCore
import Testing
import UserNotifications
@testable import MedicationAdherenceApp

struct PlatformBehaviorTests {
    @Test @MainActor
    func systemReminderActionsRequireUnlockBeforeAnyDoseMutation() {
        let actions = MedicationNotificationDelegate.reminderCategory().actions

        #expect(actions.count == 3)
        for action in actions {
            #expect(action.options.contains(.authenticationRequired))
        }
    }

    @Test
    func liveActivityAttributesNeverContainMedicationDetails() {
        let taskID = UUID()
        let attributes = MedicationSystemSurfacePrivacyPolicy.activityAttributes(taskID: taskID)

        #expect(attributes.taskID == taskID)
        #expect(attributes.medicationName == MedicationSystemSurfacePrivacyPolicy.reminderTitle)
        #expect(attributes.doseText.isEmpty)
    }

    @Test
    func notificationPolicyRejectsDeniedAuthorization() {
        let disposition = MedicationNotificationPolicy.default.authorizationDisposition(
            status: .denied,
            hasPresentationSurface: false,
            hasSound: false
        )

        #expect(disposition == .denied)
        #expect(MedicationNotificationPolicy.default.unavailableMessage(for: disposition) != nil)
    }

    @Test
    func notificationPolicyDeduplicatesCandidatesBeforeApplyingRequestBudget() {
        let firstID = UUID()
        let secondID = UUID()
        let first = MedicationReminderRequestCandidate(
            taskID: firstID,
            dueAt: Date(timeIntervalSince1970: 2_000),
            wantsAlarm: false,
            wantsEscalation: false
        )
        let second = MedicationReminderRequestCandidate(
            taskID: secondID,
            dueAt: Date(timeIntervalSince1970: 3_000),
            wantsAlarm: false,
            wantsEscalation: false
        )
        let policy = MedicationNotificationPolicy(maximumScheduledRequests: 2)
        let plan = policy.requestPlan(
            candidates: [first, first, second],
            occupiedRequestCount: 0,
            notificationAvailable: true,
            alarmAvailable: false
        )

        #expect(plan.assignments.map(\.taskID) == [firstID, secondID])
        #expect(plan.deferredTaskIDs.isEmpty)
    }

    @Test
    func notificationTriggerComponentsRetainSchedulingTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let components = MedicationNotificationPolicy.default.triggerDateComponents(
            for: date,
            calendar: calendar
        )

        #expect(components.timeZone == calendar.timeZone)
        #expect(calendar.date(from: components) == calendar.dateInterval(of: .minute, for: date)?.start)
    }

    @Test
    func watchDeliveryQueuesLatestSnapshotOnceWhileOfflineAndSendsOnReconnect() {
        var state = MedicationWatchDeliveryState()
        let first = Data([0x01])
        let second = Data([0x02])

        state.record(first)
        #expect(state.actions(isActivated: true, isReachable: false) == [.updateApplicationContext(first), .transferUserInfo(first)])
        #expect(state.actions(isActivated: true, isReachable: false) == [.updateApplicationContext(first)])

        state.record(second)
        #expect(state.actions(isActivated: true, isReachable: false) == [.updateApplicationContext(second), .transferUserInfo(second)])
        #expect(state.actions(isActivated: true, isReachable: true) == [.updateApplicationContext(second), .sendMessage(second)])
    }

    @Test
    func watchAndWidgetPresentationDistinguishesFirstSyncStaleEmptyAndPrivateContent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = MedicationWatchDoseItem(
            id: UUID(),
            medicationName: "测试药品",
            doseText: "1 片",
            dueAt: now.addingTimeInterval(600),
            status: .pending
        )

        #expect(MedicationWatchSnapshot.empty.presentationState(now: now, calendar: calendar) == .awaitingFirstSync)
        #expect(MedicationWatchSnapshot(generatedAt: now.addingTimeInterval(-86_400), items: [item], privacyMode: false).presentationState(now: now, calendar: calendar) == .stale)
        #expect(MedicationWatchSnapshot(generatedAt: now, items: [], privacyMode: false).presentationState(now: now, calendar: calendar) == .empty)
        #expect(MedicationWatchSnapshot(generatedAt: now, items: [item], privacyMode: true).presentationState(now: now, calendar: calendar) == .content(isPrivate: true))
    }

    @Test
    func watchDosePayloadRendersLocallyAndKeepsLegacySnapshotReadable() throws {
        let item = MedicationWatchDoseItem(
            id: UUID(),
            medicationName: "合成药品",
            doseText: "1.5 片",
            doseValue: 1.5,
            doseUnitCode: "tablet",
            dueAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .pending
        )
        let snapshot = MedicationWatchSnapshot(generatedAt: item.dueAt, items: [item], privacyMode: false)
        let decoded = try JSONDecoder().decode(MedicationWatchSnapshot.self, from: JSONEncoder().encode(snapshot))
        let decodedItem = try #require(decoded.items.first)
        #expect(decodedItem.doseValue == 1.5)
        #expect(decodedItem.doseUnitCode == "tablet")
        #expect(decodedItem.displayDoseText(locale: Locale(identifier: "zh_Hans_CN")) == "1.5 片")
        #expect(decodedItem.displayDoseText(locale: Locale(identifier: "en_US")) == "1.5 tablets")
        #expect(decodedItem.status == .pending)
        #expect(decoded.privacyMode == false)

        let legacyJSON = """
        {"generatedAt":0,"items":[{"id":"\(item.id.uuidString)","medicationName":"合成药品","doseText":"旧记录 1 片","dueAt":0,"status":"pending"}],"privacyMode":true}
        """.data(using: .utf8)!
        let legacySnapshot = try JSONDecoder().decode(MedicationWatchSnapshot.self, from: legacyJSON)
        let legacyItem = try #require(legacySnapshot.items.first)
        #expect(legacySnapshot.privacyMode)
        #expect(legacyItem.doseValue == nil)
        #expect(legacyItem.doseUnitCode == nil)
        #expect(legacyItem.displayDoseText(locale: Locale(identifier: "en_US")) == "旧记录 1 片")

        var unknownUnit = item
        unknownUnit.doseUnitCode = "unknown"
        #expect(unknownUnit.displayDoseText(locale: Locale(identifier: "en_US")) == "1.5 片")
    }

    @Test
    func watchDoseUnitCodesRenderEverySupportedUnitWithoutChangingStoredText() {
        let units: [(DoseUnitKind, String, String)] = [
            (.tablet, "片", "tablets"),
            (.capsule, "粒", "capsules"),
            (.bag, "袋", "sachets"),
            (.drop, "滴", "drops"),
            (.spray, "喷", "sprays"),
            (.patch, "贴", "patches"),
            (.ampoule, "支", "ampoules"),
            (.pill, "丸", "pills"),
            (.milliliter, "毫升", "mL")
        ]
        for (unit, chinese, english) in units {
            let item = MedicationWatchDoseItem(
                id: UUID(), medicationName: "合成药品", doseText: "legacy",
                doseValue: 2, doseUnitCode: unit.rawValue,
                dueAt: Date(timeIntervalSince1970: 1_800_000_000), status: .pending
            )
            #expect(item.displayDoseText(locale: Locale(identifier: "zh_Hans_CN")) == "2 \(chinese)")
            #expect(item.displayDoseText(locale: Locale(identifier: "en_US")) == "2 \(english)")
            #expect(item.doseText == "legacy")
        }
    }

    @Test @MainActor
    func watchSnapshotPublisherKeepsStoredDoseAndAddsStableUnitCode() throws {
        let medication = StoredMedication(
            displayName: "合成药品",
            kind: .prescription,
            inputSource: .manual
        )
        let task = StoredDoseTask(
            medicationID: medication.id,
            dueAt: Date().addingTimeInterval(600),
            doseValue: 1.5,
            doseUnit: "tablets"
        )
        let snapshot = MedicationWatchSnapshotPublisher().makeSnapshot(
            tasks: [task], medications: [medication], privacyMode: true
        )
        let item = try #require(snapshot.items.first)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.privacyMode)
        #expect(item.doseValue == 1.5)
        #expect(item.doseUnitCode == DoseUnitKind.tablet.rawValue)
        #expect(item.doseText == "1.5 tablets")
        #expect(task.doseValue == 1.5)
        #expect(task.doseUnit == "tablets")
    }
}
