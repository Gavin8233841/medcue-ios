import MedicationAdherenceCore
import Foundation
import SwiftData
import SwiftUI

struct RisksView: View {
    @Environment(\.activeAppTab) private var activeAppTab
    @Environment(\.isBackgroundTabPrewarm) private var isBackgroundTabPrewarm
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    private let grouper = RiskReviewGrouper()
    @State private var riskSnapshot = RiskDisplaySnapshot.empty
    @State private var lastSnapshotRefreshToken = ""
    @State private var lastSnapshotRefreshAt = Date(timeIntervalSinceReferenceDate: 0)

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

    var body: some View {
        let snapshot = riskSnapshot
        List {
            Section("按药品查看") {
                if snapshot.medicationRiskSections.isEmpty {
                    RiskEmptyStateView(hasMedications: !medications.isEmpty)
                } else {
                    ForEach(snapshot.medicationRiskSections) { section in
                        MedicationRiskDisclosureRow(section: section)
                    }
                }
            }

            Section("分类总览") {
                ForEach(RiskReviewGroup.allCases, id: \.rawValue) { group in
                    let groupedCards = snapshot.cardsByGroup[group, default: []]
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

            if !snapshot.archivedMedicationRiskSections.isEmpty {
                Section("已复核归档") {
                    ForEach(snapshot.archivedMedicationRiskSections) { section in
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
           isActiveTab,
           !isBackgroundTabPrewarm {
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

@MainActor
private enum RiskDisplaySnapshotCache {
    private static var token = ""
    private static var storedAt = Date(timeIntervalSinceReferenceDate: 0)
    private static var snapshot = RiskDisplaySnapshot.empty
    private static let timeToLive: TimeInterval = 300

    static func store(snapshot: RiskDisplaySnapshot, token: String) {
        self.token = token
        self.snapshot = snapshot
        storedAt = Date()
    }

    static func snapshot(for token: String) -> RiskDisplaySnapshot? {
        guard self.token == token,
              !snapshot.isPlaceholder,
              Date().timeIntervalSince(storedAt) <= timeToLive
        else {
            return nil
        }
        return snapshot
    }
}

private struct RiskDisplaySnapshot {
    static let empty = RiskDisplaySnapshot(
        medicationRiskSections: [],
        archivedMedicationRiskSections: [],
        cardsByGroup: [:],
        medicationNamesByID: [:],
        isPlaceholder: true
    )

    let medicationRiskSections: [MedicationRiskSection]
    let archivedMedicationRiskSections: [MedicationRiskSection]
    let cardsByGroup: [RiskReviewGroup: [StoredRiskCard]]
    let medicationNamesByID: [UUID: String]
    let isPlaceholder: Bool

    init(
        riskCards: [StoredRiskCard],
        medications: [StoredMedication],
        grouper: RiskReviewGrouper
    ) {
        let medicationNamesByID = Dictionary(
            uniqueKeysWithValues: medications.map { ($0.id, userFacingMedicationName(for: $0)) }
        )
        let medicationsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let activeRiskCards = riskCards.filter(\.isActive)
        let deduplicatedActiveRiskCards = RiskMedicationDisplayBuilder.deduplicatedCards(from: activeRiskCards)
        var cardsByGroup: [RiskReviewGroup: [StoredRiskCard]] = [:]
        for group in RiskReviewGroup.allCases {
            cardsByGroup[group] = deduplicatedActiveRiskCards.filter { grouper.mappedGroup(for: $0.coreRiskCard) == group }
        }
        self.medicationRiskSections = RiskMedicationDisplayBuilder.sections(
            from: activeRiskCards,
            medicationName: { medicationNamesByID[$0.medicationID] ?? "未知药品" },
            medicationVisual: { medicationRiskVisual(for: medicationsByID[$0.medicationID], cards: $0.cards) }
        )
        self.archivedMedicationRiskSections = RiskMedicationDisplayBuilder.sections(
            from: riskCards.filter { $0.isArchived || $0.isResolved },
            medicationName: { medicationNamesByID[$0.medicationID] ?? "未知药品" },
            medicationVisual: { medicationRiskVisual(for: medicationsByID[$0.medicationID], cards: $0.cards) }
        )
        self.cardsByGroup = cardsByGroup
        self.medicationNamesByID = medicationNamesByID
        self.isPlaceholder = false
    }

    private init(
        medicationRiskSections: [MedicationRiskSection],
        archivedMedicationRiskSections: [MedicationRiskSection],
        cardsByGroup: [RiskReviewGroup: [StoredRiskCard]],
        medicationNamesByID: [UUID: String],
        isPlaceholder: Bool
    ) {
        self.medicationRiskSections = medicationRiskSections
        self.archivedMedicationRiskSections = archivedMedicationRiskSections
        self.cardsByGroup = cardsByGroup
        self.medicationNamesByID = medicationNamesByID
        self.isPlaceholder = isPlaceholder
    }

    static func refreshID(riskCards: [StoredRiskCard], medications: [StoredMedication]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(2)
        parts.append(String(stableRiskCardSignature(riskCards)))
        parts.append(String(stableMedicationSignature(medications)))
        return parts.joined(separator: "|")
    }

    func medicationName(for card: StoredRiskCard) -> String {
        medicationNamesByID[card.medicationID] ?? "未知药品"
    }
}

private struct MedicationRiskSection: Identifiable {
    let medicationID: UUID
    let medicationName: String
    let visual: RiskVisualStyle
    let cards: [StoredRiskCard]

    var id: UUID { medicationID }

    var activeCards: [StoredRiskCard] {
        cards.filter(\.isActive)
    }

    var archivedCards: [StoredRiskCard] {
        cards.filter { $0.isArchived || $0.isResolved }
    }

    private var summaryCards: [StoredRiskCard] {
        activeCards.isEmpty ? archivedCards : activeCards
    }

    var priorityCount: Int {
        summaryCards.filter(\.requiresProfessionalReview).count
    }

    var contraindicationCount: Int {
        summaryCards.filter(isContraindicationRisk).count
    }

    var highestPriority: Int {
        summaryCards.map(\.displayPriority).min() ?? Int.max
    }

    var summaryCountText: String {
        if activeCards.isEmpty {
            return "已归档 \(archivedCards.count) 条"
        }
        return "\(activeCards.count) 条警示"
    }
}

private enum RiskMedicationDisplayBuilder {
    static func sections(
        from cards: [StoredRiskCard],
        medicationName: (StoredRiskCard) -> String,
        medicationVisual: (MedicationRiskSection) -> RiskVisualStyle
    ) -> [MedicationRiskSection] {
        Dictionary(grouping: deduplicatedCards(from: cards), by: \.medicationID)
            .compactMap { medicationID, medicationCards in
                guard let firstCard = medicationCards.first else {
                    return nil
                }
                let section = MedicationRiskSection(
                    medicationID: medicationID,
                    medicationName: medicationName(firstCard),
                    visual: .neutral,
                    cards: medicationCards
                )
                return MedicationRiskSection(
                    medicationID: section.medicationID,
                    medicationName: section.medicationName,
                    visual: medicationVisual(section),
                    cards: section.cards
                )
            }
            .sorted { lhs, rhs in
                if lhs.highestPriority != rhs.highestPriority {
                    return lhs.highestPriority < rhs.highestPriority
                }
                let nameOrder = lhs.medicationName.localizedStandardCompare(rhs.medicationName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.medicationID.uuidString < rhs.medicationID.uuidString
            }
    }

    static func deduplicatedCards(from cards: [StoredRiskCard]) -> [StoredRiskCard] {
        var chosenCards: [String: StoredRiskCard] = [:]
        for card in cards {
            let key = duplicateKey(for: card)
            if let existingCard = chosenCards[key] {
                chosenCards[key] = preferredCard(existingCard, card)
            } else {
                chosenCards[key] = card
            }
        }
        return chosenCards.values.sorted(by: riskCardSort)
    }

    private static func duplicateKey(for card: StoredRiskCard) -> String {
        let medicationKey = card.medicationID.uuidString
        let sourceExcerpt = normalized(card.sourceExcerpt)
        if !sourceExcerpt.isEmpty {
            return "\(medicationKey)|source|\(sourceExcerpt)"
        }
        return "\(medicationKey)|content|\(normalized(card.title))|\(normalized(card.message))"
    }

    private static func preferredCard(_ lhs: StoredRiskCard, _ rhs: StoredRiskCard) -> StoredRiskCard {
        if lhs.isArchived != rhs.isArchived {
            return lhs.isArchived ? rhs : lhs
        }
        if lhs.isResolved != rhs.isResolved {
            return lhs.isResolved ? rhs : lhs
        }
        if lhs.requiresProfessionalReview != rhs.requiresProfessionalReview {
            return lhs.requiresProfessionalReview ? lhs : rhs
        }
        if lhs.displayPriority != rhs.displayPriority {
            return lhs.displayPriority < rhs.displayPriority ? lhs : rhs
        }
        let lhsSpecificity = specificityScore(for: lhs)
        let rhsSpecificity = specificityScore(for: rhs)
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity > rhsSpecificity ? lhs : rhs
        }
        return lhs.id <= rhs.id ? lhs : rhs
    }

    private static func specificityScore(for card: StoredRiskCard) -> Int {
        var score = 0
        if !card.sourceTitle.isEmpty { score += 1 }
        if !card.sourceExcerpt.isEmpty { score += 2 }
        if card.title.contains("相关复核") { score += 1 }
        if card.title == "警示信息" || card.title == "注意事项" { score -= 1 }
        return score
    }
}

private struct MedicationRiskDisclosureRow: View {
    let section: MedicationRiskSection
    @State private var isExpanded = false
    @State private var isShowingArchivedCards = false
    @State private var selectedCardID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0.01)) {
                    isExpanded.toggle()
                }
            } label: {
                MedicationRiskDisclosureHeader(section: section, isExpanded: isExpanded)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(section.medicationName)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpanded ? "收起药品风险" : "展开药品风险")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !section.activeCards.isEmpty {
                        ForEach(section.activeCards) { card in
                            RiskCardSelectionButton(
                                card: card,
                                hint: "查看警示详情",
                                select: { selectedCardID = card.id }
                            )
                        }
                    }

                    if !section.archivedCards.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
                                    isShowingArchivedCards.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isShowingArchivedCards ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                    Text("已复核归档 \(section.archivedCards.count) 条")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("已复核归档")
                            .accessibilityValue("\(section.archivedCards.count) 条，\(isShowingArchivedCards ? "已展开" : "已折叠")")

                            if isShowingArchivedCards {
                                ForEach(section.archivedCards) { card in
                                    RiskCardSelectionButton(
                                        card: card,
                                        hint: "查看归档警示详情",
                                        select: { selectedCardID = card.id }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .navigationDestination(isPresented: selectedCardNavigationBinding) {
            if let selectedCard {
                RiskCardDetailView(card: selectedCard, medicationName: section.medicationName)
            }
        }
    }

    private var accessibilityValue: String {
        var parts = [section.summaryCountText]
        if section.contraindicationCount > 0 {
            parts.append("\(section.contraindicationCount) 条禁忌")
        }
        if section.priorityCount > 0 {
            parts.append("\(section.priorityCount) 条需复核")
        }
        parts.append(isExpanded ? "已展开" : "已折叠")
        return parts.joined(separator: "，")
    }

    private var selectedCard: StoredRiskCard? {
        section.cards.first { $0.id == selectedCardID }
    }

    private var selectedCardNavigationBinding: Binding<Bool> {
        Binding {
            selectedCardID != nil
        } set: { isPresented in
            if !isPresented {
                selectedCardID = nil
            }
        }
    }
}

private struct RiskCardSelectionButton: View {
    let card: StoredRiskCard
    let hint: String
    let select: () -> Void

    var body: some View {
        MedicationRiskCardRow(card: card)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            select()
        }
    }

    private var accessibilityLabel: String {
        riskDisplayTitle(for: card)
    }

    private var accessibilityValue: String {
        var parts = [riskCategoryText(for: card), riskSourceText(for: card)]
        if isContraindicationRisk(card) {
            parts.append("禁忌或慎用")
        }
        if card.requiresProfessionalReview {
            parts.append("建议复核")
        }
        if card.isReviewed {
            parts.append(card.isActive ? "已查看仍需关注" : "已复核")
        }
        return parts.joined(separator: "，")
    }
}

private struct MedicationRiskDisclosureHeader: View {
    let section: MedicationRiskSection
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(section.visual.tint.opacity(0.12))
                Image(systemName: section.visual.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(section.visual.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(section.medicationName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    StatusBadge(text: section.summaryCountText, color: section.activeCards.isEmpty ? .secondary : section.visual.tint)
                    if section.contraindicationCount > 0 {
                        StatusBadge(text: "\(section.contraindicationCount) 条禁忌", color: RiskPalette.softRed)
                    }
                    if section.priorityCount > 0 {
                        StatusBadge(text: "\(section.priorityCount) 条需复核", color: RiskPalette.indigo)
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
    }
}

private struct RiskGroupSummaryCard: View {
    let group: RiskReviewGroup
    let count: Int
    let priorityCount: Int

    var body: some View {
        let visual = riskGroupVisual(for: group)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(visual.tint.opacity(0.11))
                Image(systemName: visual.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(visual.tint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.title)
                    .font(.headline)
                Text(group.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("\(count) 条")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if priorityCount > 0 {
                        Text("\(priorityCount) 条建议复核")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(visual.tint)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct RiskCardRow: View {
    let card: StoredRiskCard
    let medicationName: String

    var body: some View {
        MedicationRiskCardRow(card: card, medicationName: medicationName)
    }
}

struct MedicationRiskCardRow: View {
    let card: StoredRiskCard
    var medicationName: String? = nil

    var body: some View {
        let categoryText = riskCategoryText(for: card)
        let displayTitle = riskDisplayTitle(for: card)
        let showsCategoryBadge = normalized(displayTitle) != normalized(categoryText)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: riskCategoryIconName(for: card))
                    .font(.headline)
                    .foregroundStyle(riskCategoryTint(for: card))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayTitle)
                        .font(.headline)
                    HStack(spacing: 8) {
                        if showsCategoryBadge {
                            StatusBadge(text: categoryText, color: riskCategoryTint(for: card))
                        }
                        if isContraindicationRisk(card) {
                            StatusBadge(text: "禁忌/慎用", color: RiskPalette.rose)
                        }
                        if let medicationName {
                            StatusBadge(text: medicationName, color: RiskPalette.blue)
                        }
                        StatusBadge(text: riskSourceText(for: card), color: sourceTint(for: card))
                    }
                }
            }
            Text(riskActionableSummaryText(for: card))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let concreteFocus = riskConcreteFocusText(for: card) {
                Label(concreteFocus, systemImage: "scope")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(riskCategoryTint(for: card))
                    .lineLimit(2)
            }
            if let sourceExcerpt = riskSourceExcerptPreview(for: card), sourceExcerpt != extractedRiskFocus(from: card) {
                Text("依据：\(sourceExcerpt)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if card.isActive, card.isReviewed {
                Text("已查看，仍需关注")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if card.isReviewed {
                Text("已复核")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct RiskEmptyStateView: View {
    let hasMedications: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂无用药风险提醒", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(hasMedications ? "说明书信息不足。" : "先添加药品。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct RiskGroupDetailView: View {
    let group: RiskReviewGroup
    let cards: [StoredRiskCard]
    let medicationName: (StoredRiskCard) -> String

    private var medicationSections: [MedicationRiskSection] {
        RiskMedicationDisplayBuilder.sections(
            from: cards,
            medicationName: medicationName,
            medicationVisual: { medicationRiskVisual(for: nil, cards: $0.cards, medicationName: $0.medicationName) }
        )
    }

    var body: some View {
        List {
            Section {
                Text(group.description)
                    .foregroundStyle(.secondary)
            }

            Section("按药品查看") {
                if medicationSections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前没有该类风险提醒。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(medicationSections) { section in
                        MedicationRiskDisclosureRow(section: section)
                    }
                }
            }
        }
        .navigationTitle(group.title)
    }
}

struct RiskCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openMedicationAIQuestion) private var openMedicationAIQuestion
    let card: StoredRiskCard
    let medicationName: String
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]

    private var medication: StoredMedication? {
        medications.first { $0.id == card.medicationID }
    }

    private var shareText: String {
        [
            "用药风险沟通摘要",
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            "提示：\(riskActionableSummaryText(for: card))",
            riskConcreteFocusText(for: card).map { "核对对象：\(riskShareFocusText($0))" },
            card.sourceTitle.isEmpty ? nil : "来源：\(card.sourceTitle)",
            card.sourceExcerpt.isEmpty ? nil : "依据片段：\(card.sourceExcerpt)",
            card.safetyNote.isEmpty ? "说明：以上内容仅用于风险提示和复诊沟通，不能替代医生或药师判断。" : "说明：\(card.safetyNote)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private var communicationText: String {
        let summary = riskCommunicationSummaryText(for: card)
        return [
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            summary.isEmpty ? nil : "提示：\(summary)",
            riskCommunicationFocusLine(for: card, summary: summary),
            card.sourceTitle.isEmpty ? nil : "来源：\(card.sourceTitle)",
            riskCommunicationEvidenceLine(for: card, summary: summary)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        isContraindicationRisk(card) ? "禁忌/慎用提醒" : riskCategoryText(for: card),
                        systemImage: riskCategoryIconName(for: card)
                    )
                    .font(.headline)
                    .foregroundStyle(riskCategoryTint(for: card))
                    Text(riskDisplayTitle(for: card))
                        .font(.title3.weight(.semibold))
                    Text(medicationName)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("提示内容") {
                Text(riskActionableSummaryText(for: card))
            }

            if let concreteFocus = riskConcreteFocusText(for: card) {
                Section("需要核对") {
                    Label(concreteFocus, systemImage: "scope")
                        .foregroundStyle(riskCategoryTint(for: card))
                }
            }

            Section("关联操作") {
                if let medication {
                    NavigationLink {
                        MedicationDetailView(medication: medication)
                    } label: {
                        Label("查看相关药品", systemImage: "pills.fill")
                    }
                }
                Button {
                    openMedicationAIQuestion(aiQuestion)
                } label: {
                    Label("让智能体解释这条警示", systemImage: "stethoscope")
                }
            }

            Section("复诊沟通") {
                Text(communicationText)
                    .font(.body)
                    .textSelection(.enabled)
                ShareLink(item: shareText) {
                    Label("分享给医生或药师", systemImage: "square.and.arrow.up")
                }
            }

            Section("处理") {
                if card.isArchived || card.isResolved {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.isResolved ? "已解除归档" : "已复核归档")
                                .font(.headline)
                            Text(card.reviewedAt.map { "复核时间：\(AppFormatters.day.string(from: $0)) \(AppFormatters.time.string(from: $0))" } ?? (card.isResolved ? "该警示已解除。" : "该警示已归档。"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        card.archivedAt = nil
                        card.resolvedAt = nil
                        card.resolutionNote = ""
                        card.reviewNote = ""
                        card.readAt = nil
                        try? modelContext.save()
                    } label: {
                        Label("重新打开警示", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        card.reviewedAt = Date()
                        card.archivedAt = Date()
                        card.reviewNote = "用户已复核并归档。"
                        try? modelContext.save()
                    } label: {
                        Label("标记已复核并归档", systemImage: "checkmark.circle")
                    }
                }
            }

            if !card.sourceExcerpt.isEmpty || !card.sourceTitle.isEmpty {
                Section("依据片段") {
                    HStack {
                        Text("来源")
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(text: riskSourceText(for: card), color: sourceTint(for: card))
                    }
                    if !card.sourceTitle.isEmpty {
                        Text(card.sourceTitle)
                            .font(.headline)
                    }
                    if !card.sourceExcerpt.isEmpty {
                        Text(card.sourceExcerpt)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("使用边界") {
                Text(card.safetyNote.isEmpty ? "以上内容仅用于风险提示，不能替代医生或药师判断。" : card.safetyNote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("警示详情")
    }

    private var aiQuestion: String {
        [
            "请帮我解释这条用药风险，并给出适合复诊沟通的提醒。",
            "药品：\(medicationName)",
            "警示：\(riskDisplayTitle(for: card))",
            "内容：\(riskActionableSummaryText(for: card))",
            riskConcreteFocusText(for: card).map { "核对对象：\(riskShareFocusText($0))" },
            card.sourceExcerpt.isEmpty ? nil : "依据：\(card.sourceExcerpt)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

func riskCardSort(_ lhs: StoredRiskCard, _ rhs: StoredRiskCard) -> Bool {
    if lhs.displayPriority != rhs.displayPriority {
        return lhs.displayPriority < rhs.displayPriority
    }
    if lhs.requiresProfessionalReview != rhs.requiresProfessionalReview {
        return lhs.requiresProfessionalReview
    }
    let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
    if titleOrder != .orderedSame {
        return titleOrder == .orderedAscending
    }
    return lhs.id < rhs.id
}

private struct RiskVisualStyle: Equatable {
    let symbolName: String
    let tint: Color

    static let neutral = RiskVisualStyle(symbolName: "pills.fill", tint: RiskPalette.slate)
}

private enum RiskPalette {
    static let slate = Color(red: 0.42, green: 0.48, blue: 0.56)
    static let blue = Color(red: 0.31, green: 0.47, blue: 0.62)
    static let teal = Color(red: 0.27, green: 0.50, blue: 0.48)
    static let indigo = Color(red: 0.43, green: 0.43, blue: 0.59)
    static let amber = Color(red: 0.62, green: 0.51, blue: 0.32)
    static let green = Color(red: 0.36, green: 0.53, blue: 0.40)
    static let rose = Color(red: 0.58, green: 0.38, blue: 0.40)
    static let grape = Color(red: 0.49, green: 0.43, blue: 0.58)
    static let softRed = rose
}

private func riskGroupVisual(for group: RiskReviewGroup) -> RiskVisualStyle {
    switch group {
    case .drugInteraction:
        RiskVisualStyle(symbolName: "pills.fill", tint: RiskPalette.indigo)
    case .foodAndLifestyleInteraction:
        RiskVisualStyle(symbolName: "fork.knife", tint: RiskPalette.teal)
    case .conditionAndSymptomAttention:
        RiskVisualStyle(symbolName: "heart.text.square", tint: RiskPalette.softRed)
    }
}

private func medicationRiskVisual(
    for medication: StoredMedication?,
    cards: [StoredRiskCard],
    medicationName fallbackName: String? = nil
) -> RiskVisualStyle {
    let primaryText = normalized([
        medication?.displayName,
        medication?.genericName,
        medication?.form,
        medication?.strength,
        fallbackName
    ]
    .compactMap { $0 }
    .joined(separator: " "))
    let fallbackText = primaryText.isEmpty ? normalized(medication?.notes ?? "") : ""
    let symbolName = medicationRiskSymbolName(
        for: medication,
        normalizedText: primaryText,
        fallbackText: fallbackText
    )
    let tint = medicationRiskTint(
        for: medication,
        normalizedText: primaryText,
        fallbackText: fallbackText
    )
    return RiskVisualStyle(symbolName: symbolName, tint: tint)
}

private func medicationRiskSymbolName(
    for medication: StoredMedication?,
    normalizedText text: String,
    fallbackText: String
) -> String {
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName),
       symbolName != "pills.fill" {
        return symbolName
    }
    if text.contains("滴眼") || text.contains("人工泪液") || text.contains("眼") {
        return "eye.fill"
    }
    if text.contains("喷") || text.contains("吸入") || text.contains("鼻") || text.contains("氯雷他定") || text.contains("loratadine") {
        return "wind"
    }
    if text.contains("维生素") || text.contains("vitamin") || text.contains("d3") {
        return "sun.max.fill"
    }
    if text.contains("布洛芬") || text.contains("对乙酰氨基酚") || text.contains("止痛") || text.contains("退热") || text.contains("ibuprofen") || text.contains("acetaminophen") {
        return "cross.case.fill"
    }
    if text.contains("胶囊") || text.contains("软胶囊") || text.contains("capsule") {
        return "capsule.fill"
    }
    if text.contains("贴") || text.contains("膏") || text.contains("外用") {
        return "bandage.fill"
    }
    if text.contains("注射") || text.contains("针") {
        return "syringe.fill"
    }
    if text.contains("颗粒") || text.contains("冲剂") || text.contains("粉") {
        return "shippingbox.fill"
    }
    if fallbackText.contains("滴眼") || fallbackText.contains("眼") {
        return "eye.fill"
    }
    if fallbackText.contains("吸入") || fallbackText.contains("鼻") {
        return "wind"
    }
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName) {
        return symbolName
    }
    return "pills.fill"
}

private func medicationRiskTint(
    for medication: StoredMedication?,
    normalizedText text: String,
    fallbackText: String
) -> Color {
    if let symbolName = medication?.photoSymbolName,
       isMedicationTypeSymbol(symbolName),
       symbolName != "pills.fill" {
        return medicationTintForSymbol(symbolName)
    }
    if text.contains("滴眼") || text.contains("人工泪液") || text.contains("眼") {
        return RiskPalette.teal
    }
    if text.contains("氯雷他定") || text.contains("loratadine") || text.contains("鼻") {
        return RiskPalette.blue
    }
    if text.contains("维生素") || text.contains("vitamin") || text.contains("d3") {
        return RiskPalette.amber
    }
    if text.contains("布洛芬") || text.contains("对乙酰氨基酚") || text.contains("止痛") || text.contains("退热") || text.contains("ibuprofen") || text.contains("acetaminophen") {
        return RiskPalette.indigo
    }
    if fallbackText.contains("滴眼") || fallbackText.contains("眼") {
        return RiskPalette.teal
    }
    if fallbackText.contains("吸入") || fallbackText.contains("鼻") {
        return RiskPalette.blue
    }
    if let symbolName = medication?.photoSymbolName {
        return medicationTintForSymbol(symbolName)
    }
    return RiskPalette.slate
}

private func isMedicationTypeSymbol(_ symbolName: String) -> Bool {
    switch symbolName {
    case "pills.fill",
        "capsule.fill",
        "eye.fill",
        "wind",
        "sun.max.fill",
        "syringe.fill",
        "bandage.fill",
        "drop.fill",
        "shippingbox.fill",
        "cross.case.fill":
        return true
    default:
        return false
    }
}

private func medicationTintForSymbol(_ symbolName: String) -> Color {
    switch symbolName {
    case "eye.fill", "drop.fill":
        return RiskPalette.teal
    case "wind":
        return RiskPalette.blue
    case "sun.max.fill":
        return RiskPalette.amber
    case "capsule.fill":
        return RiskPalette.grape
    case "syringe.fill", "bandage.fill":
        return RiskPalette.green
    case "cross.case.fill":
        return RiskPalette.indigo
    default:
        return RiskPalette.slate
    }
}

private func normalized(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .punctuationCharacters)
}

private func isContraindicationRisk(_ card: StoredRiskCard) -> Bool {
    let text = normalized("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
    return text.contains("禁忌")
        || text.contains("禁用")
        || text.contains("contraindication")
        || text.contains("contraindicated")
        || text.contains("avoid")
}

private func riskCategoryText(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "饮食注意"
    case .healthConditionReview:
        return "病症注意"
    case .medicationSourceReview:
        return "来源核对"
    case .drugClassContext:
        return "类别信息"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return "相互作用"
        case .foodAndLifestyleInteraction:
            return "饮食注意"
        case .conditionAndSymptomAttention:
            return "病症注意"
        }
    }
}

private func riskConcreteFocusText(for card: StoredRiskCard) -> String? {
    let focus = extractedRiskFocus(from: card)
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        guard !focus.isEmpty else {
            return "当前资料未写明具体饮食或生活方式，请补充说明书或向医生或药师确认。"
        }
        return "需核对饮食或生活方式：\(focus)"
    case .healthConditionReview:
        guard !focus.isEmpty else {
            return "当前资料未写明具体病症或症状，请补充病史信息或向医生或药师确认。"
        }
        return "需核对病症或症状：\(focus)"
    case .medicationSourceReview:
        guard !focus.isEmpty else {
            return "当前资料未写明药品来源细节，请按药盒、说明书或医嘱核对。"
        }
        return "需核对来源：\(focus)"
    case .drugClassContext:
        guard !focus.isEmpty else {
            return nil
        }
        return "药品类别：\(focus)"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            guard !focus.isEmpty else {
                return "当前说明书未写明具体禁忌对象，请补充完整说明书或向医生或药师确认。"
            }
            return "需核对禁忌条件：\(focus)"
        }
        switch grouped {
        case .drugInteraction:
            guard !focus.isEmpty else {
                return "当前资料未写明合用药品名称，请补充说明书或向医生或药师确认。"
            }
            return "需核对合用药品：\(focus)"
        case .foodAndLifestyleInteraction:
            guard !focus.isEmpty else {
                return "当前资料未写明具体饮食或生活方式，请补充说明书或向医生或药师确认。"
            }
            return "需核对饮食或生活方式：\(focus)"
        case .conditionAndSymptomAttention:
            guard !focus.isEmpty else {
                return "当前资料未写明具体病症或症状，请补充病史信息或向医生或药师确认。"
            }
            return "需核对病症或症状：\(focus)"
        }
    }
}

private func riskShareFocusText(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("需核对") else {
        return trimmed
    }
    return String(trimmed.dropFirst("需核对".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isMissingRiskFocusText(_ text: String) -> Bool {
    let normalizedText = normalized(text)
    return normalizedText.contains("未写明")
        || normalizedText.contains("请补充")
        || normalizedText.contains("待补充")
}

private func missingRiskFocusTitle(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "待补充饮食或生活方式"
    case .healthConditionReview:
        return "待补充病症或症状"
    case .medicationSourceReview:
        return "待补充来源细节"
    case .drugClassContext:
        return "待补充类别来源"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            return "待补充禁忌对象"
        }
        switch grouped {
        case .drugInteraction:
            return "待补充合用药品"
        case .foodAndLifestyleInteraction:
            return "待补充饮食或生活方式"
        case .conditionAndSymptomAttention:
            return "待补充病症或症状"
        }
    }
}

private func missingRiskFocusSummary(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "当前资料没有具体饮食或生活方式，请补充说明书或向医生或药师确认。"
    case .healthConditionReview:
        return "当前资料没有具体病症或症状，请补充病史信息或向医生或药师确认。"
    case .medicationSourceReview:
        return "当前资料没有药品来源细节，请按药盒、说明书或医嘱核对。"
    case .drugClassContext:
        return "当前资料没有完整药品类别来源，请补充药品资料后再复核。"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        if isContraindicationRisk(card) {
            return "当前说明书没有具体禁忌对象，请补充完整说明书或向医生或药师确认。"
        }
        switch grouped {
        case .drugInteraction:
            return "当前资料没有具体合用药品名称，请补充说明书或向医生或药师确认。"
        case .foodAndLifestyleInteraction:
            return "当前资料没有具体饮食或生活方式，请补充说明书或向医生或药师确认。"
        case .conditionAndSymptomAttention:
            return "当前资料没有具体病症或症状，请补充病史信息或向医生或药师确认。"
        }
    }
}

private func riskDisplayTitle(for card: StoredRiskCard) -> String {
    let rawTitle = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard shouldExpandRiskDisplayTitle(rawTitle) else {
        return rawTitle.isEmpty ? riskCategoryText(for: card) : rawTitle
    }
    let category = isContraindicationRisk(card) ? "禁忌或慎用" : riskCategoryText(for: card)
    guard let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
          !focus.isEmpty
    else {
        return category
    }
    if isMissingRiskFocusText(focus) {
        return "\(category)：\(missingRiskFocusTitle(for: card))"
    }
    return "\(category)：\(riskCompactTitleFocusText(focus))"
}

private func shouldExpandRiskDisplayTitle(_ title: String) -> Bool {
    let normalizedTitle = normalized(title)
    return isGenericRiskFocus(title)
        || normalizedTitle == "警示信息"
        || normalizedTitle == "注意事项"
        || normalizedTitle == "禁忌"
        || normalizedTitle == "禁忌或不得使用"
        || normalizedTitle == "相互作用"
        || normalizedTitle == "相互作用或需咨询药师"
        || normalizedTitle == "饮食注意"
        || normalizedTitle == "不良反应"
}

private func riskCompactTitleFocusText(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = [
        "禁忌条件：",
        "合用药品：",
        "饮食或生活方式：",
        "病症或症状：",
        "来源：",
        "药品类别："
    ]
    for prefix in prefixes where value.hasPrefix(prefix) {
        value = String(value.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        break
    }
    return value
}

private func riskActionableSummaryText(for card: StoredRiskCard) -> String {
    let message = cleanedRiskFocusText(card.message, limit: 96)
    let focus = riskConcreteFocusText(for: card).map(riskShareFocusText)
    let sourceExcerpt = riskSourceExcerptPreview(for: card)
    let category = isContraindicationRisk(card) ? "禁忌或慎用" : riskCategoryText(for: card)
    let baseMessage: String
    if message.isEmpty || isGenericRiskFocus(message) {
        baseMessage = "\(category)提醒，需要结合药品资料复核。"
    } else {
        baseMessage = message
    }
    let focusText: String?
    if let focus, !focus.isEmpty, focus != baseMessage {
        focusText = isMissingRiskFocusText(focus)
            ? missingRiskFocusSummary(for: card)
            : "重点核对\(focus)"
    } else {
        focusText = nil
    }
    let evidenceText: String?
    if let sourceExcerpt, !sourceExcerpt.isEmpty, sourceExcerpt != focus, sourceExcerpt != baseMessage {
        evidenceText = "依据片段：\(sourceExcerpt)"
    } else {
        evidenceText = nil
    }
    return [baseMessage, focusText, evidenceText]
        .compactMap { $0 }
        .joined(separator: "\n")
}

private func riskCommunicationSummaryText(for card: StoredRiskCard) -> String {
    let message = cleanedRiskFocusText(card.message, limit: 140)
    if !message.isEmpty && !isGenericRiskFocus(message) {
        return message
    }
    if let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
       !focus.isEmpty {
        return isMissingRiskFocusText(focus) ? missingRiskFocusSummary(for: card) : "请核对\(focus)"
    }
    if let sourceExcerpt = riskSourceExcerptPreview(for: card) {
        return sourceExcerpt
    }
    return riskActionableSummaryText(for: card)
}

private func riskCommunicationFocusLine(for card: StoredRiskCard, summary: String) -> String? {
    guard let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
          !focus.isEmpty,
          !isMissingRiskFocusText(focus),
          !riskText(summary, containsRiskFragment: focus)
    else {
        return nil
    }
    return "需要核对：\(focus)"
}

private func riskCommunicationEvidenceLine(for card: StoredRiskCard, summary: String) -> String? {
    guard let sourceExcerpt = riskSourceExcerptPreview(for: card),
          !riskText(summary, containsRiskFragment: sourceExcerpt)
    else {
        return nil
    }
    if let focus = riskConcreteFocusText(for: card).map(riskShareFocusText),
       riskText(focus, containsRiskFragment: sourceExcerpt) {
        return nil
    }
    return "依据片段：\(sourceExcerpt)"
}

private func riskText(_ text: String, containsRiskFragment fragment: String) -> Bool {
    let normalizedText = normalized(text)
    let fragments = [
        fragment,
        riskCompactTitleFocusText(fragment)
    ]
    return fragments.contains { value in
        let normalizedFragment = normalized(value)
        return !normalizedFragment.isEmpty && normalizedText.contains(normalizedFragment)
    }
}

private func extractedRiskFocus(from card: StoredRiskCard) -> String {
    let titleFocus = riskFocusFromReviewTitle(card.title)
    if !titleFocus.isEmpty {
        return titleFocus
    }
    if let sourceExcerpt = riskSourceExcerptPreview(for: card) {
        return sourceExcerpt
    }
    let message = cleanedRiskFocusText(card.message, limit: 72)
    if isGenericRiskFocus(message) {
        return ""
    }
    return message
}

private func riskFocusFromReviewTitle(_ title: String) -> String {
    guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
        return ""
    }
    return cleanedRiskFocusText(String(title[title.index(after: separatorIndex)...]), limit: 48)
}

private func riskSourceExcerptPreview(for card: StoredRiskCard) -> String? {
    let excerpt = cleanedRiskFocusText(card.sourceExcerpt, limit: 96)
    return excerpt.isEmpty ? nil : excerpt
}

private func cleanedRiskFocusText(_ text: String, limit: Int) -> String {
    let collapsed = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .replacingOccurrences(of: "说明书“", with: "")
        .replacingOccurrences(of: "”指出：", with: "：")
        .replacingOccurrences(of: "请咨询医生或药师", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty else {
        return ""
    }
    guard collapsed.count > limit else {
        return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
    return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func isGenericRiskFocus(_ text: String) -> Bool {
    let normalizedText = normalized(text)
    return normalizedText.isEmpty
        || normalizedText == "相关风险"
        || normalizedText == "相关警示"
        || normalizedText == "相关提醒"
        || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
}

private func riskCategoryIconName(for card: StoredRiskCard) -> String {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return "fork.knife"
    case .healthConditionReview:
        return "heart.text.square"
    case .medicationSourceReview:
        return "doc.badge.exclamationmark"
    case .drugClassContext:
        return "tag.fill"
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return "pills.fill"
        case .foodAndLifestyleInteraction:
            return "fork.knife"
        case .conditionAndSymptomAttention:
            return "heart.text.square"
        }
    }
}

private func riskCategoryTint(for card: StoredRiskCard) -> Color {
    switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
    case .foodReview:
        return RiskPalette.teal
    case .healthConditionReview:
        return RiskPalette.rose
    case .medicationSourceReview:
        return RiskPalette.amber
    case .drugClassContext:
        return RiskPalette.indigo
    case .labelRisk:
        let grouped = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
        switch grouped {
        case .drugInteraction:
            return RiskPalette.indigo
        case .foodAndLifestyleInteraction:
            return RiskPalette.teal
        case .conditionAndSymptomAttention:
            return RiskPalette.rose
        }
    }
}

private func riskSourceText(for card: StoredRiskCard) -> String {
    if card.id.contains("-\(MedicationRiskReviewService.userLabelRiskIDPrefix)-") {
        return "用户导入说明书"
    }
    if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue {
        return "药品来源复核"
    }
    if card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
        return "药品类别信息"
    }
    if !card.sourceTitle.isEmpty || !card.sourceExcerpt.isEmpty {
        return "说明书资料"
    }
    return "本地规则"
}

private func sourceTint(for card: StoredRiskCard) -> Color {
    if card.id.contains("-\(MedicationRiskReviewService.userLabelRiskIDPrefix)-") {
        return RiskPalette.green
    }
    if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue {
        return RiskPalette.amber
    }
    if card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
        return RiskPalette.indigo
    }
    return .secondary
}
