import Foundation

public enum MedicationTrendTopic: String, Codable, Sendable, Equatable, CaseIterable {
    case discipline
    case timing
    case doseChange
    case regimenLoad
    case healthSignal
}

public enum MedicationTrendDirection: String, Codable, Sendable, Equatable {
    case improving
    case stable
    case declining
    case needsData
}

public enum MedicationLifecycleState: String, Codable, Sendable, Equatable {
    case active
    case interrupted
    case archived
}

public enum HealthSignalKind: String, Codable, Sendable, Equatable {
    case heartRate
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bloodOxygen
    case bodyTemperature
    case bloodGlucose
    case unknown
}

public struct MedicationLifecycleEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var medicationID: UUID
    public var state: MedicationLifecycleState
    public var occurredAt: Date
    public var note: String

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        state: MedicationLifecycleState,
        occurredAt: Date,
        note: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.state = state
        self.occurredAt = occurredAt
        self.note = note
    }
}

public struct HealthSignalSample: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: HealthSignalKind
    public var measuredAt: Date
    public var value: Double
    public var unit: String

    public init(
        id: UUID = UUID(),
        kind: HealthSignalKind,
        measuredAt: Date,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.kind = kind
        self.measuredAt = measuredAt
        self.value = value
        self.unit = unit
    }
}

public struct MedicationTrendPoint: Codable, Identifiable, Sendable, Equatable {
    public var id: DateOnly { date }
    public var date: DateOnly
    public var score: Double
    public var scheduledCount: Int
    public var completedCount: Int
    public var delayedCount: Int
    public var skippedCount: Int
    public var doseChangeCount: Int
    public var activeMedicationCount: Int
    public var archivedMedicationCount: Int
    public var healthSignalCount: Int
    public var annotation: String

    public init(
        date: DateOnly,
        score: Double,
        scheduledCount: Int,
        completedCount: Int,
        delayedCount: Int,
        skippedCount: Int,
        doseChangeCount: Int = 0,
        activeMedicationCount: Int = 0,
        archivedMedicationCount: Int = 0,
        healthSignalCount: Int = 0,
        annotation: String = ""
    ) {
        self.date = date
        self.score = score
        self.scheduledCount = scheduledCount
        self.completedCount = completedCount
        self.delayedCount = delayedCount
        self.skippedCount = skippedCount
        self.doseChangeCount = doseChangeCount
        self.activeMedicationCount = activeMedicationCount
        self.archivedMedicationCount = archivedMedicationCount
        self.healthSignalCount = healthSignalCount
        self.annotation = annotation
    }
}

public struct MedicationTrendMetric: Codable, Identifiable, Sendable, Equatable {
    public var id: MedicationTrendTopic { topic }
    public var topic: MedicationTrendTopic
    public var title: String
    public var score: Double
    public var direction: MedicationTrendDirection
    public var summary: String
    public var dataSourceSummary: String
    public var points: [MedicationTrendPoint]

    public init(
        topic: MedicationTrendTopic,
        title: String,
        score: Double,
        direction: MedicationTrendDirection,
        summary: String,
        dataSourceSummary: String,
        points: [MedicationTrendPoint]
    ) {
        self.topic = topic
        self.title = title
        self.score = score
        self.direction = direction
        self.summary = summary
        self.dataSourceSummary = dataSourceSummary
        self.points = points
    }
}

public struct MedicationTrendDashboard: Codable, Sendable, Equatable {
    public var overallScore: Double
    public var direction: MedicationTrendDirection
    public var title: String
    public var summary: String
    public var disciplineSummary: String
    public var safetyNote: String
    public var metrics: [MedicationTrendMetric]

    public init(
        overallScore: Double,
        direction: MedicationTrendDirection,
        title: String,
        summary: String,
        disciplineSummary: String,
        safetyNote: String = MedicationTrendDashboardBuilder.defaultSafetyNote,
        metrics: [MedicationTrendMetric]
    ) {
        self.overallScore = overallScore
        self.direction = direction
        self.title = title
        self.summary = summary
        self.disciplineSummary = disciplineSummary
        self.safetyNote = safetyNote
        self.metrics = metrics
    }
}

public struct MedicationTrendDashboardBuilder: Sendable {
    public static let defaultMinimumRequiredDays = 7
    public static let defaultMaximumAnalysisDays = 56
    public static let defaultSafetyNote = "用药趋势只整理用户记录、用药方案变化和授权健康数据，不代表诊断、处方、剂量建议或疗效判断。"

    public init() {}

