import Foundation
import Testing
@testable import MedicationAdherenceApp

struct PlatformBehaviorTests {
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
}
