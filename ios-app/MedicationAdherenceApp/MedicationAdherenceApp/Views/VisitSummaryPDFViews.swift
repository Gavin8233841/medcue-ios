import AuthenticationServices
import MedicationAdherenceCore
import OSLog
import QuickLook
import SwiftData
import SwiftUI
import UIKit

struct VisitSummaryPDFReport {
    let medications: [VisitSummaryMedicationValue]
    let tasks: [VisitSummaryTaskValue]
    let doseChanges: [VisitSummaryDoseChangeValue]
    let riskCards: [VisitSummaryRiskValue]
    let trendDashboard: MedicationTrendDashboard
    let healthSignals: [HealthSignalSample]
    let startDate: Date
    let endDate: Date
    let generatedAt: Date

    init(payload: VisitSummaryExportPayload) {
        medications = payload.medications
        tasks = payload.tasks
        doseChanges = payload.doseChanges
        riskCards = payload.riskCards
        trendDashboard = payload.trendDashboard
        healthSignals = payload.healthSignals
        startDate = payload.startDate
        endDate = payload.endDate
        generatedAt = payload.generatedAt
    }

    private static let primaryText = UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
    private static let secondaryText = UIColor(red: 0.42, green: 0.46, blue: 0.54, alpha: 1)
    private static let mutedText = UIColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1)
    private static let dividerColor = UIColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
    private static let neutralPanel = UIColor(red: 0.96, green: 0.975, blue: 0.995, alpha: 1)

    private var completedCount: Int {
        tasks.filter(\.isTaken).count
    }

    private var skippedCount: Int {
        tasks.filter(\.isSkipped).count
    }

    private var delayedCount: Int {
        tasks.filter(\.isDelayed).count
    }

    private var completionRate: Double {
        tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count)
    }

    private var adherenceInsight: AdherenceInsight {
        AdherenceInsightBuilder().build(
            scheduledDoses: tasks.map(\.coreScheduledDose),
            events: tasks.compactMap(\.coreDoseEvent),
            timeZone: TimeZone.current,
            now: generatedAt
        )
    }

    private var recentDoseChanges: [VisitSummaryDoseChangeValue] {
        return doseChanges
            .sorted { $0.effectiveFrom > $1.effectiveFrom }
    }

    private var activeProfessionalRiskCards: [VisitSummaryRiskValue] {
        riskCards.filter { $0.requiresProfessionalReview && $0.isActive }
    }

    private var communicationCount: Int {
        skippedCount + delayedCount + activeProfessionalRiskCards.count
    }

    private var healthSignalDayCount: Int {
        let calendar = Calendar.current
        return Set(healthSignals.map { calendar.startOfDay(for: $0.measuredAt) }).count
    }

    private var healthSignalMetricCount: Int {
        Set(healthSignals.map(\.kind)).count
    }

    private var rangeText: String {
        VisitSummaryDateRange.displayText(startDate: startDate, endDate: endDate)
    }

    func draw(in context: UIGraphicsPDFRendererContext, pageBounds: CGRect) {
        context.beginPage()
        drawSummaryPage(in: pageBounds)
        context.beginPage()
        drawTimelinePage(in: pageBounds)
    }

    private func drawSummaryPage(in pageBounds: CGRect) {
        let margin: CGFloat = 36
        let contentWidth = pageBounds.width - margin * 2
        let accent = UIColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1)
        let green = UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        let orange = UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        let red = UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        let softBackground = UIColor(red: 0.96, green: 0.975, blue: 0.995, alpha: 1)
        var y = margin

        drawHeader(x: margin, y: y, width: contentWidth, accent: accent)
        y += 82

        let metricWidth = (contentWidth - 24) / 4
        let metrics = [
            ("药品", "\(medications.count)", accent),
            ("完成率", "\(Int((completionRate * 100).rounded()))%", green),
            ("已服用", "\(completedCount)", green),
            ("需沟通", "\(communicationCount)", orange)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = margin + CGFloat(index) * (metricWidth + 8)
            drawMetricCard(title: metric.0, value: metric.1, color: metric.2, rect: CGRect(x: x, y: y, width: metricWidth, height: 62))
        }
        y += 78

        drawSectionTitle("所选范围执行概览", x: margin, y: y)
        y += 26
        drawStackedAdherenceBar(
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 12),
            completed: completedCount,
            delayed: delayedCount,
            skipped: skippedCount,
            total: tasks.count,
            completedColor: green,
            delayedColor: accent,
            skippedColor: orange
        )
        y += 20
        drawAdherenceLegend(x: margin, y: y, completedColor: green, delayedColor: accent, skippedColor: orange)
        y += 24
        drawMultilineText(
            "\(rangeText) 期间计划 \(tasks.count) 次，已服用 \(completedCount) 次，稍后 \(delayedCount) 次，已忽略 \(skippedCount) 次。",
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 34),
            font: .systemFont(ofSize: 10),
            color: Self.secondaryText
        )
        y += 48

        let columnWidth = (contentWidth - 12) / 2
        drawTrendPanel(rect: CGRect(x: margin, y: y, width: columnWidth, height: 92), accent: accent)
        drawDoseChangePanel(rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 92), accent: UIColor.systemPurple)
        y += 110

        drawSectionTitle("当前药品", x: margin, y: y)
        y += 24
        let medicationRows = Array(medications.prefix(4))
        for medication in medicationRows {
            let relatedTasks = tasks.filter { $0.medicationID == medication.id }
            let taken = relatedTasks.filter(\.isTaken).count
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 34), fill: softBackground)
            drawText(medication.displayName, rect: CGRect(x: margin + 14, y: y + 7, width: 160, height: 18), font: .systemFont(ofSize: 11, weight: .semibold))
            drawText([medication.strength, medication.form].filter { !$0.isEmpty }.joined(separator: " · "), rect: CGRect(x: margin + 180, y: y + 8, width: 190, height: 16), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText("\(taken) / \(relatedTasks.count) 次", rect: CGRect(x: margin + contentWidth - 92, y: y + 8, width: 78, height: 16), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: green, alignment: .right)
            y += 39
        }
        if medications.count > medicationRows.count {
            drawBodyText("另有 \(medications.count - medicationRows.count) 个药品未在本页展开。", rect: CGRect(x: margin, y: y, width: contentWidth, height: 20))
            y += 28
        }

        drawSectionTitle("异常节点与风险复核", x: margin, y: y)
        y += 24
        let exceptions = tasks
            .filter { $0.isSkipped || $0.isDelayed }
            .sorted { $0.effectiveAdherenceDate > $1.effectiveAdherenceDate }
        let importantRiskCards = activeProfessionalRiskCards.prefix(2)
        drawExceptionPanel(rect: CGRect(x: margin, y: y, width: columnWidth, height: 112), exceptions: Array(exceptions.prefix(4)), accent: accent, orange: orange)
        drawRiskPanel(rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 112), risks: Array(importantRiskCards), red: red)

        drawFooter(x: margin, y: pageBounds.height - 54, width: contentWidth)
    }

    private func drawTimelinePage(in pageBounds: CGRect) {
        let margin: CGFloat = 36
        let contentWidth = pageBounds.width - margin * 2
        let accent = UIColor(red: 0.13, green: 0.38, blue: 0.92, alpha: 1)
        let green = UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        let orange = UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        let red = UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        let purple = UIColor(red: 0.46, green: 0.26, blue: 0.82, alpha: 1)
        var y = margin

        drawHeader(x: margin, y: y, width: contentWidth, accent: accent)
        y += 82

        drawSectionTitle("连续达标与复诊沟通重点", x: margin, y: y)
        y += 24
        let insight = adherenceInsight
        let streakValue = insight.currentStreakDays > 0 ? "\(insight.currentStreakDays) 天" : "\(insight.longestStreakDays) 天"
        let streakTitle = insight.currentStreakDays > 0 ? "当前连续达标" : "历史最长达标"
        let columnWidth = (contentWidth - 12) / 2
        drawMetricCard(title: streakTitle, value: streakValue, color: green, rect: CGRect(x: margin, y: y, width: columnWidth, height: 62))
        drawMetricCard(title: "范围内需沟通", value: "\(communicationCount)", color: orange, rect: CGRect(x: margin + columnWidth + 12, y: y, width: columnWidth, height: 62))
        y += 78
        drawMultilineText(
            insight.message,
            rect: CGRect(x: margin, y: y, width: contentWidth, height: 36),
            font: .systemFont(ofSize: 10),
            color: Self.secondaryText
        )
        y += 54

        drawSectionTitle("时间线", x: margin, y: y)
        y += 26
        let events = timelineEvents(accent: accent, green: green, orange: orange, red: red, purple: purple)
        if events.isEmpty {
            drawRoundedPanel(rect: CGRect(x: margin, y: y, width: contentWidth, height: 54), fill: Self.neutralPanel)
            drawMultilineText(
                "所选日期范围内没有需要优先沟通的异常节点、剂量变化或风险复核记录。",
                rect: CGRect(x: margin + 14, y: y + 14, width: contentWidth - 28, height: 28),
                font: .systemFont(ofSize: 10),
                color: Self.secondaryText
            )
            y += 72
        } else {
            for event in events.prefix(9) {
                drawTimelineEvent(event, x: margin, y: y, width: contentWidth)
                y += 48
            }
            if events.count > 9 {
                drawBodyText("另有 \(events.count - 9) 条记录未在本页展开。", rect: CGRect(x: margin + 18, y: y, width: contentWidth - 36, height: 18))
                y += 26
            }
        }

        let lowerTop = min(y + 4, pageBounds.height - 190)
        drawSectionTitle("医生快速查看", x: margin, y: lowerTop)
        let quickTop = lowerTop + 24
        drawDoctorChecklist(rect: CGRect(x: margin, y: quickTop, width: columnWidth, height: 116), accent: accent, orange: orange, red: red)
        drawMedicationContextPanel(rect: CGRect(x: margin + columnWidth + 12, y: quickTop, width: columnWidth, height: 116), green: green, purple: purple)

        drawFooter(x: margin, y: pageBounds.height - 54, width: contentWidth)
    }

    private func drawStackedAdherenceBar(
        rect: CGRect,
        completed: Int,
        delayed: Int,
        skipped: Int,
        total: Int,
        completedColor: UIColor,
        delayedColor: UIColor,
        skippedColor: UIColor
    ) {
        let background = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        Self.dividerColor.setFill()
        background.fill()

        guard total > 0 else {
            return
        }

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        background.addClip()
        defer { context.restoreGState() }

        let segments: [(Int, UIColor)] = [
            (completed, completedColor),
            (delayed, delayedColor),
            (skipped, skippedColor)
        ].filter { $0.0 > 0 }

        var currentX = rect.minX
        for (count, color) in segments {
            let width = rect.width * CGFloat(count) / CGFloat(total)
            let segmentRect = CGRect(x: currentX, y: rect.minY, width: width, height: rect.height)
            color.setFill()
            UIBezierPath(rect: segmentRect).fill()
            currentX += width
        }

        Self.dividerColor.setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    private func drawAdherenceLegend(x: CGFloat, y: CGFloat, completedColor: UIColor, delayedColor: UIColor, skippedColor: UIColor) {
        drawLegendItem("已服用 \(completedCount)", x: x, y: y, color: completedColor)
        drawLegendItem("稍后 \(delayedCount)", x: x + 126, y: y, color: delayedColor)
        drawLegendItem("已忽略 \(skippedCount)", x: x + 238, y: y, color: skippedColor)
    }

    private func drawLegendItem(_ title: String, x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: y + 4, width: 7, height: 7)).fill()
        drawText(title, rect: CGRect(x: x + 12, y: y, width: 100, height: 16), font: .systemFont(ofSize: 9), color: Self.secondaryText)
    }

    private func drawTrendPanel(rect: CGRect, accent: UIColor) {
        let trendColor = trendReportColor(trendDashboard.direction, fallback: accent)
        drawRoundedPanel(rect: rect, fill: trendColor.withAlphaComponent(0.10))
        drawText("用药趋势", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: trendColor)
        drawText("综合 \(pdfPercentage(trendDashboard.overallScore))% · \(trendReportTitle(trendDashboard.direction))", rect: CGRect(x: rect.minX + 12, y: rect.minY + 29, width: rect.width - 24, height: 18), font: .monospacedDigitSystemFont(ofSize: 13, weight: .bold))
        drawProgressBar(rect: CGRect(x: rect.minX + 12, y: rect.minY + 52, width: rect.width - 24, height: 7), progress: trendDashboard.overallScore, background: Self.dividerColor, fill: trendColor)

        let highlightedMetric = trendDashboard.metrics.first { $0.direction == .declining || $0.direction == .fluctuating }
            ?? trendDashboard.metrics.first
        let detail = highlightedMetric.map { "\($0.title) \(pdfPercentage($0.score))%：\($0.summary)" } ?? trendDashboard.summary
        drawMultilineText(detail, rect: CGRect(x: rect.minX + 12, y: rect.minY + 64, width: rect.width - 24, height: 24), font: .systemFont(ofSize: 8.5), color: Self.secondaryText)
    }

    private func drawDoseChangePanel(rect: CGRect, accent: UIColor) {
        drawRoundedPanel(rect: rect, fill: accent.withAlphaComponent(0.10))
        drawText("剂量变化", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: accent)
        let changes = Array(recentDoseChanges.prefix(2))
        if changes.isEmpty {
            drawMultilineText("所选范围内没有记录剂量变化。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 50), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 29
        for change in changes {
            let medicationName = medications.first { $0.id == change.medicationID }?.displayName ?? "待核对药品名称"
            let previous = change.previousDoseValue.map { doseAmountText(value: $0, unit: change.previousDoseUnit) } ?? "未记录"
            let current = doseAmountText(value: change.newDoseValue, unit: change.newDoseUnit)
            drawText(medicationName, rect: CGRect(x: rect.minX + 12, y: rowY, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 9, weight: .semibold))
            drawText("\(previous) 调整为 \(current)", rect: CGRect(x: rect.minX + 12, y: rowY + 13, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 8.5), color: Self.secondaryText)
            drawText(pdfDoseChangePeriodText(change: change), rect: CGRect(x: rect.minX + 12, y: rowY + 26, width: rect.width - 24, height: 13), font: .systemFont(ofSize: 8), color: Self.secondaryText)
            rowY += 39
        }
    }

    private func drawExceptionPanel(rect: CGRect, exceptions: [VisitSummaryTaskValue], accent: UIColor, orange: UIColor) {
        drawRoundedPanel(rect: rect, fill: Self.neutralPanel)
        drawText("异常节点", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold))
        guard !exceptions.isEmpty else {
            drawMultilineText("所选范围内没有需要优先沟通的忽略或稍后记录。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: 32), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 32
        for task in exceptions {
            let medicationName = medications.first { $0.id == task.medicationID }?.displayName ?? "待核对药品名称"
            let action = task.isSkipped ? "已忽略" : "稍后提醒"
            let displayDate = task.effectiveAdherenceDate
            drawTimelineDot(x: rect.minX + 13, y: rowY + 6, color: task.isSkipped ? orange : accent)
            drawText("\(AppFormatters.day.string(from: displayDate)) \(AppFormatters.time.string(from: displayDate))", rect: CGRect(x: rect.minX + 28, y: rowY, width: 92, height: 14), font: .monospacedDigitSystemFont(ofSize: 8, weight: .medium), color: Self.secondaryText)
            drawText("\(medicationName) · \(action)", rect: CGRect(x: rect.minX + 122, y: rowY, width: rect.width - 134, height: 14), font: .systemFont(ofSize: 8.5, weight: .semibold))
            rowY += 20
        }
    }

    private func drawRiskPanel(rect: CGRect, risks: [VisitSummaryRiskValue], red: UIColor) {
        drawRoundedPanel(rect: rect, fill: red.withAlphaComponent(0.08))
        drawText("风险复核", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: red)
        guard !risks.isEmpty else {
            drawMultilineText("暂无需要优先沟通的风险提醒。", rect: CGRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: 32), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            return
        }

        var rowY = rect.minY + 31
        for card in risks {
            let medicationName = medications.first { $0.id == card.medicationID }?.displayName ?? "待核对药品名称"
            let focus = pdfRiskFocusSummary(for: card)
            drawText(medicationName, rect: CGRect(x: rect.minX + 12, y: rowY, width: 88, height: 13), font: .systemFont(ofSize: 8.5, weight: .semibold), color: red)
            drawText(pdfRiskDisplayTitle(for: card, limit: 36), rect: CGRect(x: rect.minX + 104, y: rowY, width: rect.width - 116, height: 13), font: .systemFont(ofSize: 8.5, weight: .semibold))
            drawMultilineText(focus, rect: CGRect(x: rect.minX + 12, y: rowY + 14, width: rect.width - 24, height: 24), font: .systemFont(ofSize: 8), color: Self.secondaryText)
            rowY += 38
        }
    }

    private struct PDFTimelineEvent {
        let date: Date
        let title: String
        let detail: String
        let color: UIColor
    }

    private func timelineEvents(
        accent: UIColor,
        green: UIColor,
        orange: UIColor,
        red: UIColor,
        purple: UIColor
    ) -> [PDFTimelineEvent] {
        var events: [PDFTimelineEvent] = []

        let exceptionEvents = tasks
            .filter { $0.isSkipped || $0.isDelayed }
            .sorted { $0.effectiveAdherenceDate > $1.effectiveAdherenceDate }
            .prefix(8)
            .map { task -> PDFTimelineEvent in
                let medicationName = medications.first { $0.id == task.medicationID }?.displayName ?? "待核对药品名称"
                let action = task.isSkipped ? "已忽略" : "稍后提醒"
                let doseText = "\(task.doseValue.formatted()) \(localizedMedicationUnit(task.doseUnit))"
                let reason = pdfRecordReason(from: task.reason).map { " · \($0)" } ?? ""
                return PDFTimelineEvent(
                    date: task.effectiveAdherenceDate,
                    title: "\(medicationName) · \(action)",
                    detail: "\(AppFormatters.day.string(from: task.effectiveAdherenceDate)) \(AppFormatters.time.string(from: task.effectiveAdherenceDate)) · \(doseText)\(reason)",
                    color: task.isSkipped ? orange : accent
                )
            }
        events.append(contentsOf: exceptionEvents)

        let doseEvents = recentDoseChanges.prefix(4).map { change -> PDFTimelineEvent in
            let medicationName = medications.first { $0.id == change.medicationID }?.displayName ?? "待核对药品名称"
            let previous = change.previousDoseValue.map { doseAmountText(value: $0, unit: change.previousDoseUnit) } ?? "未记录"
            let current = doseAmountText(value: change.newDoseValue, unit: change.newDoseUnit)
            return PDFTimelineEvent(
                date: change.effectiveFrom,
                title: "\(medicationName) · 剂量变化",
                detail: "\(previous) 调整为 \(current)；\(pdfDoseChangePeriodText(change: change))",
                color: purple
            )
        }
        events.append(contentsOf: doseEvents)

        let riskEvents = riskCards
            .filter {
                $0.requiresProfessionalReview
                    && $0.isActive
                    && $0.lastDetectedAt >= startDate
                    && $0.lastDetectedAt <= endDate
            }
            .sorted {
                if $0.displayPriority != $1.displayPriority {
                    return $0.displayPriority < $1.displayPriority
                }
                return $0.lastDetectedAt > $1.lastDetectedAt
            }
            .prefix(5)
            .map { card -> PDFTimelineEvent in
                let medicationName = medications.first { $0.id == card.medicationID }?.displayName ?? "待核对药品名称"
                return PDFTimelineEvent(
                    date: card.lastDetectedAt,
                    title: "\(medicationName) · \(pdfRiskDisplayTitle(for: card, limit: 42))",
                    detail: pdfRiskFocusSummary(for: card, limit: 84),
                    color: card.isHighSeverity ? red : orange
                )
            }
        events.append(contentsOf: riskEvents)

        return events.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.title < rhs.title
        }
    }

    private func drawTimelineEvent(_ event: PDFTimelineEvent, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawTimelineDot(x: x + 5, y: y + 13, color: event.color)
        drawText(
            AppFormatters.day.string(from: event.date),
            rect: CGRect(x: x + 24, y: y + 4, width: 78, height: 15),
            font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            color: Self.secondaryText
        )
        drawText(
            event.title,
            rect: CGRect(x: x + 106, y: y + 3, width: width - 118, height: 16),
            font: .systemFont(ofSize: 10, weight: .semibold)
        )
        drawMultilineText(
            event.detail,
            rect: CGRect(x: x + 106, y: y + 20, width: width - 118, height: 24),
            font: .systemFont(ofSize: 8.5),
            color: Self.secondaryText
        )
        Self.dividerColor.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: x + 9, y: y + 27))
        line.addLine(to: CGPoint(x: x + 9, y: y + 47))
        line.lineWidth = 1
        line.stroke()
    }

    private func drawDoctorChecklist(rect: CGRect, accent: UIColor, orange: UIColor, red: UIColor) {
        drawRoundedPanel(rect: rect, fill: Self.neutralPanel)
        drawText("需要沟通", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: accent)

        let activeRiskCount = riskCards.filter { $0.requiresProfessionalReview && $0.isActive }.count
        let rows = [
            ("忽略记录", "\(skippedCount) 次", skippedCount > 0 ? orange : Self.secondaryText),
            ("稍后记录", "\(delayedCount) 次", delayedCount > 0 ? accent : Self.secondaryText),
            ("风险复核", "\(activeRiskCount) 条", activeRiskCount > 0 ? red : Self.secondaryText)
        ]
        var rowY = rect.minY + 32
        for row in rows {
            drawTimelineDot(x: rect.minX + 13, y: rowY + 4, color: row.2)
            drawText(row.0, rect: CGRect(x: rect.minX + 28, y: rowY, width: 88, height: 14), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText(row.1, rect: CGRect(x: rect.minX + rect.width - 82, y: rowY, width: 68, height: 14), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: row.2, alignment: .right)
            rowY += 22
        }
    }

    private func drawMedicationContextPanel(rect: CGRect, green: UIColor, purple: UIColor) {
        drawRoundedPanel(rect: rect, fill: purple.withAlphaComponent(0.09))
        drawText("方案与健康", rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: purple)

        let trackedMedicationCount = medications.filter { !$0.isArchived }.count
        let rows: [(String, String, UIColor)] = [
            ("剂量变化", "\(recentDoseChanges.count) 次", purple),
            ("管理药品", "\(trackedMedicationCount) 个", green),
            ("健康信号", healthSignals.isEmpty ? "待样本" : "\(healthSignalDayCount) 天 · \(healthSignals.count) 条", UIColor.systemTeal)
        ]
        var rowY = rect.minY + 32
        for row in rows {
            drawTimelineDot(x: rect.minX + 13, y: rowY + 4, color: row.2)
            drawText(row.0, rect: CGRect(x: rect.minX + 28, y: rowY, width: 74, height: 14), font: .systemFont(ofSize: 9), color: Self.secondaryText)
            drawText(row.1, rect: CGRect(x: rect.minX + 104, y: rowY, width: rect.width - 116, height: 14), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: row.2, alignment: .right)
            rowY += 22
        }

        if healthSignalMetricCount > 0 {
            drawText("纳入 \(healthSignalMetricCount) 类指标", rect: CGRect(x: rect.minX + 28, y: rect.maxY - 20, width: rect.width - 40, height: 12), font: .systemFont(ofSize: 8), color: Self.secondaryText)
        }
    }

    private func doseAmountText(value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) \(localizedMedicationUnit(unit))"
    }

    private func trimmedPDFText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请咨询医生或药师", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private func pdfRecordReason(from rawText: String) -> String? {
        let displayParts = rawText
            .components(separatedBy: "；")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in
                !part.isEmpty
                    && !part.contains("用户撤销后等待确认")
                    && !part.contains("同一剂量重复提醒已随")
                    && !part.contains("未来提醒已停用")
            }
        guard !displayParts.isEmpty else {
            return nil
        }
        return displayParts.joined(separator: "；")
    }

    private func pdfRiskFocusSummary(for card: VisitSummaryRiskValue, limit: Int = 72) -> String {
        if let focus = pdfRiskConcreteFocusText(for: card, limit: limit) {
            return focus
        }
        let message = trimmedPDFText(card.message, limit: limit)
        guard !message.isEmpty else {
            return "需补充说明书或向医生或药师确认具体对象。"
        }
        return message
    }

    private func pdfRiskDisplayTitle(for card: VisitSummaryRiskValue, limit: Int) -> String {
        let rawTitle = trimmedPDFText(card.title, limit: limit)
        guard pdfIsGenericRiskFocus(rawTitle) || rawTitle == "警示信息" || rawTitle == "注意事项" else {
            return rawTitle.isEmpty ? pdfRiskCategoryTitle(for: card) : rawTitle
        }
        let category = pdfIsContraindicationRisk(card) ? "禁忌或慎用" : pdfRiskCategoryTitle(for: card)
        guard let focus = pdfRiskConcreteFocusText(for: card, limit: limit),
              !focus.isEmpty
        else {
            return category
        }
        return trimmedPDFText("\(category)：\(pdfRiskShareFocusText(focus))", limit: limit)
    }

    private func pdfRiskConcreteFocusText(for card: VisitSummaryRiskValue, limit: Int) -> String? {
        let focus = pdfExtractedRiskFocus(from: card, limit: limit)
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
        case .healthConditionReview:
            return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
        case .medicationSourceReview:
            return focus.isEmpty ? "需按药盒、说明书或医嘱核对来源。" : "核对来源：\(focus)"
        case .drugClassContext:
            return focus.isEmpty ? nil : "药品类别：\(focus)"
        case .labelRisk:
            let group = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
            if pdfIsContraindicationRisk(card) {
                return focus.isEmpty ? "需核对禁忌条件，当前资料未写明具体对象。" : "核对禁忌条件：\(focus)"
            }
            switch group {
            case .drugInteraction:
                return focus.isEmpty ? "需核对合用药品，当前资料未写明具体名称。" : "核对合用药品：\(focus)"
            case .foodAndLifestyleInteraction:
                return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
            case .conditionAndSymptomAttention:
                return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
            }
        }
    }

    private func pdfExtractedRiskFocus(from card: VisitSummaryRiskValue, limit: Int) -> String {
        let titleFocus = pdfRiskFocusFromReviewTitle(card.title, limit: limit)
        if !titleFocus.isEmpty {
            return titleFocus
        }
        let sourceExcerpt = trimmedPDFText(card.sourceExcerpt, limit: limit)
        if !sourceExcerpt.isEmpty {
            return sourceExcerpt
        }
        let message = trimmedPDFText(card.message, limit: limit)
        return pdfIsGenericRiskFocus(message) ? "" : message
    }

    private func pdfRiskFocusFromReviewTitle(_ title: String, limit: Int) -> String {
        guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
            return ""
        }
        return trimmedPDFText(String(title[title.index(after: separatorIndex)...]), limit: limit)
    }

    private func pdfRiskShareFocusText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("需核对") else {
            return trimmed
        }
        return String(trimmed.dropFirst("需核对".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pdfRiskCategoryTitle(for card: VisitSummaryRiskValue) -> String {
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
            switch RiskReviewGrouper().mappedGroup(for: card.coreRiskCard) {
            case .drugInteraction:
                return "相互作用"
            case .foodAndLifestyleInteraction:
                return "饮食注意"
            case .conditionAndSymptomAttention:
                return "病症注意"
            }
        }
    }

    private func pdfIsContraindicationRisk(_ card: VisitSummaryRiskValue) -> Bool {
        let text = pdfNormalizedRiskText("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
        return text.contains("禁忌")
            || text.contains("禁用")
            || text.contains("contraindication")
            || text.contains("contraindicated")
            || text.contains("avoid")
    }

    private func pdfIsGenericRiskFocus(_ text: String) -> Bool {
        let normalizedText = pdfNormalizedRiskText(text)
        return normalizedText.isEmpty
            || normalizedText == "相关风险"
            || normalizedText == "相关警示"
            || normalizedText == "相关提醒"
            || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
    }

    private func pdfNormalizedRiskText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private func pdfDoseChangePeriodText(change: VisitSummaryDoseChangeValue) -> String {
        let startText = AppFormatters.day.string(from: change.effectiveFrom)
        guard let effectiveUntil = pdfDoseChangeEffectiveUntil(change) else {
            return "\(startText) 起生效"
        }
        if Calendar.current.isDate(effectiveUntil, inSameDayAs: change.effectiveFrom) {
            return "\(startText) 当天生效，之后有新记录"
        }
        return "\(startText) 至 \(AppFormatters.day.string(from: effectiveUntil))"
    }

    private func pdfDoseChangeEffectiveUntil(_ change: VisitSummaryDoseChangeValue) -> Date? {
        let calendar = Calendar.current
        let currentStart = calendar.startOfDay(for: change.effectiveFrom)
        let nextChange = doseChanges
            .filter {
                $0.id != change.id
                    && $0.medicationID == change.medicationID
                    && pdfDoseChangePlanMatches($0, change)
                    && $0.effectiveFrom > change.effectiveFrom
            }
            .min { $0.effectiveFrom < $1.effectiveFrom }

        guard let nextStart = nextChange.map({ calendar.startOfDay(for: $0.effectiveFrom) }) else {
            return nil
        }
        guard nextStart > currentStart else {
            return currentStart
        }
        return calendar.date(byAdding: .day, value: -1, to: nextStart)
    }

    private func pdfDoseChangePlanMatches(_ first: VisitSummaryDoseChangeValue, _ second: VisitSummaryDoseChangeValue) -> Bool {
        guard let firstPlanID = first.planID, let secondPlanID = second.planID else {
            return true
        }
        return firstPlanID == secondPlanID
    }

    private func pdfPercentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))"
    }

    private func trendReportTitle(_ direction: MedicationTrendDirection) -> String {
        switch direction {
        case .improving:
            return "趋势改善"
        case .stable:
            return "趋势平稳"
        case .fluctuating:
            return "需要关注"
        case .declining:
            return "趋势下降"
        case .needsData:
            return "继续记录"
        }
    }

    private func trendReportColor(_ direction: MedicationTrendDirection, fallback: UIColor) -> UIColor {
        switch direction {
        case .improving:
            return UIColor(red: 0.12, green: 0.58, blue: 0.32, alpha: 1)
        case .stable:
            return fallback
        case .fluctuating:
            return UIColor(red: 0.92, green: 0.43, blue: 0.12, alpha: 1)
        case .declining:
            return UIColor(red: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        case .needsData:
            return Self.secondaryText
        }
    }

    private func drawHeader(x: CGFloat, y: CGFloat, width: CGFloat, accent: UIColor) {
        drawText("服药复诊沟通报告", rect: CGRect(x: x, y: y, width: width * 0.62, height: 28), font: .systemFont(ofSize: 22, weight: .bold))
        drawText("范围 \(rangeText) · 生成 \(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))", rect: CGRect(x: x, y: y + 32, width: width * 0.74, height: 18), font: .systemFont(ofSize: 10), color: Self.secondaryText)
        drawText("供复诊沟通", rect: CGRect(x: x + width - 118, y: y + 6, width: 118, height: 22), font: .systemFont(ofSize: 11, weight: .semibold), color: accent, alignment: .right)
        drawProgressBar(rect: CGRect(x: x, y: y + 66, width: width, height: 3), progress: 1, background: accent.withAlphaComponent(0.18), fill: accent)
    }

    private func drawMetricCard(title: String, value: String, color: UIColor, rect: CGRect) {
        drawRoundedPanel(rect: rect, fill: color.withAlphaComponent(0.10))
        drawText(value, rect: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 24), font: .monospacedDigitSystemFont(ofSize: 19, weight: .bold), color: color)
        drawText(title, rect: CGRect(x: rect.minX + 12, y: rect.minY + 37, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 10, weight: .medium), color: Self.secondaryText)
    }

    private func drawSectionTitle(_ title: String, x: CGFloat, y: CGFloat) {
        drawText(title, rect: CGRect(x: x, y: y, width: 260, height: 20), font: .systemFont(ofSize: 14, weight: .bold))
    }

    private func drawFooter(x: CGFloat, y: CGFloat, width: CGFloat) {
        drawProgressBar(rect: CGRect(x: x, y: y - 10, width: width, height: 1), progress: 1, background: Self.dividerColor, fill: Self.dividerColor)
    }

    private func drawProgressBar(rect: CGRect, progress: Double, background: UIColor, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        background.setFill()
        path.fill()
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(max(0, min(progress, 1))), height: rect.height)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        UIBezierPath(roundedRect: fillRect, cornerRadius: rect.height / 2).addClip()
        fill.setFill()
        path.fill()
        context.restoreGState()
    }

    private func drawRoundedPanel(rect: CGRect, fill: UIColor) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
    }

    private func drawTimelineDot(x: CGFloat, y: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 8, height: 8)).fill()
    }

    private func drawBodyText(_ text: String, rect: CGRect) {
        drawText(text, rect: rect, font: .systemFont(ofSize: 10), color: Self.secondaryText)
    }

    private func drawMultilineText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor = VisitSummaryPDFReport.primaryText,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor = VisitSummaryPDFReport.primaryText,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