    public func build(
        scheduledDoses: [ScheduledDose],
        events: [DoseEvent],
        doseChanges: [MedicationDoseChange] = [],
        lifecycleEvents: [MedicationLifecycleEvent] = [],
        healthSignals: [HealthSignalSample] = [],
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone,
        now: Date = Date(),
        minimumRequiredDays: Int = Self.defaultMinimumRequiredDays,
        maximumAnalysisDays: Int = Self.defaultMaximumAnalysisDays
    ) -> MedicationTrendDashboard {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let requiredDays = max(1, minimumRequiredDays)
        let maxDays = max(requiredDays, maximumAnalysisDays)
        let dates = analysisDates(scheduledDoses: scheduledDoses, calendar: calendar, limit: maxDays)
        let latestEvents = Dictionary(grouping: events, by: \.scheduledDoseID).compactMapValues { doseEvents in
            doseEvents.sorted { $0.recordedAt < $1.recordedAt }.last
        }
        let dosesByDate = Dictionary(grouping: scheduledDoses) { dateOnly(from: $0.dueAt, calendar: calendar) }
        let doseChangesByDate = Dictionary(grouping: doseChanges) { dateOnly(from: $0.effectiveFrom, calendar: calendar) }
        let lifecycleByDate = Dictionary(grouping: lifecycleEvents) { dateOnly(from: $0.occurredAt, calendar: calendar) }
        let healthByDate = Dictionary(grouping: healthSignals) { dateOnly(from: $0.measuredAt, calendar: calendar) }

        let disciplinePoints = dates.map { date in
            point(
                date: date,
                doses: dosesByDate[date] ?? [],
                latestEvents: latestEvents,
                score: completionScore(doses: dosesByDate[date] ?? [], latestEvents: latestEvents),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0
            )
        }

        let timingPoints = dates.map { date in
            let doses = dosesByDate[date] ?? []
            return point(
                date: date,
                doses: doses,
                latestEvents: latestEvents,
                score: timingScore(doses: doses, latestEvents: latestEvents),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0
            )
        }

        let doseChangePoints = dates.map { date in
            let count = doseChangesByDate[date]?.count ?? 0
            let score = count == 0 ? 1 : max(0.35, 1 - Double(count) * 0.18)
            return point(
                date: date,
                doses: dosesByDate[date] ?? [],
                latestEvents: latestEvents,
                score: score,
                doseChangeCount: count,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0,
                annotation: count == 0 ? "" : "\(count) 次剂量变化"
            )
        }

        let regimenPoints = dates.map { date in
            let doses = dosesByDate[date] ?? []
            let lifecycleEventsForDate = lifecycleByDate[date] ?? []
            let archivedCount = lifecycleEventsForDate.filter { $0.state == .archived }.count
            let activeMedicationCount = Set(doses.map(\.planID)).count
            let loadPenalty = min(0.35, Double(max(0, doses.count - 4)) * 0.05)
            let archivePenalty = min(0.25, Double(archivedCount) * 0.08)
            return point(
                date: date,
                doses: doses,
                latestEvents: latestEvents,
                score: max(0, 1 - loadPenalty - archivePenalty),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                activeMedicationCount: activeMedicationCount,
                archivedMedicationCount: archivedCount,
                lifecycleEvents: lifecycleEventsForDate,
                healthSignalCount: healthByDate[date]?.count ?? 0,
                annotation: loadAnnotation(doseCount: doses.count, archivedCount: archivedCount)
            )
        }

        let healthPoints = dates.map { date in
            let samples = healthByDate[date] ?? []
            let score = healthSignalScore(samples: samples)
            return point(
                date: date,
                doses: dosesByDate[date] ?? [],
                latestEvents: latestEvents,
                score: score,
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: samples.count,
                annotation: samples.isEmpty ? "等待授权健康数据" : "\(samples.count) 条健康数据"
            )
        }

        let metrics = [
            metric(
                topic: .discipline,
                title: "用药纪律",
                points: disciplinePoints,
                requiredDays: requiredDays,
                source: "服药历史：已服用、已修正、稍后、忽略",
                summary: disciplineSummary(points: disciplinePoints, requiredDays: requiredDays)
            ),
            metric(
                topic: .timing,
                title: "时间稳定",
                points: timingPoints,
                requiredDays: requiredDays,
                source: "服药时间：提醒时间与用户记录时间差",
                summary: timingSummary(points: timingPoints, requiredDays: requiredDays)
            ),
            metric(
                topic: .doseChange,
                title: "剂量变化",
                points: doseChangePoints,
                requiredDays: requiredDays,
                source: "剂量变化记录：旧剂量、新剂量、生效日期",
                summary: doseChangeSummary(count: doseChanges.count)
            ),
            metric(
                topic: .regimenLoad,
                title: "用药负担",
                points: regimenPoints,
                requiredDays: requiredDays,
                source: "药物类型、每日提醒数量、归档或中断操作",
                summary: regimenSummary(points: regimenPoints, requiredDays: requiredDays)
            ),
            metric(
                topic: .healthSignal,
                title: "健康信号",
                points: healthPoints,
                requiredDays: requiredDays,
                source: "用户授权的 HealthKit 心率、血压、血氧、体温、血糖等指标",
                summary: healthSummary(sampleCount: healthSignals.count)
            )
        ]

        let scoredMetrics = metrics.filter { $0.direction != .needsData && $0.topic != .healthSignal }
        let overall = scoredMetrics.isEmpty ? 0 : scoredMetrics.reduce(0) { $0 + $1.score } / Double(scoredMetrics.count)
        let direction = direction(for: disciplinePoints)
        return MedicationTrendDashboard(
            overallScore: clamped(overall),
            direction: scoredMetrics.isEmpty ? .needsData : direction,
            title: dashboardTitle(direction: scoredMetrics.isEmpty ? .needsData : direction),
            summary: dashboardSummary(metrics: metrics, overallScore: overall, requiredDays: requiredDays),
            disciplineSummary: disciplineSummary(points: disciplinePoints, requiredDays: requiredDays),
            metrics: metrics
        )
    }

