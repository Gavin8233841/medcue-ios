import MedicationAdherenceCore
import SwiftData
import SwiftUI

struct RisksView: View {
    @Query(sort: \StoredRiskCard.displayPriority) private var riskCards: [StoredRiskCard]
    @Query(sort: \StoredMedication.displayName) private var medications: [StoredMedication]
    private let grouper = RiskReviewGrouper()

    private var activeRiskCards: [StoredRiskCard] {
        riskCards.filter { !$0.isArchived }
    }

    private var archivedRiskCards: [StoredRiskCard] {
        riskCards.filter(\.isArchived)
    }

    var body: some View {
        List {
            let priorityCards = severePriorityCards
            if !priorityCards.isEmpty {
                Section("需要优先复核") {
                    ForEach(priorityCards.prefix(1)) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: medicationName(for: card))
                        } label: {
                            PriorityRiskRow(card: card, medicationName: medicationName(for: card))
                        }
                    }
                    let foldedCards = Array(priorityCards.dropFirst().prefix(2))
                    if !foldedCards.isEmpty {
                        DisclosureGroup("另有 \(priorityCards.count - 1) 条严重警示") {
                            ForEach(foldedCards) { card in
                                NavigationLink {
                                    RiskCardDetailView(card: card, medicationName: medicationName(for: card))
                                } label: {
                                    RiskCardRow(card: card, medicationName: medicationName(for: card))
                                }
                            }
                        }
                    }
                }
            }

            Section("风险总览") {
                ForEach(RiskReviewGroup.allCases, id: \.rawValue) { group in
                    let groupedCards = cards(for: group)
                    NavigationLink {
                        RiskGroupDetailView(
                            group: group,
                            cards: groupedCards,
                            medicationName: medicationName
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

            Section("全部警示") {
                if activeRiskCards.isEmpty {
                    RiskEmptyStateView(hasMedications: !medications.isEmpty)
                } else {
                    ForEach(activeRiskCards) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: medicationName(for: card))
                        } label: {
                            RiskCardRow(
                                card: card,
                                medicationName: medicationName(for: card)
                            )
                        }
                    }
                }
            }

            if !archivedRiskCards.isEmpty {
                Section("已复核归档") {
                    ForEach(archivedRiskCards) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: medicationName(for: card))
                        } label: {
                            RiskCardRow(card: card, medicationName: medicationName(for: card))
                        }
                    }
                }
            }

            Section("免责与来源") {
                Text("风险提示来自说明书、用户确认的导入信息和已授权的数据复核。以上内容仅用于用药风险提示和复诊沟通，不能替代医生或药师判断，也不会诊断、处方或自动调整用药。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("风险")
    }

    private var severePriorityCards: [StoredRiskCard] {
        activeRiskCards.filter { $0.requiresProfessionalReview && $0.displayPriority <= 12 }
    }

    private func cards(for group: RiskReviewGroup) -> [StoredRiskCard] {
        activeRiskCards.filter { grouper.mappedGroup(for: $0.coreRiskCard) == group }
    }

    private func medicationName(for card: StoredRiskCard) -> String {
        medications.first { $0.id == card.medicationID }?.displayName ?? "未知药品"
    }
}

private struct RiskGroupSummaryCard: View {
    let group: RiskReviewGroup
    let count: Int
    let priorityCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.14))
                Image(systemName: iconName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
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
                    StatusBadge(text: "\(count) 条", color: tint)
                    if priorityCount > 0 {
                        StatusBadge(text: "\(priorityCount) 条需复核", color: .orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        switch group {
        case .drugInteraction:
            .orange
        case .foodAndLifestyleInteraction:
            .blue
        case .conditionAndSymptomAttention:
            .purple
        }
    }

    private var iconName: String {
        switch group {
        case .drugInteraction:
            "pills.fill"
        case .foodAndLifestyleInteraction:
            "fork.knife"
        case .conditionAndSymptomAttention:
            "heart.text.square"
        }
    }
}

private struct PriorityRiskRow: View {
    let card: StoredRiskCard
    let medicationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(card.title)
                    .font(.headline)
            }
            Text(medicationName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 6)
    }
}

