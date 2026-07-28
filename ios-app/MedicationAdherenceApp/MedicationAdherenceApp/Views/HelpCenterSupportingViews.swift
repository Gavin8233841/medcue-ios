import SwiftUI

struct AppHelpGoalHeader: View {
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

struct AppHelpSectionHeader: View {
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

struct AppHelpTopicRow: View {
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

struct AppHelpTopicDetailView: View {
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

struct AppHelpUIExample: Identifiable {
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

enum AppHelpTopicDetailContent {
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