enum VisitSummaryPDFExporter {
    static func export(payload: VisitSummaryExportPayload, targetURL: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let report = VisitSummaryPDFReport(payload: payload)
            let data = renderer.pdfData { context in
                report.draw(in: context, pageBounds: pageBounds)
            }
            try Task.checkCancellation()
            try data.write(to: targetURL, options: .atomic)
            try Task.checkCancellation()
            return targetURL
        }.value
    }
}

struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PDFPreviewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct VisitSummaryTextBuilder {
    func build(
        medications: [StoredMedication],
        tasks: [StoredDoseTask],
        riskCards: [StoredRiskCard],
        startDate: Date,
        endDate: Date,
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        let medicationsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let tasksByMedicationID = Dictionary(grouping: tasks, by: \.medicationID)
        var takenTotal = 0
        var skippedTotal = 0
        var delayedTotal = 0
        for task in tasks {
            switch task.status {
            case .taken, .corrected:
                takenTotal += 1
            case .skipped:
                skippedTotal += 1
            case .delayed:
                delayedTotal += 1
            case .pending:
                break
            }
        }
        lines.append("复诊沟通摘要")
        lines.append("")
        lines.append("日期范围：\(VisitSummaryDateRange.displayText(startDate: startDate, endDate: endDate))")
        lines.append("生成时间：\(AppFormatters.day.string(from: generatedAt)) \(AppFormatters.time.string(from: generatedAt))")
        lines.append("")

        let medicationCount = Set(tasks.map(\.medicationID)).count
        let completionRate = tasks.isEmpty ? 0 : Int((Double(takenTotal) / Double(tasks.count) * 100).rounded())
        lines.append("摘要：期间记录 \(medicationCount) 种药物，应服 \(tasks.count) 次，已服用 \(takenTotal) 次，忽略 \(skippedTotal) 次，稍后 \(delayedTotal) 次，记录服用率 \(completionRate)%。")
        lines.append("")

        if medications.isEmpty {
            lines.append("用药记录")
            lines.append("暂无药品记录。")
        } else {
            lines.append("用药记录")
            for medication in medications {
                let relatedTasks = tasksByMedicationID[medication.id] ?? []
                guard !relatedTasks.isEmpty else { continue }
                let takenCount = relatedTasks.filter { $0.status == .taken || $0.status == .corrected }.count
                let skippedCount = relatedTasks.filter { $0.status == .skipped }.count
                let delayedCount = relatedTasks.filter { $0.status == .delayed }.count
                let rate = Int((Double(takenCount) / Double(max(relatedTasks.count, 1)) * 100).rounded())
                lines.append("\(userFacingMedicationName(for: medication))：计划 \(relatedTasks.count) 次，完成 \(takenCount) 次，完成率 \(rate)%，忽略 \(skippedCount) 次，稍后 \(delayedCount) 次。")
                let exceptionNotes = relatedTasks
                    .filter { $0.status == .skipped || $0.status == .delayed }
                    .prefix(3)
                    .map { task in
                        "\(AppFormatters.day.string(from: task.effectiveAdherenceDate)) \(task.status == .skipped ? "忽略" : "稍后")"
                    }
                if !exceptionNotes.isEmpty {
                    lines.append("需沟通节点：\(exceptionNotes.joined(separator: "；"))。")
                }
            }
        }

        lines.append("")
        lines.append("所选时间段记录")
        let calendar = Calendar.current
        let recentTasks = tasks
            .filter { $0.effectiveAdherenceDate >= startDate && $0.effectiveAdherenceDate <= endDate }
            .sorted { $0.effectiveAdherenceDate < $1.effectiveAdherenceDate }
        let groupedByWeek = Dictionary(grouping: recentTasks) { task -> Date in
            let interval = calendar.dateInterval(of: .weekOfYear, for: task.effectiveAdherenceDate)
            return interval?.start ?? calendar.startOfDay(for: task.effectiveAdherenceDate)
        }
        for weekStart in groupedByWeek.keys.sorted() {
            let weekTasks = groupedByWeek[weekStart] ?? []
            let takenCount = weekTasks.filter { $0.status == .taken || $0.status == .corrected }.count
            let delayedCount = weekTasks.filter { $0.status == .delayed }.count
            let skipped = weekTasks.filter { $0.status == .skipped }
            lines.append("\(AppFormatters.day.string(from: weekStart)) 周：计划 \(weekTasks.count) 次，完成 \(takenCount) 次，稍后 \(delayedCount) 次，忽略 \(skipped.count) 次。")
            let exceptions = weekTasks
                .filter { $0.status == .skipped || $0.status == .delayed }
                .prefix(8)
            for task in exceptions {
                let medicationName = medicationsByID[task.medicationID].map(userFacingMedicationName(for:)) ?? "未知药品"
                let action = task.status == .skipped ? "忽略" : "稍后"
                let displayDate = task.effectiveAdherenceDate
                lines.append("- \(AppFormatters.day.string(from: displayDate)) \(AppFormatters.time.string(from: displayDate))：\(medicationName) \(action)。")
            }
        }

        lines.append("")
        lines.append("风险提示")
        let importantRiskCards = riskCards.filter { $0.requiresProfessionalReview && $0.isActive }.prefix(6)
        if importantRiskCards.isEmpty {
            lines.append("暂无需要优先沟通的风险提醒。")
        } else {
            for card in importantRiskCards {
                let medicationName = medicationsByID[card.medicationID].map(userFacingMedicationName(for:)) ?? "未知药品"
                lines.append("\(medicationName)：\(summaryRiskDisplayTitle(for: card, limit: 48))。\(summaryRiskFocusText(for: card))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summaryRiskFocusText(for card: StoredRiskCard) -> String {
        if let focus = summaryRiskConcreteFocusText(for: card, limit: 96) {
            return focus
        }
        let message = summaryTrimmedText(card.message, limit: 96)
        return message.isEmpty ? "需补充说明书或向医生或药师确认具体对象。" : message
    }

    private func summaryRiskDisplayTitle(for card: StoredRiskCard, limit: Int) -> String {
        let rawTitle = summaryTrimmedText(card.title, limit: limit)
        guard summaryIsGenericRiskFocus(rawTitle) || rawTitle == "警示信息" || rawTitle == "注意事项" else {
            return rawTitle.isEmpty ? summaryRiskCategoryTitle(for: card) : rawTitle
        }
        let category = summaryIsContraindicationRisk(card) ? "禁忌或慎用" : summaryRiskCategoryTitle(for: card)
        guard let focus = summaryRiskConcreteFocusText(for: card, limit: limit),
              !focus.isEmpty
        else {
            return category
        }
        return summaryTrimmedText("\(category)：\(summaryRiskShareFocusText(focus))", limit: limit)
    }

    private func summaryRiskConcreteFocusText(for card: StoredRiskCard, limit: Int) -> String? {
        let focus = summaryExtractedRiskFocus(from: card, limit: limit)
        switch RiskAssessmentCardKind(rawValue: card.kindRaw) ?? .labelRisk {
        case .foodReview:
            return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
        case .healthConditionReview:
            return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
        case .medicationSourceReview:
            return focus.isEmpty ? "需按药盒、说明书或医嘱核对来源。" : "核对来源：\(focus)"
        case .drugClassContext:
            return focus.isEmpty ? nil : "药品类别：\(focus)"
        case .labelRisk:
            let group = RiskReviewGrouper().mappedGroup(for: card.coreRiskCard)
            if summaryIsContraindicationRisk(card) {
                return focus.isEmpty ? "需核对禁忌条件，当前资料未写明具体对象。" : "核对禁忌条件：\(focus)"
            }
            switch group {
            case .drugInteraction:
                return focus.isEmpty ? "需核对合用药品，当前资料未写明具体名称。" : "核对合用药品：\(focus)"
            case .foodAndLifestyleInteraction:
                return focus.isEmpty ? "需核对具体饮食或生活方式。" : "核对饮食或生活方式：\(focus)"
            case .conditionAndSymptomAttention:
                return focus.isEmpty ? "需核对具体病症或症状。" : "核对病症或症状：\(focus)"
            }
        }
    }

    private func summaryExtractedRiskFocus(from card: StoredRiskCard, limit: Int) -> String {
        let titleFocus = summaryRiskFocusFromReviewTitle(card.title, limit: limit)
        if !titleFocus.isEmpty {
            return titleFocus
        }
        let sourceExcerpt = summaryTrimmedText(card.sourceExcerpt, limit: limit)
        if !sourceExcerpt.isEmpty {
            return sourceExcerpt
        }
        let message = summaryTrimmedText(card.message, limit: limit)
        return summaryIsGenericRiskFocus(message) ? "" : message
    }

    private func summaryRiskFocusFromReviewTitle(_ title: String, limit: Int) -> String {
        guard let separatorIndex = title.firstIndex(of: "：") ?? title.firstIndex(of: ":") else {
            return ""
        }
        return summaryTrimmedText(String(title[title.index(after: separatorIndex)...]), limit: limit)
    }

    private func summaryRiskShareFocusText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("需核对") else {
            return trimmed
        }
        return String(trimmed.dropFirst("需核对".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func summaryRiskCategoryTitle(for card: StoredRiskCard) -> String {
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
            switch RiskReviewGrouper().mappedGroup(for: card.coreRiskCard) {
            case .drugInteraction:
                return "相互作用"
            case .foodAndLifestyleInteraction:
                return "饮食注意"
            case .conditionAndSymptomAttention:
                return "病症注意"
            }
        }
    }

    private func summaryTrimmedText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "说明书“", with: "")
            .replacingOccurrences(of: "”指出：", with: "：")
            .replacingOccurrences(of: "请咨询医生或药师", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<index]) + "..."
    }

    private func summaryIsContraindicationRisk(_ card: StoredRiskCard) -> Bool {
        let text = summaryNormalizedRiskText("\(card.title) \(card.message) \(card.sourceTitle) \(card.sourceExcerpt)")
        return text.contains("禁忌")
            || text.contains("禁用")
            || text.contains("contraindication")
            || text.contains("contraindicated")
            || text.contains("avoid")
    }

    private func summaryIsGenericRiskFocus(_ text: String) -> Bool {
        let normalizedText = summaryNormalizedRiskText(text)
        return normalizedText.isEmpty
            || normalizedText == "相关风险"
            || normalizedText == "相关警示"
            || normalizedText == "相关提醒"
            || normalizedText.contains("已根据药品资料和用户记录生成用药风险提醒")
    }

    private func summaryNormalizedRiskText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