private struct RiskCardRow: View {
    let card: StoredRiskCard
    let medicationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: card.requiresProfessionalReview ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(card.requiresProfessionalReview ? .orange : .blue)
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(.headline)
                    Text(medicationName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(card.message)
                .font(.body)
            if !card.sourceExcerpt.isEmpty {
                Text(card.sourceExcerpt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                StatusBadge(text: medicationName, color: .blue)
                StatusBadge(text: riskSourceText(for: card), color: sourceTint(for: card))
            }
            Text(card.safetyNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if card.isReviewed {
                StatusBadge(text: "已复核", color: .green)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct RiskEmptyStateView: View {
    let hasMedications: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂无自动风险卡片", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(hasMedications ? "进入药品详情导入说明书后，App 会按章节和关键词在本地生成警示，并在这里按相互作用、饮食生活方式、病症症状分组展示。" : "先在药品页添加药品，再导入说明书生成风险卡片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("识别结果会保留来源片段，可跳转到药品详情继续核对。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct RiskGroupDetailView: View {
    let group: RiskReviewGroup
    let cards: [StoredRiskCard]
    let medicationName: (StoredRiskCard) -> String

    var body: some View {
        List {
            Section {
                Text(group.description)
                    .foregroundStyle(.secondary)
            }

            Section("警示列表") {
                if cards.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前没有该类风险卡片。")
                            .foregroundStyle(.secondary)
                        Text("当用户导入说明书或补充病症、饮食注意后，相关警示会自动进入这个分组。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(cards) { card in
                        NavigationLink {
                            RiskCardDetailView(card: card, medicationName: medicationName(card))
                        } label: {
                            RiskCardRow(card: card, medicationName: medicationName(card))
                        }
                    }
                }
            }
        }
        .navigationTitle(group.title)
    }
}

private struct RiskCardDetailView: View {
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
            "警示：\(card.title)",
            "提示：\(card.message)",
            card.sourceTitle.isEmpty ? nil : "来源：\(card.sourceTitle)",
            card.sourceExcerpt.isEmpty ? nil : "依据片段：\(card.sourceExcerpt)",
            card.safetyNote.isEmpty ? "说明：以上内容仅用于风险提示和复诊沟通，不能替代医生或药师判断。" : "说明：\(card.safetyNote)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        card.requiresProfessionalReview ? "建议专业复核" : "用药注意",
                        systemImage: card.requiresProfessionalReview ? "exclamationmark.triangle.fill" : "info.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(card.requiresProfessionalReview ? .orange : .blue)
                    Text(card.title)
                        .font(.title3.weight(.semibold))
                    Text(medicationName)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("提示内容") {
                Text(card.message)
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
                    Label("让 AI 解释这条警示", systemImage: "stethoscope")
                }
                Text("AI 解释会跳转到 AI 助手并预填问题；发送前仍需用户确认授权。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("复诊沟通") {
                Text(shareText)
                    .font(.body)
                    .textSelection(.enabled)
                ShareLink(item: shareText) {
                    Label("分享给医生或药师", systemImage: "square.and.arrow.up")
                }
            }

            Section("处理") {
                if card.isArchived {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已复核归档")
                                .font(.headline)
                            Text(card.reviewedAt.map { "复核时间：\(AppFormatters.day.string(from: $0)) \(AppFormatters.time.string(from: $0))" } ?? "该警示已归档。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        card.archivedAt = nil
                        card.reviewNote = ""
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
                    Text("归档不会删除记录，可在风险页的已复核归档中查看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

            Section("安全边界") {
                Text(card.safetyNote.isEmpty ? "以上内容仅用于风险提示，不能替代医生或药师判断。" : card.safetyNote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("警示详情")
    }

    private var aiQuestion: String {
        [
            "请用不超过100字解释这条用药风险，保持纯文本，并给出适合复诊沟通的提醒。",
            "药品：\(medicationName)",
            "警示：\(card.title)",
            "内容：\(card.message)",
            card.sourceExcerpt.isEmpty ? nil : "依据：\(card.sourceExcerpt)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
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
        return .green
    }
    if card.kindRaw == RiskAssessmentCardKind.medicationSourceReview.rawValue {
        return .orange
    }
    if card.kindRaw == RiskAssessmentCardKind.drugClassContext.rawValue {
        return .purple
    }
    return .secondary
}
