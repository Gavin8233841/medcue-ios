import Testing
@testable import MedicationAdherenceApp

#if DEBUG
// The diagnostic itself is Debug-only; Demo does not expose this smoke entry.
struct ReminderLiveActivitySmokeDiagnosticTests {
    @Test
    func setupLineContainsOnlyFixedEventName() {
        #expect(
            ReminderLiveActivitySmokeDiagnostic.setupCompleteLine
                == "[ReminderLiveActivity-Smoke] setup-complete"
        )
    }

    @Test
    func stateLineContainsOnlyAuthorizationAndBoundedCounts() {
        let line = ReminderLiveActivitySmokeDiagnostic.stateLine(
            notificationAuthorized: true,
            pendingBaseNotificationCount: .max,
            activeLiveActivityCount: -1
        )

        #expect(
            line
                == "[ReminderLiveActivity-Smoke] notificationAuthorized=true pendingBaseNotifications=999 activeLiveActivities=0"
        )
    }
}
#endif