    private func analysisDates(scheduledDoses: [ScheduledDose], calendar: Calendar, limit: Int) -> [DateOnly] {
        let dates = Set(scheduledDoses.map { dateOnly(from: $0.dueAt, calendar: calendar) })
        return Array(dates).sorted().suffix(limit).map { $0 }
    }

    private func point(
        date: DateOnly,
        doses: [ScheduledDose],
        latestEvents: [UUID: DoseEvent],
        score: Double,
        doseChangeCount: Int = 0,
        activeMedicationCount: Int = 0,
        archivedMedicationCount: Int = 0,
        lifecycleEvents: [MedicationLifecycleEvent],
        healthSignalCount: Int,
        annotation: String = ""
    ) -> MedicationTrendPoint {
        let events = doses.compactMap { latestEvents[$0.id] }
        let completed = events.filter { $0.status == .taken || $0.status == .corrected }.count
        let delayed = events.filter { $0.status == .delayed }.count
        let skipped = events.filter { $0.status == .skipped }.count
        let archived = archivedMedicationCount + lifecycleEvents.filter { $0.state == .archived }.count
        return MedicationTrendPoint(
            date: date,
            score: clamped(score),
            scheduledCount: doses.count,
            completedCount: completed,
            delayedCount: delayed,
            skippedCount: skipped,
            doseChangeCount: doseChangeCount,
            activeMedicationCount: activeMedicationCount,
            archivedMedicationCount: archived,
            healthSignalCount: healthSignalCount,
            annotation: annotation
        )
    }

    private func completionScore(doses: [ScheduledDose], latestEvents: [UUID: DoseEvent]) -> Double {
        guard !doses.isEmpty else {
            return 0
        }
        let events = doses.compactMap { latestEvents[$0.id] }
        let completed = events.filter { $0.status == .taken || $0.status == .corrected }.count
        let delayed = events.filter { $0.status == .delayed }.count
        return (Double(completed) + Double(delayed) * 0.35) / Double(doses.count)
    }

    private func timingScore(doses: [ScheduledDose], latestEvents: [UUID: DoseEvent]) -> Double {
        let completedEvents = doses.compactMap { dose -> (ScheduledDose, DoseEvent)? in
            guard let event = latestEvents[dose.id], event.status == .taken || event.status == .corrected || event.status == .delayed else {
                return nil
            }
            return (dose, event)
        }
        guard !completedEvents.isEmpty else {
            return doses.isEmpty ? 0 : 0.25
        }
        let averageDelayMinutes = completedEvents.reduce(0.0) { result, pair in
            result + abs(pair.1.recordedAt.timeIntervalSince(pair.0.dueAt)) / 60
        } / Double(completedEvents.count)
        return clamped(1 - averageDelayMinutes / 180)
    }

    private func healthSignalScore(samples: [HealthSignalSample]) -> Double {
        guard !samples.isEmpty else {
            return 0
        }
        let kinds = Set(samples.map(\.kind))
        return clamped(0.45 + Double(kinds.count) * 0.12)
    }

