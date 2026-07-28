import Foundation
import SwiftData
import SwiftUI

@MainActor
enum MedicationListSnapshotCache {
    struct Entry {
        let snapshot: MedicationListSnapshot
    }

    private static var token = ""
    private static var storedAt = Date(timeIntervalSinceReferenceDate: 0)
    private static var entry = Entry(snapshot: .empty)
    private static let timeToLive: TimeInterval = 300

    static func store(snapshot: MedicationListSnapshot, token: String) {
        self.token = token
        self.entry = Entry(snapshot: snapshot)
        storedAt = Date()
    }

    static func entry(for token: String) -> Entry? {
        guard self.token == token,
              !entry.snapshot.isPlaceholder,
              Date().timeIntervalSince(storedAt) <= timeToLive
        else {
            return nil
        }
        return entry
    }
}

struct MedicationDetailRoute: Hashable {
    let medicationID: UUID
}

struct MedicationDetailResolverView: View {
    let medicationID: UUID
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    var body: some View {
        if let medication = medications.first(where: { $0.id == medicationID }) {
            MedicationDetailView(medication: medication)
        } else {
            List {
                Text("没有找到这项药品，可能已被归档或删除。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("药品详情")
        }
    }
}
