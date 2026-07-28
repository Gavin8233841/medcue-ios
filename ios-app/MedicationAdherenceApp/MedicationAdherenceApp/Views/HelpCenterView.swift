import SwiftData
import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedMode: AppHelpMode = .tutorial
    @State private var showingProductTour = false
    @State private var isShowingDemoModeError = false
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
                FirstLaunchSetupView(
                    finish: { _ in
                        showingProductTour = false
                    },
                    startDemoMode: {
                        Task {
                            await startDebugDemoMode()
                        }
                    }
                )
            }
            .alert("演示模式未能启动", isPresented: $isShowingDemoModeError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("演示数据未能保存，请重新打开 App 后再试。")
            }
        }
    }

    @MainActor
    private func startDebugDemoMode() async {
        #if DEBUG
        do {
            try await DebugDemoModeLauncher.rebuildAndExit(in: modelContext)
        } catch {
            showingProductTour = false
            isShowingDemoModeError = true
        }
        #endif
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