    private func metric(
        topic: MedicationTrendTopic,
        title: String,
        points: [MedicationTrendPoint],
        requiredDays: Int,
        source: String,
        summary: String
    ) -> MedicationTrendMetric {
        let direction = points.count < requiredDays ? MedicationTrendDirection.needsData : direction(for: points)
        let score = averageScore(points)
        return MedicationTrendMetric(
            topic: topic,
            title: title,
            score: score,
            direction: direction,
            summary: points.count < requiredDays ? "至少记录 \(requiredDays) 个有提醒日期后，才生成稳定趋势。" : summary,
            dataSourceSummary: source,
            points: points
        )
    }

    private func direction(for points: [MedicationTrendPoint]) -> MedicationTrendDirection {
        guard points.count >= 7 else {
            return .needsData
        }
        let recent = Array(points.suffix(7))
        let previous = Array(points.dropLast(7).suffix(7))
        let recentAverage = averageScore(recent)
        let previousAverage = previous.count == 7 ? averageScore(previous) : averageScore(points)
        let change = recentAverage - previousAverage
        if change >= 0.08 {
            return .improving
        }
        if change <= -0.08 {
            return .declining
        }
        return .stable
    }

    private func averageScore(_ points: [MedicationTrendPoint]) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        return clamped(points.reduce(0) { $0 + $1.score } / Double(points.count))
    }

    private func disciplineSummary(points: [MedicationTrendPoint], requiredDays: Int) -> String {
        guard points.count >= requiredDays else {
            return "继续积累记录后，将按完成、稍后和忽略情况生成用药纪律趋势。"
        }
        let recent = Array(points.suffix(7))
        let scheduled = recent.reduce(0) { $0 + $1.scheduledCount }
        let completed = recent.reduce(0) { $0 + $1.completedCount }
        let delayed = recent.reduce(0) { $0 + $1.delayedCount }
        let skipped = recent.reduce(0) { $0 + $1.skippedCount }
        return "最近 7 天完成 \(completed)/\(scheduled) 项，稍后 \(delayed) 项，忽略 \(skipped) 项。"
    }

    private func timingSummary(points: [MedicationTrendPoint], requiredDays: Int) -> String {
        guard points.count >= requiredDays else {
            return "继续记录实际服药时间后，将观察提醒与记录时间的稳定性。"
        }
        let score = averageScore(Array(points.suffix(7)))
        return score >= 0.8 ? "近期服药时间较稳定。" : "近期记录时间波动较大，可复盘容易延后的时段。"
    }

    private func doseChangeSummary(count: Int) -> String {
        count == 0 ? "近期没有剂量变化记录。" : "记录到 \(count) 次剂量变化；趋势解读应结合调整前后分别观察。"
    }

    private func regimenSummary(points: [MedicationTrendPoint], requiredDays: Int) -> String {
        guard points.count >= requiredDays else {
            return "继续记录后，将结合每日提醒数量和归档/中断操作观察用药负担。"
        }
        let recent = Array(points.suffix(7))
        let averageScheduled = recent.isEmpty ? 0 : Double(recent.reduce(0) { $0 + $1.scheduledCount }) / Double(recent.count)
        let archived = recent.reduce(0) { $0 + $1.archivedMedicationCount }
        return archived > 0 ? "近期有归档或中断操作，建议复诊时说明变化。" : "最近 7 天平均每日 \(averageScheduled.formatted(.number.precision(.fractionLength(1)))) 项提醒。"
    }

    private func healthSummary(sampleCount: Int) -> String {
        sampleCount == 0 ? "等待用户授权并导入 HealthKit 数据后，再观察生命体征与用药记录的时间关系。" : "已接入 \(sampleCount) 条授权健康数据，仅用于用药相关提示准备。"
    }

    private func dashboardTitle(direction: MedicationTrendDirection) -> String {
        switch direction {
        case .improving:
            return "用药趋势改善"
        case .stable:
            return "用药趋势平稳"
        case .declining:
            return "用药趋势需关注"
        case .needsData:
            return "继续记录后生成趋势"
        }
    }

    private func dashboardSummary(metrics: [MedicationTrendMetric], overallScore: Double, requiredDays: Int) -> String {
        let available = metrics.filter { $0.direction != .needsData }.count
        guard available > 0 else {
            return "至少记录 \(requiredDays) 个有提醒日期后，才生成多主题用药趋势。"
        }
        return "综合用药纪律、时间稳定、剂量变化和用药负担，当前综合评分 \(Int((overallScore * 100).rounded()))%。"
    }

    private func loadAnnotation(doseCount: Int, archivedCount: Int) -> String {
        if archivedCount > 0 {
            return "\(archivedCount) 个归档操作"
        }
        if doseCount >= 5 {
            return "当天提醒较多"
        }
        return ""
    }

    private func dateOnly(from date: Date, calendar: Calendar) -> DateOnly {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateOnly(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
