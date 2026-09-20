import MedicationAdherenceCore
import Foundation
import SwiftData
import SwiftUI

struct RisksView: View {
    @Environment(\.activeAppTab) private var activeAppTab
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    private let grouper = RiskReviewGrouper()
    @State private var riskSnapshot = RiskDisplaySnapshot.empty
    @State private var lastSnapshotRefreshToken = ""
    @State private var lastSnapshotRefreshAt = Date(timeIntervalSinceReferenceDate: 0)
    @State private var searchText = ""

    private var isActiveTab: Bool {
        activeAppTab == nil || activeAppTab == .medications
    }

    private var refreshToken: String {
        RiskDisplaySnapshot.refreshID(riskCards: riskCards, medications: medications)
    }

    private var refreshTaskID: String {
        "\(isActiveTab ? "active" : "inactive")|\(refreshToken)"
    }

    private var shouldPrepareSnapshot: Bool {
        isActiveTab || riskSnapshot.isPlaceholder
    }

    private var searchQuery: [String] {
        SearchTextNormalizer.tokenize(searchText)
    }

    private var medicationsByID: [UUID: StoredMedication] {
        Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
    }

    private func filteredCards(_ cards: [StoredRiskCard]) -> [StoredRiskCard] {
        guard !searchQuery.isEmpty else {
            return cards
        }
        let medicationLookup = medicationsByID
        return cards.filter { card in
            let medication = medicationLookup[card.medicationID]
            return RiskSearchIndex(
                card: card,
                medicationName: riskSnapshot.medicationName(for: card),
                medicationGenericName: medication?.genericName ?? ""
            ).matches(query: searchQuery)
        }
    }

    private func filteredSections(_ sections: [MedicationRiskSection]) -> [MedicationRiskSection] {
        guard !searchQuery.isEmpty else {
            return sections
        }
        return sections.compactMap { section in
            let matchingCards = filteredCards(section.cards)
            guard !matchingCards.isEmpty else {
                return nil
            }
            return MedicationRiskSection(
                medicationID: section.medicationID,
                medicationName: section.medicationName,
                visual: section.visual,
                cards: matchingCards
            )
        }
    }

    var body: some View {
        let snapshot = riskSnapshot
        List {
            let filteredActive = filteredSections(snapshot.medicationRiskSections)
            let filteredArchived = filteredSections(snapshot.archivedMedicationRiskSections)
            Section("按药品查看") {
                if snapshot.medicationRiskSections.isEmpty {
                    RiskEmptyStateView(hasMedications: !medications.isEmpty)
                } else if filteredActive.isEmpty {
                    if !searchQuery.isEmpty && filteredArchived.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else if !searchQuery.isEmpty {
                        Text("当前活动风险中没有匹配结果。")
                            .foregroundStyle(.secondary)
                    } else {
                        RiskEmptyStateView(hasMedications: !medications.isEmpty)
                    }
                } else {
                    ForEach(filteredActive) { section in
                        MedicationRiskDisclosureRow(section: section)
                    }
                }
            }

            Section("分类总览") {
                ForEach(RiskReviewGroup.allCases, id: \.rawValue) { group in
                    let groupedCards = filteredCards(snapshot.cardsByGroup[group, default: []])
                    NavigationLink {
                        RiskGroupDetailView(
                            group: group,
                            cards: groupedCards,
                            medicationName: snapshot.medicationName(for:)
                        )
                    } label: {
                        RiskGroupSummaryCard(
                            group: group,
                            count: groupedCards.count,
                            priorityCount: groupedCards.filter(\.requiresProfessionalReview).count
                        )
                    }
                }
            }

            if !filteredArchived.isEmpty {
                Section("已复核归档") {
                    ForEach(filteredArchived) { section in
                        MedicationRiskDisclosureRow(section: section)
                    }
                }
            }

            Section("来源与边界") {
                Text("风险提示来自说明书、药品来源、用户确认的导入信息和本地复核规则。以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断，也不会诊断、处方或自动调整用药。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("风险复核")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索药品、警示或来源"
        )
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            restoreRiskSnapshotFromCacheIfAvailable()
        }
        .task(id: refreshTaskID) {
            guard shouldPrepareSnapshot else {
                return
            }
            let delay: Duration = isActiveTab
                ? .milliseconds(riskSnapshot.isPlaceholder ? 40 : 120)
                : .milliseconds(160)
            await refreshRiskSnapshot(token: refreshToken, after: delay)
        }
    }

    @MainActor
    private func refreshRiskSnapshot(token: String, after delay: Duration) async {
        if restoreRiskSnapshotFromCacheIfAvailable(for: token),
           !riskSnapshot.isPlaceholder,
           isActiveTab {
            return
        }
        if lastSnapshotRefreshToken == token,
           !riskSnapshot.isPlaceholder,
           Date().timeIntervalSince(lastSnapshotRefreshAt) < 15 {
            return
        }
        let riskCards = riskCards
        let medications = medications
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else {
            return
        }
        riskSnapshot = RiskDisplaySnapshot(
            riskCards: riskCards,
            medications: medications,
            grouper: grouper
        )
        lastSnapshotRefreshToken = token
        lastSnapshotRefreshAt = Date()
        RiskDisplaySnapshotCache.store(snapshot: riskSnapshot, token: token)
    }

    @MainActor
    @discardableResult
    private func restoreRiskSnapshotFromCacheIfAvailable(for token: String? = nil) -> Bool {
        let lookupToken = token ?? refreshToken
        guard let cachedSnapshot = RiskDisplaySnapshotCache.snapshot(for: lookupToken) else {
            return false
        }
        riskSnapshot = cachedSnapshot
        lastSnapshotRefreshToken = lookupToken
        lastSnapshotRefreshAt = Date()
        return true
    }
}
