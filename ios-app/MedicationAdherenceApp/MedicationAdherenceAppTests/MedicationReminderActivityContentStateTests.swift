import Foundation
import Testing
@testable import MedicationAdherenceApp

#if canImport(ActivityKit)
struct MedicationReminderActivityContentStateTests {
    typealias ContentState = MedicationReminderActivityAttributes.ContentState

    @Test
    func newActivityCompletionDoesNotDependOnDisplayLanguage() throws {
        let dueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let open = ContentState(
            dueAt: dueAt,
            statusText: "已完成",
            completedAt: nil,
            phase: .open
        )
        let completed = ContentState(
            dueAt: dueAt,
            statusText: "Reminder pending",
            completedAt: dueAt,
            phase: .completed
        )

        #expect(!open.isCompleted)
        #expect(completed.isCompleted)
        let encodedOpen = try JSONEncoder().encode(open)
        let encodedCompleted = try JSONEncoder().encode(completed)
        #expect(String(data: encodedOpen, encoding: .utf8)?.contains(#""phase":"open""#) == true)
        #expect(String(data: encodedCompleted, encoding: .utf8)?.contains(#""phase":"completed""#) == true)
        #expect(try !JSONDecoder().decode(ContentState.self, from: encodedOpen).isCompleted)
        #expect(try JSONDecoder().decode(ContentState.self, from: encodedCompleted).isCompleted)
    }

    @Test
    func legacyActivityWithoutPhaseKeepsItsReadOnlyCompletionMeaning() throws {
        for statusText in ["已处理", "已完成"] {
            let legacyCompleted = Data("""
            {"dueAt":0,"statusText":"\(statusText)","completedAt":null}
            """.utf8)
            let completed = try JSONDecoder().decode(ContentState.self, from: legacyCompleted)
            #expect(completed.phase == nil)
            #expect(completed.isCompleted)
        }

        let legacyOpen = Data(#"{"dueAt":0,"statusText":"该服药了","completedAt":null}"#.utf8)
        let legacyTimestamp = Data(#"{"dueAt":0,"statusText":"Reminder pending","completedAt":1}"#.utf8)
        let open = try JSONDecoder().decode(ContentState.self, from: legacyOpen)
        let timestamped = try JSONDecoder().decode(ContentState.self, from: legacyTimestamp)

        #expect(open.phase == nil)
        #expect(!open.isCompleted)
        #expect(timestamped.phase == nil)
        #expect(timestamped.isCompleted)
        #expect(String(data: try JSONEncoder().encode(open), encoding: .utf8)?.contains("phase") == false)
    }
}
#endif
