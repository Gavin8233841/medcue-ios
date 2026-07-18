import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMode: AppHelpMode = .tutorial
    @State private var showingProductTour = false
    @State private var expandedTutorialGoalIDs = Set<String>()
    @State private var expandedExplanationCategoryIDs = Set<String>()

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [AppHelpTopic] {
        let query = normalizedQuery
        let topics = AppHelpCatalog.topics(for: selectedMode)
        guard !query.isEmpty else {
            return topics
        }
        return topics.filter { $0.matches(query) }
    }

    private var filteredSections: [AppHelpSection] {
        let query = normalizedQuery
        let sections = AppHelpCatalog.sections(for: selectedMode)
        guard !query.isEmpty else {
            return sections
        }
        return sections.compactMap { section in
            let topics = section.topics.filter { $0.matches(query) }
            guard !topics.isEmpty else {
                return nil
            }
            return AppHelpSection(category: section.category, topics: topics)
        }
    }

    private var filteredGoalGroups: [AppHelpGoalTopicGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return AppHelpCatalog.tutorialGoalGroups
        }
        return AppHelpCatalog.goals.compactMap { goal in
            let topics = AppHelpCatalog.topics(for: goal, mode: .tutorial).filter { $0.matches(query) }
            guard !topics.isEmpty else {
                return nil
            }
            return AppHelpGoalTopicGroup(goal: goal, topics: topics)
        }
    }

    private var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("快速找到需要的帮助", systemImage: "sparkle.magnifyingglass")
                            .font(.headline)
                        Text("按任务、功能或关键词查找，常用问题会优先出现。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        AppHelpModeSelector(selection: $selectedMode)
                    }
                    .padding(.vertical, 4)
                }

                if isSearching {
                    Section("搜索结果") {
                        if searchResults.isEmpty {
                            ContentUnavailableView("没有找到相关帮助", systemImage: "magnifyingglass")
                        } else {
                            ForEach(searchResults) { topic in
                                NavigationLink {
                                    AppHelpTopicDetailView(topic: topic, preferredMode: selectedMode)
                                } label: {
                                    AppHelpTopicRow(topic: topic, mode: selectedMode)
                                }
                            }
                        }
                    }
                } else {
                    switch selectedMode {
                    case .tutorial:
                        Section("按任务查找") {
                            ForEach(filteredGoalGroups) { group in
                                Button {
                                    toggleTutorialGoal(group.goal)
                                } label: {
                                    AppHelpGoalHeader(
                                        goal: group.goal,
                                        count: group.topics.count,
                                        isExpanded: expandedTutorialGoalIDs.contains(group.goal.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(group.goal.title)
                                .accessibilityValue("\(group.topics.count) 个主题，\(expandedTutorialGoalIDs.contains(group.goal.id) ? "已展开" : "已折叠")")

                                if expandedTutorialGoalIDs.contains(group.goal.id) {
                                    ForEach(group.topics) { topic in
                                        NavigationLink {
                                            AppHelpTopicDetailView(topic: topic, preferredMode: .tutorial)
                                        } label: {
                                            AppHelpTopicRow(topic: topic, mode: .tutorial)
                                        }
                                    }
                                }
                            }
                        }
                    case .explanation:
                        Section("按功能查找") {
                            ForEach(filteredSections) { section in
                                Button {
                                    toggleExplanationCategory(section.category)
                                } label: {
                                    AppHelpSectionHeader(
                                        category: section.category,
                                        count: section.topics.count,
                                        isExpanded: expandedExplanationCategoryIDs.contains(section.category.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(section.category.title)
                                .accessibilityValue("\(section.topics.count) 个主题，\(expandedExplanationCategoryIDs.contains(section.category.id) ? "已展开" : "已折叠")")

                                if expandedExplanationCategoryIDs.contains(section.category.id) {
                                    ForEach(section.topics) { topic in
                                        NavigationLink {
                                            AppHelpTopicDetailView(topic: topic, preferredMode: .explanation)
                                        } label: {
                                            AppHelpTopicRow(topic: topic, mode: .explanation)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section("安全边界") {
                    Label("本 App 用于提醒、记录、风险提示和复诊沟通，不替代医生或药师判断。", systemImage: "shield.lefthalf.filled")
                    Label("处方药、禁忌、严重不适和剂量调整，应咨询医生或药师。", systemImage: "person.text.rectangle")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("使用帮助")
            .searchable(text: $searchText, prompt: selectedMode.searchPrompt)
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        showingProductTour = true
                    } label: {
                        Label("快速上手", systemImage: "play.circle")
                    }
                    .accessibilityLabel("快速上手")

                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingProductTour) {
                FirstLaunchSetupView { _ in
                    showingProductTour = false
                }
            }
        }
    }

    private func toggleTutorialGoal(_ goal: AppHelpGoal) {
        if expandedTutorialGoalIDs.contains(goal.id) {
            expandedTutorialGoalIDs.remove(goal.id)
        } else {
            expandedTutorialGoalIDs.insert(goal.id)
        }
    }

    private func toggleExplanationCategory(_ category: AppHelpCategory) {
        if expandedExplanationCategoryIDs.contains(category.id) {
            expandedExplanationCategoryIDs.remove(category.id)
        } else {
            expandedExplanationCategoryIDs.insert(category.id)
        }
    }
}

private enum AppHelpMode: String, CaseIterable, Identifiable {
    case tutorial
    case explanation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tutorial:
            "教程步骤"
        case .explanation:
            "功能解释"
        }
    }

    var rowCaption: String {
        switch self {
        case .tutorial:
            "按步骤操作"
        case .explanation:
            "了解作用"
        }
    }

    var detailPrimarySectionTitle: String {
        switch self {
        case .tutorial:
            "操作步骤"
        case .explanation:
            "功能解释"
        }
    }

    var searchPrompt: String {
        switch self {
        case .tutorial:
            "搜索怎么添加、修正、导出…"
        case .explanation:
            "搜索趋势、风险、健康、授权…"
        }
    }
}

private struct AppHelpModeSelector: View {
    @Binding var selection: AppHelpMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppHelpMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(selection == mode ? .semibold : .regular))
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == mode {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue(selection == mode ? "已选择" : "未选择")
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct AppHelpSection: Identifiable {
    let category: AppHelpCategory
    let topics: [AppHelpTopic]

    var id: AppHelpCategory { category }
}

private struct AppHelpGoalTopicGroup: Identifiable {
    let goal: AppHelpGoal
    let topics: [AppHelpTopic]

    var id: String { goal.id }
}

private struct AppHelpCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
}

private struct AppHelpGoal: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let topicIDs: [String]

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let ownText = [title, subtitle]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        if ownText.contains(normalizedQuery) {
            return true
        }
        return AppHelpCatalog.topics(for: self).contains { $0.matches(query) }
    }
}

private struct AppHelpTopic: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbolName: String
    let tint: Color
    let steps: [String]
    let examples: [String]
    let keywords: [String]

    var tutorialPreview: String {
        steps.first ?? summary
    }

    var explanationPreview: String {
        AppHelpTopicDetailContent.explanationBullets(for: self).first ?? summary
    }

    func matches(_ query: String) -> Bool {
        let text = ([title, summary] + steps + examples + keywords)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedQuery = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        return text.contains(normalizedQuery)
    }
}

private enum AppHelpCatalog {
    static let today = AppHelpCategory(
        id: "today",
        title: "今日",
        subtitle: "处理今天要服用或已处理的药物",
        symbolName: "calendar",
        tint: .blue
    )
    static let medications = AppHelpCategory(
        id: "medications",
        title: "药品",
        subtitle: "录入药品、药盒、说明书和提醒",
        symbolName: "pills.fill",
        tint: .green
    )
    static let records = AppHelpCategory(
        id: "records",
        title: "记录与趋势",
        subtitle: "看周历、月历和用药趋势",
        symbolName: "chart.xyaxis.line",
        tint: .teal
    )
    static let risks = AppHelpCategory(
        id: "risks",
        title: "风险",
        subtitle: "按药品和类别核对警示",
        symbolName: "shield.lefthalf.filled",
        tint: .indigo
    )
    static let assistant = AppHelpCategory(
        id: "assistant",
        title: "智能体",
        subtitle: "授权后整理说明书和复诊问题",
        symbolName: "stethoscope",
        tint: .purple
    )
    static let profile = AppHelpCategory(
        id: "profile",
        title: "个人",
        subtitle: "复诊资料、Apple 健康、账号和隐私",
        symbolName: "person.crop.circle",
        tint: .orange
    )

    static let quickTopics: [AppHelpTopic] = [
        topic(
            id: "mark-dose",
            title: "处理一条今日用药",
            summary: "在今日页按实际情况选择已服用、稍后或忽略。",
            symbolName: "checkmark.circle.fill",
            tint: .blue,
            steps: [
                "在今日页找到对应时间和药品。",
                "核对药名、剂量、药盒编号或照片。",
                "按实际情况点已服用、稍后或忽略。",
                "误操作时展开今日已处理，可撤销到待处理。"
            ],
            examples: [
                "8:00 的药刚吃完：点已服用。",
                "暂时不方便服用：点稍后。",
                "医生已说明本次不服：点忽略。"
            ],
            keywords: ["今日", "已服用", "稍后", "忽略", "撤销"]
        ),
        topic(
            id: "add-medication",
            title: "添加或修改药品",
            summary: "从药品页右上角加号进入，先手动添加，图片和库存可稍后补。",
            symbolName: "plus.circle.fill",
            tint: .green,
            steps: [
                "进入药品页，点右上角加号。",
                "选择手动添加，填写药名、规格、剂型和提醒时间。",
                "保存前核对药盒、说明书、医嘱或药师建议。",
                "进入药品详情可继续补照片、药盒编号、库存和说明书。"
            ],
            examples: [
                "药盒上写着维生素 D3：先填药名和剂量，再拍药盒照片。",
                "药盒很多时：在药盒上写 B1、B2，并把编号填进药品详情。"
            ],
            keywords: ["药品", "添加", "修改", "药盒", "编号", "照片"]
        ),
        topic(
            id: "risk-review",
            title: "看懂风险提醒",
            summary: "药品页的风险复核按药品和类别整理，先看具体对象，再点详情核对来源。",
            symbolName: "exclamationmark.triangle.fill",
            tint: .indigo,
            steps: [
                "进入药品页，打开风险复核，先按药品查看需要复核的对象。",
                "看卡片里的需核对对象，例如过敏成分、合用药品、饮酒或症状。",
                "点开详情查看依据片段和相关药品。",
                "需要更通俗解释时，可跳到智能体预填问题。"
            ],
            examples: [
                "氯雷他定提示相互作用时，先核对是否正在使用酮康唑、红霉素或西咪替丁。",
                "看到禁忌或严重不适相关内容时，应咨询医生或药师。"
            ],
            keywords: ["风险", "禁忌", "相互作用", "说明书", "医生", "药师"]
        ),
        topic(
            id: "visit-summary",
            title: "生成复诊资料",
            summary: "个人页的复诊资料可按日期范围生成摘要和 PDF。",
            symbolName: "doc.richtext.fill",
            tint: .orange,
            steps: [
                "进入个人页，打开复诊资料。",
                "选择开始日期和结束日期。",
                "先查看关键指标和摘要预览。",
                "点生成 PDF，再预览或分享。"
            ],
            examples: [
                "复诊前选择最近 2 个月，带上忽略、稍后、剂量变化和风险提示。",
                "日期改动后需要重新生成 PDF。"
            ],
            keywords: ["复诊", "PDF", "导出", "分享", "摘要"]
        )
    ]

    static let goals: [AppHelpGoal] = [
        AppHelpGoal(
            id: "daily-use",
            title: "今天要按时处理用药",
            subtitle: "提醒、稍后、忽略、撤销和完成率",
            symbolName: "calendar.badge.checkmark",
            tint: .blue,
            topicIDs: ["mark-dose", "today-progress", "reminder-escalation", "weather-focus"]
        ),
        AppHelpGoal(
            id: "medication-setup",
            title: "补全一个药品资料",
            subtitle: "药名、照片、药盒编号、库存、疗程和说明书",
            symbolName: "pills.circle.fill",
            tint: .green,
            topicIDs: ["add-medication", "medication-photo-stock", "dose-plan", "label-import", "medication-lifecycle"]
        ),
        AppHelpGoal(
            id: "review-history",
            title: "回看历史或准备复诊",
            subtitle: "周历、月历、修正记录、趋势和复诊资料",
            symbolName: "doc.text.magnifyingglass",
            tint: .teal,
            topicIDs: ["calendar-records", "record-correction", "trend-model", "visit-summary"]
        ),
        AppHelpGoal(
            id: "risk-ai",
            title: "看懂警示并问智能体",
            subtitle: "风险对象、依据片段、归档和授权咨询",
            symbolName: "shield.lefthalf.filled",
            tint: .indigo,
            topicIDs: ["risk-review", "risk-archive", "ai-chat", "ai-photo"]
        ),
        AppHelpGoal(
            id: "privacy-health",
            title: "管理健康数据和隐私",
            subtitle: "Apple 健康、智能体授权、账号和偏好",
            symbolName: "lock.shield.fill",
            tint: .orange,
            topicIDs: ["healthkit", "ai-chat", "privacy-settings"]
        )
    ]

    static let sections: [AppHelpSection] = [
        AppHelpSection(category: today, topics: [
            quickTopics[0],
            topic(
                id: "today-progress",
                title: "今日完成率和进度反馈",
                summary: "今日处理进度会随已服用、稍后和忽略更新。",
                symbolName: "gauge.with.dots.needle.67percent",
                tint: .blue,
                steps: [
                    "每处理一条用药，今日页会更新进度。",
                    "全部处理完成后，完成反馈会更明显。",
                    "撤销后进度会随记录回退。"
                ],
                examples: [
                    "4 条待处理全部处理后，今日页会显示完成状态。",
                    "撤销一条已服用后，这条药回到待处理。"
                ],
                keywords: ["完成率", "进度", "撤销", "全部完成"]
            ),
            topic(
                id: "reminder-escalation",
                title: "推送、稍后和强提醒",
                summary: "提醒以计划时间为主，稍后不会随意打乱原计划时间线。",
                symbolName: "bell.badge.fill",
                tint: .blue,
                steps: [
                    "计划时间会先推送普通提醒。",
                    "稍后通常按原计划时间向后顺延。",
                    "距离计划时间很久时，App 会要求再次确认。",
                    "长时间未处理时，系统可记录为忽略并进入记录页。"
                ],
                examples: [
                    "8:00 的药 8:03 点稍后，会顺延到 8:30。",
                    "很早提前点稍后时，需要确认，避免时间线错乱。"
                ],
                keywords: ["提醒", "推送", "闹钟", "稍后", "忽略"]
            ),
            topic(
                id: "weather-focus",
                title: "天气与用药关注",
                summary: "今日页会结合本地药品资料和天气信号生成简短关注点。",
                symbolName: "cloud.sun.fill",
                tint: .blue,
                steps: [
                    "允许位置后，今日页可读取当前位置天气。",
                    "关注点只用于提醒核对药品保存、随身药和今日计划。",
                    "没有天气授权时，App 会根据今日计划和药品类型给出简短关注。",
                    "天气提示不会替代风险页的说明书警示。"
                ],
                examples: [
                    "高温天气时，优先核对避光、密封或冷藏要求。",
                    "干燥或有风时，人工泪液和过敏相关药品会更容易被提醒核对。"
                ],
                keywords: ["天气", "位置", "高温", "随身药", "保存"]
            )
        ]),
        AppHelpSection(category: medications, topics: [
            quickTopics[1],
            topic(
                id: "medication-photo-stock",
                title: "药盒照片、编号和库存",
                summary: "照片和编号用于帮助找到正确药盒，库存用于提示核对实物。",
                symbolName: "shippingbox.fill",
                tint: .green,
                steps: [
                    "进入药品详情，补充药盒照片。",
                    "给药盒写上清楚编号，并同步填入 App。",
                    "填写剩余量和低库存阈值。",
                    "库存估算会根据已服用记录更新。"
                ],
                examples: [
                    "把人工泪液药盒写成 B1，提醒时按 B1 和照片核对。",
                    "剩余量低于阈值时，药盒页会提示复核。"
                ],
                keywords: ["药盒", "照片", "编号", "库存", "低库存"]
            ),
            topic(
                id: "dose-plan",
                title: "修改疗程、剂量和提醒",
                summary: "药品详情可修改计划，并记录剂量从哪天开始变化。",
                symbolName: "clock.badge.checkmark.fill",
                tint: .green,
                steps: [
                    "进入药品详情，打开修改疗程与提醒。",
                    "核对剂量、单位、疗程开始和结束日期。",
                    "增加或减少每天提醒次数，必要时选择推送通知或 iPhone 闹钟。",
                    "剂量变化会写入记录页和趋势分析，用于复诊时回看。"
                ],
                examples: [
                    "医生把每日 1 片改为每日 2 片时，在生效日期处保存剂量变化。",
                    "需要更强提醒时，可把提醒方式改为 iPhone 闹钟。"
                ],
                keywords: ["剂量", "疗程", "提醒次数", "闹钟", "剂量变化"]
            ),
            topic(
                id: "label-import",
                title: "导入说明书并生成风险",
                summary: "说明书文本保存后，App 会在本地重建相关风险提醒。",
                symbolName: "doc.text.magnifyingglass",
                tint: .green,
                steps: [
                    "进入药品详情，打开导入说明书。",
                    "粘贴或识别说明书文字。",
                    "核对文字后保存。",
                    "到药品页的风险复核查看新生成或已归档的警示。"
                ],
                examples: [
                    "导入氯雷他定说明书后，风险复核会显示过敏禁忌和相互作用对象。",
                    "重新导入后，不再出现的旧风险会进入归档。"
                ],
                keywords: ["说明书", "图片识别", "导入", "风险", "警示"]
            ),
            topic(
                id: "medication-lifecycle",
                title: "归档、恢复和删除药品",
                summary: "不再服用的药品可归档；归档后才能删除，并会停用未来提醒。",
                symbolName: "archivebox.fill",
                tint: .green,
                steps: [
                    "进入药品详情，在高级操作里修改药品状态。",
                    "选择归档或服用中断后，未来待处理提醒会停用。",
                    "恢复为正在服用后，App 会重新生成未来提醒。",
                    "只有归档药品会显示删除入口，删除前必须再次确认。"
                ],
                examples: [
                    "临时停药但还要保留历史：选择服用中断。",
                    "疗程结束且不再需要：先归档，再按需删除。"
                ],
                keywords: ["归档", "恢复", "删除", "服用中断", "未来提醒"]
            )
        ]),
        AppHelpSection(category: records, topics: [
            topic(
                id: "calendar-records",
                title: "周历、月历和每日详情",
                summary: "记录页用周历看近况，用月历查历史。",
                symbolName: "calendar.badge.clock",
                tint: .teal,
                steps: [
                    "进入记录页，默认查看月历。",
                    "折叠时看本周记录，展开后看月历。",
                    "左右切换月份，点日期查看当天详情。",
                    "点具体记录可修正状态、计划时间或实际记录时间。"
                ],
                examples: [
                    "复诊前点开某一天，查看当天是否漏服或稍后。",
                    "剂量变化会在对应日期详情中出现。"
                ],
                keywords: ["记录", "周历", "月历", "日期", "修正"]
            ),
            topic(
                id: "record-correction",
                title: "修正一条服药记录",
                summary: "记录页可把状态、计划时间和实际记录时间改回真实情况。",
                symbolName: "pencil.and.list.clipboard",
                tint: .teal,
                steps: [
                    "进入记录页，点开对应日期。",
                    "选择需要修正的药品记录。",
                    "按真实情况调整状态、计划时间或实际记录时间。",
                    "保存后，趋势、日历和复诊资料会使用修正后的口径。"
                ],
                examples: [
                    "早上忘记点已服用，晚上可把实际记录时间修正为早上。",
                    "误点忽略后，可把状态修正为已服用。"
                ],
                keywords: ["修正", "记录", "实际时间", "计划时间", "状态"]
            ),
            topic(
                id: "trend-model",
                title: "用药趋势怎么看",
                summary: "趋势基于 App 内真实提醒和记录，至少一周数据更有参考价值。",
                symbolName: "waveform.path.ecg",
                tint: .teal,
                steps: [
                    "进入记录页，在日历下方打开用药趋势。",
                    "先看综合评分，再看时间稳定、忽略趋势、剂量变化和用药负担。",
                    "进入主题详情后，左右滑动曲线查看不同日期。",
                    "拖动曲线可查看当天分数、完成数量、稍后、忽略和事件点。",
                    "结合药品状态、剂量变化和 Apple 健康授权样本一起理解。",
                    "趋势会综合近 7 天记录、前一周期对比、剂量变化和授权健康样本。",
                    "它只反映 App 内提醒记录，不等同临床依从性指标。"
                ],
                examples: [
                    "连续稍后增多时，时间稳定主题会提示波动。",
                    "剂量调整后，趋势图会把它作为事件点。",
                    "高分区间也会放大显示细微变化，避免所有曲线挤在顶部。"
                ],
                keywords: ["趋势", "趋势分析", "评分", "曲线", "剂量变化"]
            ),
        ]),
        AppHelpSection(category: risks, topics: [
            quickTopics[2],
            topic(
                id: "risk-archive",
                title: "复核、归档和重新打开",
                summary: "已处理的风险不会消失，可在归档中回看。",
                symbolName: "archivebox.fill",
                tint: .indigo,
                steps: [
                    "点开警示详情。",
                    "确认已看过后，可标记已复核并归档。",
                    "归档后仍可在药品页的风险复核中查看。",
                    "需要重新关注时，点重新打开警示。"
                ],
                examples: [
                    "重新导入说明书后，旧警示可能自动归档。",
                    "复诊时仍可打开归档查看来源片段。"
                ],
                keywords: ["风险", "归档", "重新打开", "复核"]
            )
        ]),
        AppHelpSection(category: assistant, topics: [
            topic(
                id: "ai-chat",
                title: "智能体怎么用",
                summary: "可选择设备端模型或云端智能体，再决定共享范围。",
                symbolName: "stethoscope",
                tint: .purple,
                steps: [
                    "第一次进入智能体，阅读并确认使用说明。",
                    "选择设备端模型 Beta 或云端智能体。",
                    "选择允许共享的数据范围。",
                    "点快捷咨询或直接输入问题。",
                    "聊天页默认保留最近 3 轮咨询，较早内容进入归档历史。"
                ],
                examples: [
                    "使用设备端模型时，输入和本地记录默认留在这台 iPhone 上。",
                    "点今日核对，让智能体基于授权记录整理今天要留意的事项。",
                    "从风险详情跳转时，问题会自动预填。"
                ],
                keywords: ["智能体", "设备端", "云端", "授权", "共享", "聊天", "归档"]
            ),
            topic(
                id: "ai-photo",
                title: "图片咨询和说明书可读化",
                summary: "可上传药盒或说明书图片，让 App 先识别文字再整理问题。",
                symbolName: "photo.on.rectangle",
                tint: .purple,
                steps: [
                    "在智能体点图片按钮。",
                    "选择药盒、药品或说明书图片。",
                    "确认识别出的文字和问题。",
                    "发送后查看解释，末尾会保留模型可能出错的提醒。"
                ],
                examples: [
                    "拍药盒正面，询问如何补全药名、规格和提醒。",
                    "拍说明书片段，询问哪些词需要复诊时核对。"
                ],
                keywords: ["智能体", "图片", "药盒", "说明书", "识别"]
            )
        ]),
        AppHelpSection(category: profile, topics: [
            quickTopics[3],
            topic(
                id: "healthkit",
                title: "Apple 健康有什么用",
                summary: "授权后，生命体征样本可作为趋势和复诊资料的背景信号。",
                symbolName: "heart.text.square.fill",
                tint: .orange,
                steps: [
                    "进入个人页，打开 Apple 健康。",
                    "按系统弹窗选择允许读取的健康类型。",
                    "返回 App 查看覆盖天数、样本数和指标摘要。",
                    "这些信号只作为趋势背景，不自动判断药物导致异常。"
                ],
                examples: [
                    "近期心率和血压样本可出现在用药趋势的健康信号摘要中。",
                    "复诊资料会把授权样本作为沟通背景。"
                ],
                keywords: ["Apple 健康", "心率", "血压", "血氧", "体温"]
            ),
            topic(
                id: "privacy-settings",
                title: "账号、隐私和偏好",
                summary: "用药记录默认在本机，账号和同步属于后续增强能力。",
                symbolName: "lock.shield.fill",
                tint: .orange,
                steps: [
                    "个人页可查看账号、医疗智能体授权和应用设置。",
                    "不登录也可以继续使用提醒、药品和记录。",
                    "医疗智能体授权可随时撤销。",
                    "偏好设置可调整外观、动效和数据相关选项。"
                ],
                examples: [
                    "觉得动画太多时，可降低动效。",
                    "不想继续共享给智能体时，到医疗智能体授权页撤销。"
                ],
                keywords: ["个人", "设置", "隐私", "账号", "授权", "动效"]
            )
        ])
    ]

    private static let tutorialTopicIDs: Set<String> = [
        "mark-dose",
        "add-medication",
        "visit-summary",
        "today-progress",
        "reminder-escalation",
        "medication-photo-stock",
        "dose-plan",
        "label-import",
        "medication-lifecycle",
        "calendar-records",
        "record-correction",
        "risk-archive",
        "ai-chat",
        "ai-photo",
        "privacy-settings"
    ]

    private static let explanationTopicIDs: Set<String> = [
        "today-progress",
        "reminder-escalation",
        "weather-focus",
        "medication-photo-stock",
        "label-import",
        "medication-lifecycle",
        "trend-model",
        "risk-review",
        "visit-summary",
        "ai-chat",
        "healthkit",
        "privacy-settings"
    ]

    private static var allTopics: [AppHelpTopic] {
        uniqueTopics(sections.flatMap(\.topics))
    }

    static var tutorialGoalGroups: [AppHelpGoalTopicGroup] {
        goals.compactMap { goal in
            let topics = topics(for: goal, mode: .tutorial)
            guard !topics.isEmpty else {
                return nil
            }
            return AppHelpGoalTopicGroup(goal: goal, topics: topics)
        }
    }

    static func topics(for mode: AppHelpMode) -> [AppHelpTopic] {
        let topicIDs = mode == .tutorial ? tutorialTopicIDs : explanationTopicIDs
        return allTopics.filter { topicIDs.contains($0.id) }
    }

    static func sections(for mode: AppHelpMode) -> [AppHelpSection] {
        let topicIDs = mode == .tutorial ? tutorialTopicIDs : explanationTopicIDs
        return sections.compactMap { section in
            let topics = uniqueTopics(section.topics).filter { topicIDs.contains($0.id) }
            guard !topics.isEmpty else {
                return nil
            }
            return AppHelpSection(category: section.category, topics: topics)
        }
    }

    private static func topic(
        id: String,
        title: String,
        summary: String,
        symbolName: String,
        tint: Color,
        steps: [String],
        examples: [String],
        keywords: [String]
    ) -> AppHelpTopic {
        AppHelpTopic(
            id: id,
            title: title,
            summary: summary,
            symbolName: symbolName,
            tint: tint,
            steps: steps,
            examples: examples,
            keywords: keywords
        )
    }

    static func topics(for goal: AppHelpGoal, mode: AppHelpMode? = nil) -> [AppHelpTopic] {
        let modeTopicIDs: Set<String>? = mode.map { $0 == .tutorial ? tutorialTopicIDs : explanationTopicIDs }
        return goal.topicIDs.compactMap { topicID in
            guard modeTopicIDs?.contains(topicID) ?? true else {
                return nil
            }
            return allTopics.first { $0.id == topicID }
        }
    }

    private static func uniqueTopics(_ topics: [AppHelpTopic]) -> [AppHelpTopic] {
        var seenTopicIDs = Set<String>()
        var result: [AppHelpTopic] = []
        for topic in topics where seenTopicIDs.insert(topic.id).inserted {
            result.append(topic)
        }
        return result
    }
}

private struct AppHelpGoalHeader: View {
    let goal: AppHelpGoal
    let count: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(goal.tint.opacity(0.14))
                Image(systemName: goal.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(goal.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.headline)
                Text(goal.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AppHelpSectionHeader: View {
    let category: AppHelpCategory
    let count: Int
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(category.tint.opacity(0.14))
                Image(systemName: category.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(category.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                Text(category.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AppHelpTopicRow: View {
    let topic: AppHelpTopic
    let mode: AppHelpMode

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(topic.tint.opacity(0.12))
                Image(systemName: topic.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(topic.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                    Text(mode.rowCaption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(topic.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(topic.tint.opacity(0.10), in: Capsule())
                }
                Text(mode == .tutorial ? topic.tutorialPreview : topic.explanationPreview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AppHelpTopicDetailView: View {
    let topic: AppHelpTopic
    let preferredMode: AppHelpMode

    private var explanationBullets: [String] {
        AppHelpTopicDetailContent.explanationBullets(for: topic)
    }

    private var uiExamples: [AppHelpUIExample] {
        AppHelpTopicDetailContent.uiExamples(for: topic)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(topic.tint.opacity(0.14))
                        Image(systemName: topic.symbolName)
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(topic.tint)
                    }
                    .frame(width: 62, height: 62)
                    Text(topic.title)
                        .font(.title2.weight(.semibold))
                    Text(topic.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("功能解释") {
                ForEach(explanationBullets, id: \.self) { bullet in
                    AppHelpExplanationRow(text: bullet, tint: topic.tint)
                }
            }

            Section("教程步骤") {
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                    AppHelpStepRow(index: index + 1, text: step, tint: topic.tint)
                }
            }

            Section("界面元素示例") {
                ForEach(uiExamples) { example in
                    AppHelpUIExampleCard(example: example)
                }
            }

            Section("场景示范") {
                ForEach(topic.examples, id: \.self) { example in
                    Label(example, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppHelpExplanationRow: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct AppHelpStepRow: View {
    let index: Int
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

private struct AppHelpUIExample: Identifiable {
    let id: String
    let title: String
    let detail: String
    let sampleText: String
    let symbolName: String
    let tint: Color
}

private struct AppHelpUIExampleCard: View {
    let example: AppHelpUIExample

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: example.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(example.tint)
                .frame(width: 36, height: 36)
                .background(example.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(example.title)
                    .font(.subheadline.weight(.semibold))
                Text(example.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(example.sampleText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(example.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(example.tint.opacity(0.10), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private enum AppHelpTopicDetailContent {
    static func explanationBullets(for topic: AppHelpTopic) -> [String] {
        switch topic.id {
        case "mark-dose":
            return [
                "今日页只处理今天这一轮用药，不会改变长期疗程。",
                "已服用、稍后、忽略都会写入记录，后续可在日历和趋势里回看。"
            ]
        case "add-medication":
            return [
                "药品资料是提醒、风险、记录和复诊资料的基础。",
                "手动添加优先保证真实可用，图片、药盒编号和库存可以稍后补齐。"
            ]
        case "risk-review":
            return [
                "风险页先按药品聚合，再按相互作用、饮食生活方式、病症症状等类别辅助定位。",
                "风险提醒只提示需要核对的对象和依据片段，不替代医生或药师判断。"
            ]
        case "trend-model":
            return [
                "趋势曲线展示记录变化，不评价疗效，也不推断病情好坏。",
                "高分区间会放大细微波动，方便观察稍后、忽略、剂量变化和健康样本的时间关系。"
            ]
        case "healthkit":
            return [
                "Apple 健康样本只作为趋势和复诊资料的背景信号。",
                "App 不根据生命体征自动诊断，也不自动建议调整药物。"
            ]
        case "ai-chat":
            return [
                "医疗智能体只有在用户授权后读取所选用药数据。",
                "快捷问题会整理本机用药信息；聊天页只显示问题和回答。"
            ]
        case "visit-summary":
            return [
                "复诊资料把记录、风险、剂量变化和健康背景整理成沟通材料。",
                "日期范围改变后，应重新生成 PDF，避免沿用旧摘要。"
            ]
        default:
            return [topic.summary]
        }
    }

    static func uiExamples(for topic: AppHelpTopic) -> [AppHelpUIExample] {
        switch topic.id {
        case "mark-dose":
            return [
                example("today-taken", "今日待处理按钮", "处理药物时使用纯文字按钮，避免图标误读。", "已服用", "checkmark.circle.fill", .blue),
                example("today-undo", "今日已处理折叠栏", "误操作后展开已处理列表，点撤销回到待处理。", "撤销", "arrow.uturn.backward.circle.fill", .orange)
            ]
        case "add-medication":
            return [
                example("add-plus", "药品页加号", "右上角加号打开录入方式。", "手动添加", "plus.circle.fill", .green),
                example("box-number", "药盒编号", "药盒上写编号，再填入药品详情。", "A1", "shippingbox.fill", .green)
            ]
        case "risk-review":
            return [
                example("risk-card", "风险卡片", "先看药品名，再看具体需核对对象。", "禁忌", "shield.lefthalf.filled", .indigo),
                example("risk-ai", "智能体解释入口", "从风险详情跳转时会预填相关问题。", "解释这条风险", "stethoscope", .purple)
            ]
        case "trend-model":
            return [
                example("trend-chart", "趋势曲线", "左右滑动曲线，拖动查看某一天读数。", "2026年6月10日 · 100%", "waveform.path.ecg", .teal),
                example("trend-event", "事件标记", "剂量变化和健康样本会显示为事件点。", "剂量变化", "arrow.triangle.2.circlepath", .purple)
            ]
        case "visit-summary":
            return [
                example("pdf-range", "日期范围", "先选复诊需要的时间段。", "近 2 个月", "calendar.badge.clock", .orange),
                example("pdf-action", "生成 PDF", "日期或记录变化后重新生成。", "生成复诊资料", "doc.richtext.fill", .orange)
            ]
        case "ai-chat", "ai-photo":
            return [
                example("ai-quick", "快捷咨询", "可展开横向滑动的问题卡片。", "今日重点核对", "sparkles", .purple),
                example("ai-input", "聊天输入栏", "手动输入或选择图片后再发送。", "询问用药记录…", "paperplane.circle.fill", .blue)
            ]
        default:
            return [
                example("\(topic.id)-main", topic.title, topic.summary, topic.keywords.first ?? "查看详情", topic.symbolName, topic.tint)
            ]
        }
    }

    private static func example(
        _ id: String,
        _ title: String,
        _ detail: String,
        _ sampleText: String,
        _ symbolName: String,
        _ tint: Color
    ) -> AppHelpUIExample {
        AppHelpUIExample(
            id: id,
            title: title,
            detail: detail,
            sampleText: sampleText,
            symbolName: symbolName,
            tint: tint
        )
    }
}
