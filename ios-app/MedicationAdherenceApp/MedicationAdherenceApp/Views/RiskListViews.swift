import Foundation
import MedicationAdherenceCore
import SwiftData
import SwiftUI

@MainActor
enum RiskDisplaySnapshotCache {
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

struct RiskDisplaySnapshot {
    static var empty: RiskDisplaySnapshot {
        RiskDisplaySnapshot(
            medicationRiskSections: [],
            archivedMedicationRiskSections: [],
            cardsByGroup: [:],
            medicationNamesByID: [:],
            isPlaceholder: true
        )
    }

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
        let projection = RiskDisplayProjection(
            riskCards: riskCards,
            medications: medications,
            grouper: grouper
        )
        let medicationsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        self.medicationRiskSections = RiskMedicationDisplayBuilder.sections(
            from: projection.activeCards,
            medicationName: projection.medicationName(for:),
            medicationVisual: { medicationRiskVisual(for: medicationsByID[$0.medicationID], cards: $0.cards) }
        )
        self.archivedMedicationRiskSections = RiskMedicationDisplayBuilder.sections(
            from: projection.archivedCards,
            medicationName: projection.medicationName(for:),
            medicationVisual: { medicationRiskVisual(for: medicationsByID[$0.medicationID], cards: $0.cards) }
        )
        self.cardsByGroup = projection.cardsByGroup
        self.medicationNamesByID = projection.medicationNamesByID
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
        RiskDisplayProjection.refreshID(
            riskCards: riskCards,
            medications: medications
        )
    }

    func medicationName(for card: StoredRiskCard) -> String {
        medicationNamesByID[card.medicationID] ?? "未知药品"
    }
}

struct MedicationRiskSection: Identifiable {
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

enum RiskMedicationDisplayBuilder {
    static func sections(
        from cards: [StoredRiskCard],
        medicationName: (StoredRiskCard) -> String,
        medicationVisual: (MedicationRiskSection) -> RiskVisualStyle
    ) -> [MedicationRiskSection] {
        Dictionary(grouping: cards, by: \.medicationID)
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
}

struct MedicationRiskDisclosureRow: View {
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

struct RiskCardSelectionButton: View {
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

struct MedicationRiskDisclosureHeader: View {
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

struct RiskGroupSummaryCard: View {
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

struct RiskCardRow: View {
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

struct RiskEmptyStateView: View {
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

struct RiskGroupDetailView: View {
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
