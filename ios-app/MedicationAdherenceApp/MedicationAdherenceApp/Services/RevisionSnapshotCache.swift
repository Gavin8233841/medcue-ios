import Foundation

@MainActor
final class RevisionSnapshotCache<Value> {
    private var cached: (revision: String, value: Value)?

    func value(for revision: String, build: () -> Value) -> Value {
        if let cached, cached.revision == revision {
            return cached.value
        }
        let value = build()
        cached = (revision, value)
        return value
    }

    func invalidate() {
        cached = nil
    }
}
