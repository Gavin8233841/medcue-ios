import Testing
@testable import MedicationAdherenceApp

@MainActor
struct RevisionSnapshotCacheTests {
    @Test
    func sameRevisionReusesTheExistingSnapshot() {
        let cache = RevisionSnapshotCache<Int>()
        var buildCount = 0

        let first = cache.value(for: "one") {
            buildCount += 1
            return buildCount
        }
        let second = cache.value(for: "one") {
            buildCount += 1
            return buildCount
        }

        #expect(first == 1)
        #expect(second == 1)
        #expect(buildCount == 1)
    }

    @Test
    func changedRevisionBuildsExactlyOneReplacementSnapshot() {
        let cache = RevisionSnapshotCache<Int>()
        var buildCount = 0

        _ = cache.value(for: "one") {
            buildCount += 1
            return buildCount
        }
        let replacement = cache.value(for: "two") {
            buildCount += 1
            return buildCount
        }

        #expect(replacement == 2)
        #expect(buildCount == 2)
    }
}
