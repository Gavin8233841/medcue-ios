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
    case fluctuating
    case declining
    case needsData
}

public struct MedicationTrendPeriodComparison: Codable, Sendable, Equatable {
    public var recentPeriodTitle: String
    public var previousPeriodTitle: String
    public var recentScore: Double
    public var previousScore: Double?
    public var delta: Double?
    public var trendSlopePerDay: Double
    public var trendStrengthScore: Double
    public var confidenceScore: Double
    public var recentDayCount: Int
    public var previousDayCount: Int
    public var recentScheduledCount: Int
    public var previousScheduledCount: Int
    public var evidenceSummary: String

    public init(
        recentPeriodTitle: String = "近 7 天",
        previousPeriodTitle: String = "前 7 天",
        recentScore: Double,
        previousScore: Double? = nil,
        delta: Double? = nil,
        trendSlopePerDay: Double = 0,
        trendStrengthScore: Double = 0,
        confidenceScore: Double,
        recentDayCount: Int,
        previousDayCount: Int,
        recentScheduledCount: Int,
        previousScheduledCount: Int,
        evidenceSummary: String
    ) {
        self.recentPeriodTitle = recentPeriodTitle
        self.previousPeriodTitle = previousPeriodTitle
        self.recentScore = recentScore
        self.previousScore = previousScore
        self.delta = delta
        self.trendSlopePerDay = trendSlopePerDay
        self.trendStrengthScore = trendStrengthScore
        self.confidenceScore = confidenceScore
        self.recentDayCount = recentDayCount
        self.previousDayCount = previousDayCount
        self.recentScheduledCount = recentScheduledCount
        self.previousScheduledCount = previousScheduledCount
        self.evidenceSummary = evidenceSummary
    }
}

public struct MedicationTrendFormulaComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var weight: Double
    public var score: Double
    public var source: String
    public var explanation: String

    public init(
        id: String,
        title: String,
        weight: Double,
        score: Double,
        source: String,
        explanation: String
    ) {
        self.id = id
        self.title = title
        self.weight = weight
        self.score = score
        self.source = source
        self.explanation = explanation
    }
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

public struct MedicationTrendPlanContext: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID { planID }
    public var planID: UUID
    public var medicationID: UUID
    public var medicationKind: MedicationKind
    public var inputSource: MedicationInputSource
    public var lifecycleState: MedicationLifecycleState

    public init(
        planID: UUID,
        medicationID: UUID,
        medicationKind: MedicationKind,
        inputSource: MedicationInputSource,
        lifecycleState: MedicationLifecycleState
    ) {
        self.planID = planID
        self.medicationID = medicationID
        self.medicationKind = medicationKind
        self.inputSource = inputSource
        self.lifecycleState = lifecycleState
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
    public var interruptedMedicationCount: Int
    public var prescriptionMedicationCount: Int
    public var nonPrescriptionMedicationCount: Int
    public var importedMedicationCount: Int
    public var healthSignalCount: Int
    public var formulaComponents: [MedicationTrendFormulaComponent]
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
        interruptedMedicationCount: Int = 0,
        prescriptionMedicationCount: Int = 0,
        nonPrescriptionMedicationCount: Int = 0,
        importedMedicationCount: Int = 0,
        healthSignalCount: Int = 0,
        formulaComponents: [MedicationTrendFormulaComponent] = [],
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
        self.interruptedMedicationCount = interruptedMedicationCount
        self.prescriptionMedicationCount = prescriptionMedicationCount
        self.nonPrescriptionMedicationCount = nonPrescriptionMedicationCount
        self.importedMedicationCount = importedMedicationCount
        self.healthSignalCount = healthSignalCount
        self.formulaComponents = formulaComponents
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
    public var formulaSummary: String
    public var comparison: MedicationTrendPeriodComparison
    public var contributorSummary: [String]
    public var formulaComponents: [MedicationTrendFormulaComponent]
    public var points: [MedicationTrendPoint]

    public init(
        topic: MedicationTrendTopic,
        title: String,
        score: Double,
        direction: MedicationTrendDirection,
        summary: String,
        dataSourceSummary: String,
        formulaSummary: String,
        comparison: MedicationTrendPeriodComparison,
        contributorSummary: [String] = [],
        formulaComponents: [MedicationTrendFormulaComponent] = [],
        points: [MedicationTrendPoint]
    ) {
        self.topic = topic
        self.title = title
        self.score = score
        self.direction = direction
        self.summary = summary
        self.dataSourceSummary = dataSourceSummary
        self.formulaSummary = formulaSummary
        self.comparison = comparison
        self.contributorSummary = contributorSummary
        self.formulaComponents = formulaComponents
        self.points = points
    }
}

public struct MedicationTrendDashboard: Codable, Sendable, Equatable {
    public var overallScore: Double
    public var direction: MedicationTrendDirection
    public var title: String
    public var summary: String
    public var disciplineSummary: String
    public var confidenceScore: Double
    public var dataQualitySummary: String
    public var safetyNote: String
    public var metrics: [MedicationTrendMetric]

    public init(
        overallScore: Double,
        direction: MedicationTrendDirection,
        title: String,
        summary: String,
        disciplineSummary: String,
        confidenceScore: Double = 0,
        dataQualitySummary: String = "继续记录后提高趋势可信度。",
        safetyNote: String = MedicationTrendDashboardBuilder.defaultSafetyNote,
        metrics: [MedicationTrendMetric]
    ) {
        self.overallScore = overallScore
        self.direction = direction
        self.title = title
        self.summary = summary
        self.disciplineSummary = disciplineSummary
        self.confidenceScore = confidenceScore
        self.dataQualitySummary = dataQualitySummary
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
        planContexts: [MedicationTrendPlanContext] = [],
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
        let latestEvents = Dictionary(grouping: events, by: \.scheduledDoseID).compactMapValues { doseEvents in
            doseEvents.sorted { $0.recordedAt < $1.recordedAt }.last
        }
        let measurableDoses = scheduledDoses.filter { dose in
            dose.dueAt <= now || latestEvents[dose.id] != nil
        }
        let historicalDoseChanges = doseChanges.filter { $0.effectiveFrom <= now }
        let historicalLifecycleEvents = lifecycleEvents.filter { $0.occurredAt <= now }
        let historicalHealthSignals = healthSignals.filter { $0.measuredAt <= now }
        let dates = analysisDates(scheduledDoses: measurableDoses, latestEvents: latestEvents, calendar: calendar, now: now, limit: maxDays)
        let dosesByDate = Dictionary(grouping: measurableDoses) { dose -> DateOnly in
            if let event = latestEvents[dose.id], dose.dueAt > now {
                return dateOnly(from: event.recordedAt, calendar: calendar)
            }
            return dateOnly(from: dose.dueAt, calendar: calendar)
        }
        let doseChangesByDate = Dictionary(grouping: historicalDoseChanges) { dateOnly(from: $0.effectiveFrom, calendar: calendar) }
        let lifecycleByDate = Dictionary(grouping: historicalLifecycleEvents) { dateOnly(from: $0.occurredAt, calendar: calendar) }
        let lifecycleEventsByMedicationID = Dictionary(grouping: historicalLifecycleEvents, by: \.medicationID)
        let healthByDate = Dictionary(grouping: historicalHealthSignals) { dateOnly(from: $0.measuredAt, calendar: calendar) }
        let contextsByPlanID = Dictionary(grouping: planContexts, by: \.planID).compactMapValues(\.first)

        let disciplinePoints = dates.map { date in
            let doses = dosesByDate[date] ?? []
            let components = disciplineComponents(doses: doses, latestEvents: latestEvents)
            return point(
                date: date,
                doses: doses,
                latestEvents: latestEvents,
                score: weightedScore(components),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0,
                formulaComponents: components
            )
        }

        let timingPoints = dates.map { date in
            let doses = dosesByDate[date] ?? []
            let components = timingComponents(doses: doses, latestEvents: latestEvents)
            return point(
                date: date,
                doses: doses,
                latestEvents: latestEvents,
                score: weightedScore(components),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0,
                formulaComponents: components
            )
        }

        let doseChangePoints = dates.map { date in
            let count = doseChangesByDate[date]?.count ?? 0
            let components = doseChangeComponents(changeCount: count)
            return point(
                date: date,
                doses: dosesByDate[date] ?? [],
                latestEvents: latestEvents,
                score: weightedScore(components),
                doseChangeCount: count,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: healthByDate[date]?.count ?? 0,
                formulaComponents: components,
                annotation: count == 0 ? "" : "\(count) 次剂量变化"
            )
        }

        let regimenPoints = dates.map { date in
            let doses = dosesByDate[date] ?? []
            let lifecycleEventsForDate = lifecycleByDate[date] ?? []
            let contexts = uniquePlanContexts(
                for: doses,
                date: date,
                contextsByPlanID: contextsByPlanID,
                lifecycleEventsByMedicationID: lifecycleEventsByMedicationID,
                calendar: calendar
            )
            let archivedEventCount = lifecycleEventsForDate.filter { $0.state == .archived }.count
            let interruptedEventCount = lifecycleEventsForDate.filter { $0.state == .interrupted }.count
            let archivedContextCount = contexts.filter { $0.lifecycleState == .archived }.count
            let interruptedCount = contexts.filter { $0.lifecycleState == .interrupted }.count + interruptedEventCount
            let activeMedicationCount = contexts.isEmpty ? Set(doses.map(\.planID)).count : contexts.filter { $0.lifecycleState == .active }.count
            let prescriptionCount = contexts.filter { $0.medicationKind == .prescription }.count
            let nonPrescriptionCount = contexts.filter { $0.medicationKind == .overTheCounter }.count
            let importedCount = contexts.filter { $0.inputSource == .barcode || $0.inputSource == .prescriptionImage }.count
            let components = regimenLoadComponents(
                doseCount: doses.count,
                archivedCount: archivedEventCount + archivedContextCount,
                interruptedCount: interruptedCount,
                prescriptionCount: prescriptionCount,
                importedCount: importedCount
            )
            return point(
                date: date,
                doses: doses,
                latestEvents: latestEvents,
                score: weightedScore(components),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                activeMedicationCount: activeMedicationCount,
                archivedMedicationCount: archivedContextCount,
                interruptedMedicationCount: interruptedCount,
                prescriptionMedicationCount: prescriptionCount,
                nonPrescriptionMedicationCount: nonPrescriptionCount,
                importedMedicationCount: importedCount,
                lifecycleEvents: lifecycleEventsForDate,
                healthSignalCount: healthByDate[date]?.count ?? 0,
                formulaComponents: components,
                annotation: loadAnnotation(
                    doseCount: doses.count,
                    archivedCount: archivedEventCount + archivedContextCount,
                    interruptedCount: interruptedCount,
                    prescriptionCount: prescriptionCount
                )
            )
        }

        let healthPoints = dates.map { date in
            let samples = healthByDate[date] ?? []
            let components = healthSignalComponents(samples: samples)
            return point(
                date: date,
                doses: dosesByDate[date] ?? [],
                latestEvents: latestEvents,
                score: weightedScore(components),
                doseChangeCount: doseChangesByDate[date]?.count ?? 0,
                lifecycleEvents: lifecycleByDate[date] ?? [],
                healthSignalCount: samples.count,
                formulaComponents: components,
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
                formulaSummary: "纪律分 = 完成覆盖 x 62% + 稍后影响 x 22% + 忽略影响 x 16%。稍后保留部分分值，忽略只用于复盘，不判断疗效。",
                summary: disciplineSummary(points: disciplinePoints, requiredDays: requiredDays),
                formulaComponents: aggregateFormulaComponents(
                    topic: .discipline,
                    points: disciplinePoints,
                    componentBuilder: { point in
                        disciplineComponentsForPoint(point)
                    }
                )
            ),
            metric(
                topic: .timing,
                title: "时间稳定",
                points: timingPoints,
                requiredDays: requiredDays,
                source: "服药时间：提醒时间与用户记录时间差",
                formulaSummary: "时间稳定分 = 时间偏差 x 70% + 记录覆盖 x 30%。时间偏差以实际记录和提醒时间的绝对差估算。",
                summary: timingSummary(points: timingPoints, requiredDays: requiredDays),
                formulaComponents: aggregateFormulaComponents(
                    topic: .timing,
                    points: timingPoints,
                    componentBuilder: { point in
                        timingComponentsForPoint(point)
                    }
                )
            ),
            metric(
                topic: .doseChange,
                title: "剂量变化",
                points: doseChangePoints,
                requiredDays: requiredDays,
                source: "剂量变化记录：旧剂量、新剂量、生效日期",
                formulaSummary: "剂量变化分 = 调整频率 x 55% + 观察连续性 x 45%。剂量变更日前后分段观察，不评价疗效。",
                summary: doseChangeSummary(count: historicalDoseChanges.count),
                formulaComponents: aggregateFormulaComponents(
                    topic: .doseChange,
                    points: doseChangePoints,
                    componentBuilder: { point in
                        doseChangeComponents(changeCount: point.doseChangeCount)
                    }
                )
            ),
            metric(
                topic: .regimenLoad,
                title: "用药负担",
                points: regimenPoints,
                requiredDays: requiredDays,
                source: "药物类型、每日提醒数量、归档或中断操作",
                formulaSummary: "用药负担分 = 提醒负担 x 50% + 状态变化 x 28% + 用药复杂度 x 22%。处方药、导入来源和中断状态提高复核要求。",
                summary: regimenSummary(points: regimenPoints, requiredDays: requiredDays),
                formulaComponents: aggregateFormulaComponents(
                    topic: .regimenLoad,
                    points: regimenPoints,
                    componentBuilder: { point in
                        regimenLoadComponents(
                            doseCount: point.scheduledCount,
                            archivedCount: point.archivedMedicationCount,
                            interruptedCount: point.interruptedMedicationCount,
                            prescriptionCount: point.prescriptionMedicationCount,
                            importedCount: point.importedMedicationCount
                        )
                    }
                )
            ),
            metric(
                topic: .healthSignal,
                title: "健康信号",
                points: healthPoints,
                requiredDays: requiredDays,
                source: "用户授权的 Apple 健康心率、血压、血氧、体温、血糖等指标",
                formulaSummary: "健康信号分 = 指标稳定 x 68% + 样本覆盖 x 32%。只观察授权样本和用药记录的时间关系，不生成诊断。",
                summary: healthSummary(sampleCount: historicalHealthSignals.count),
                formulaComponents: aggregateFormulaComponents(
                    topic: .healthSignal,
                    points: healthPoints,
                    componentBuilder: { point in
                        healthSignalComponentsForPoint(point)
                    }
                )
            )
        ]

        let scoredMetrics = metrics.filter { $0.direction != .needsData && $0.topic != .healthSignal }
        let overall = scoredMetrics.isEmpty ? 0 : scoredMetrics.reduce(0) { $0 + $1.comparison.recentScore } / Double(scoredMetrics.count)
        let direction = dashboardDirection(metrics: scoredMetrics)
        let confidence = scoredMetrics.isEmpty ? 0 : scoredMetrics.reduce(0) { $0 + $1.comparison.confidenceScore } / Double(scoredMetrics.count)
        return MedicationTrendDashboard(
            overallScore: clamped(overall),
            direction: direction,
            title: dashboardTitle(direction: direction),
            summary: dashboardSummary(metrics: metrics, overallScore: overall, requiredDays: requiredDays),
            disciplineSummary: disciplineSummary(points: disciplinePoints, requiredDays: requiredDays),
            confidenceScore: clamped(confidence),
            dataQualitySummary: dataQualitySummary(metrics: metrics, requiredDays: requiredDays),
            metrics: metrics
        )
    }

    private func analysisDates(
        scheduledDoses: [ScheduledDose],
        latestEvents: [UUID: DoseEvent],
        calendar: Calendar,
        now: Date,
        limit: Int
    ) -> [DateOnly] {
        let dates = Set(scheduledDoses.map { dose in
            if let event = latestEvents[dose.id], dose.dueAt > now {
                return dateOnly(from: event.recordedAt, calendar: calendar)
            }
            return dateOnly(from: dose.dueAt, calendar: calendar)
        })
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
        interruptedMedicationCount: Int = 0,
        prescriptionMedicationCount: Int = 0,
        nonPrescriptionMedicationCount: Int = 0,
        importedMedicationCount: Int = 0,
        lifecycleEvents: [MedicationLifecycleEvent],
        healthSignalCount: Int,
        formulaComponents: [MedicationTrendFormulaComponent] = [],
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
            interruptedMedicationCount: interruptedMedicationCount,
            prescriptionMedicationCount: prescriptionMedicationCount,
            nonPrescriptionMedicationCount: nonPrescriptionMedicationCount,
            importedMedicationCount: importedMedicationCount,
            healthSignalCount: healthSignalCount,
            formulaComponents: formulaComponents,
            annotation: annotation
        )
    }

    private func uniquePlanContexts(
        for doses: [ScheduledDose],
        date: DateOnly,
        contextsByPlanID: [UUID: MedicationTrendPlanContext],
        lifecycleEventsByMedicationID: [UUID: [MedicationLifecycleEvent]],
        calendar: Calendar
    ) -> [MedicationTrendPlanContext] {
        var seenPlanIDs = Set<UUID>()
        var contexts: [MedicationTrendPlanContext] = []
        for dose in doses {
            guard seenPlanIDs.insert(dose.planID).inserted, let context = contextsByPlanID[dose.planID] else {
                continue
            }
            contexts.append(
                contextWithEffectiveLifecycleState(
                    context,
                    on: date,
                    lifecycleEvents: lifecycleEventsByMedicationID[context.medicationID] ?? [],
                    calendar: calendar
                )
            )
        }
        return contexts
    }

    private func contextWithEffectiveLifecycleState(
        _ context: MedicationTrendPlanContext,
        on date: DateOnly,
        lifecycleEvents: [MedicationLifecycleEvent],
        calendar: Calendar
    ) -> MedicationTrendPlanContext {
        guard !lifecycleEvents.isEmpty else {
            return context
        }
        let sortedEvents = lifecycleEvents.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let latestEventOnOrBeforeDate = sortedEvents.last { event in
            dateOnly(from: event.occurredAt, calendar: calendar) <= date
        }
        let effectiveState = latestEventOnOrBeforeDate?.state ?? .active
        return MedicationTrendPlanContext(
            planID: context.planID,
            medicationID: context.medicationID,
            medicationKind: context.medicationKind,
            inputSource: context.inputSource,
            lifecycleState: effectiveState
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

    private func disciplineComponents(doses: [ScheduledDose], latestEvents: [UUID: DoseEvent]) -> [MedicationTrendFormulaComponent] {
        guard !doses.isEmpty else {
            return [
                formulaComponent(id: "completion", title: "完成覆盖", weight: 0.62, score: 0, source: "已服用/已修正记录", explanation: "当天没有可计入的提醒。"),
                formulaComponent(id: "delay", title: "稍后影响", weight: 0.22, score: 0, source: "稍后记录", explanation: "当天没有可计入的提醒。"),
                formulaComponent(id: "skip", title: "忽略影响", weight: 0.16, score: 0, source: "忽略记录", explanation: "当天没有可计入的提醒。")
            ]
        }
        let events = doses.compactMap { latestEvents[$0.id] }
        let completed = events.filter { $0.status == .taken || $0.status == .corrected }.count
        let delayed = events.filter { $0.status == .delayed }.count
        let skipped = events.filter { $0.status == .skipped }.count
        let scheduled = Double(doses.count)
        return [
            formulaComponent(id: "completion", title: "完成覆盖", weight: 0.62, score: Double(completed) / scheduled, source: "已服用/已修正记录", explanation: "记录按计划完成的比例越高，纪律分越稳定。"),
            formulaComponent(id: "delay", title: "稍后影响", weight: 0.22, score: 1 - Double(delayed) / scheduled * 0.65, source: "稍后记录", explanation: "稍后不等同漏服，但会降低节奏稳定性。"),
            formulaComponent(id: "skip", title: "忽略影响", weight: 0.16, score: 1 - Double(skipped) / scheduled, source: "忽略记录", explanation: "忽略记录用于提示复盘，不判断治疗效果。")
        ]
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

    private func timingComponents(doses: [ScheduledDose], latestEvents: [UUID: DoseEvent]) -> [MedicationTrendFormulaComponent] {
        let completedEvents = doses.compactMap { dose -> (ScheduledDose, DoseEvent)? in
            guard let event = latestEvents[dose.id], event.status == .taken || event.status == .corrected || event.status == .delayed else {
                return nil
            }
            return (dose, event)
        }
        guard !completedEvents.isEmpty else {
            return [
                formulaComponent(id: "timeOffset", title: "时间偏差", weight: 0.7, score: doses.isEmpty ? 0 : 0.25, source: "提醒时间与记录时间", explanation: "缺少实际记录时只能给出低置信度估计。"),
                formulaComponent(id: "handledCoverage", title: "记录覆盖", weight: 0.3, score: 0, source: "已处理记录", explanation: "实际记录越完整，时间稳定判断越可靠。")
            ]
        }
        let averageDelayMinutes = completedEvents.reduce(0.0) { result, pair in
            result + abs(pair.1.recordedAt.timeIntervalSince(pair.0.dueAt)) / 60
        } / Double(completedEvents.count)
        let handledCoverage = doses.isEmpty ? 0 : Double(completedEvents.count) / Double(doses.count)
        return [
            formulaComponent(id: "timeOffset", title: "时间偏差", weight: 0.7, score: 1 - averageDelayMinutes / 180, source: "提醒时间与记录时间", explanation: "平均偏离提醒时间越小，时间稳定分越高。"),
            formulaComponent(id: "handledCoverage", title: "记录覆盖", weight: 0.3, score: handledCoverage, source: "已处理记录", explanation: "缺少记录会降低时间趋势可信度。")
        ]
    }

    private func doseChangeComponents(changeCount: Int) -> [MedicationTrendFormulaComponent] {
        [
            formulaComponent(id: "changeFrequency", title: "调整频率", weight: 0.55, score: changeCount == 0 ? 1 : max(0.35, 1 - Double(changeCount) * 0.18), source: "剂量变化记录", explanation: "频繁调整会提示需要分段观察记录。"),
            formulaComponent(id: "continuity", title: "观察连续性", weight: 0.45, score: changeCount == 0 ? 1 : max(0.45, 1 - Double(changeCount) * 0.12), source: "生效日期", explanation: "调整当天前后的趋势不混作疗效判断。")
        ]
    }

    private func regimenLoadComponents(
        doseCount: Int,
        archivedCount: Int,
        interruptedCount: Int,
        prescriptionCount: Int,
        importedCount: Int
    ) -> [MedicationTrendFormulaComponent] {
        let scheduleLoadScore = 1 - min(0.45, Double(max(0, doseCount - 4)) * 0.07)
        let lifecycleScore = 1 - min(0.35, Double(archivedCount + interruptedCount) * 0.1)
        let complexityScore = 1 - min(0.22, Double(prescriptionCount) * 0.04 + Double(importedCount) * 0.03)
        return [
            formulaComponent(id: "scheduleLoad", title: "提醒负担", weight: 0.5, score: scheduleLoadScore, source: "每日提醒数量", explanation: "提醒越密集，执行负担越高。"),
            formulaComponent(id: "lifecycle", title: "状态变化", weight: 0.28, score: lifecycleScore, source: "归档/中断操作", explanation: "归档或中断提示方案发生变化，应在复诊时说明。"),
            formulaComponent(id: "complexity", title: "用药复杂度", weight: 0.22, score: complexityScore, source: "药物类型和导入来源", explanation: "处方药和导入来源会提高复核要求。")
        ]
    }

    private func healthSignalScore(samples: [HealthSignalSample]) -> Double {
        guard !samples.isEmpty else {
            return 0
        }
        let groupedSamples = Dictionary(grouping: samples, by: \.kind)
        let stabilityScores = groupedSamples.map { kind, kindSamples in
            healthSignalStabilityScore(kind: kind, values: kindSamples.map(\.value))
        }
        let averageStability = stabilityScores.reduce(0, +) / Double(stabilityScores.count)
        let coverageScore = min(1, Double(samples.count) / 6)
        return clamped(averageStability * 0.7 + coverageScore * 0.3)
    }

    private func healthSignalComponents(samples: [HealthSignalSample]) -> [MedicationTrendFormulaComponent] {
        guard !samples.isEmpty else {
            return [
                formulaComponent(id: "stability", title: "指标稳定", weight: 0.68, score: 0, source: "授权 Apple 健康样本", explanation: "等待用户授权并产生样本。"),
                formulaComponent(id: "coverage", title: "样本覆盖", weight: 0.32, score: 0, source: "Apple 健康样本数量", explanation: "样本越完整，观察越可靠。")
            ]
        }
        let groupedSamples = Dictionary(grouping: samples, by: \.kind)
        let stabilityScores = groupedSamples.map { kind, kindSamples in
            healthSignalStabilityScore(kind: kind, values: kindSamples.map(\.value))
        }
        let averageStability = stabilityScores.reduce(0, +) / Double(stabilityScores.count)
        let coverageScore = min(1, Double(samples.count) / 6)
        return [
            formulaComponent(id: "stability", title: "指标稳定", weight: 0.68, score: averageStability, source: "授权 Apple 健康样本", explanation: "按同类指标中位数和波动幅度估计稳定度。"),
            formulaComponent(id: "coverage", title: "样本覆盖", weight: 0.32, score: coverageScore, source: "Apple 健康样本数量", explanation: "样本数量只影响观察可信度，不生成诊断。")
        ]
    }

    private func healthSignalStabilityScore(kind: HealthSignalKind, values: [Double]) -> Double {
        let sortedValues = values.sorted()
        guard let medianValue = median(sortedValues), sortedValues.count > 1 else {
            return 0.62
        }
        let deviations = sortedValues.map { abs($0 - medianValue) }.sorted()
        let medianDeviation = median(deviations) ?? 0
        let threshold = healthSignalVariationThreshold(kind: kind, medianValue: medianValue)
        let penalty = min(0.65, medianDeviation / threshold * 0.65)
        return clamped(1 - penalty)
    }

    private func healthSignalVariationThreshold(kind: HealthSignalKind, medianValue: Double) -> Double {
        switch kind {
        case .heartRate:
            return 20
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return 18
        case .bloodOxygen:
            return 4
        case .bodyTemperature:
            return 1.2
        case .bloodGlucose:
            return 45
        case .unknown:
            return max(1, abs(medianValue) * 0.2)
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }

    private func metric(
        topic: MedicationTrendTopic,
        title: String,
        points: [MedicationTrendPoint],
        requiredDays: Int,
        source: String,
        formulaSummary: String,
        summary: String,
        formulaComponents: [MedicationTrendFormulaComponent]
    ) -> MedicationTrendMetric {
        let comparison = periodComparison(points: points, topic: topic, requiredDays: requiredDays)
        let direction = direction(from: comparison, topic: topic, points: points, requiredDays: requiredDays)
        let score = averageScore(points)
        return MedicationTrendMetric(
            topic: topic,
            title: title,
            score: score,
            direction: direction,
            summary: points.count < requiredDays ? "至少记录 \(requiredDays) 个有提醒日期后，才生成稳定趋势。" : summary,
            dataSourceSummary: source,
            formulaSummary: formulaSummary,
            comparison: comparison,
            contributorSummary: contributorSummary(topic: topic, points: points, comparison: comparison),
            formulaComponents: formulaComponents,
            points: points
        )
    }

    private func weightedScore(_ components: [MedicationTrendFormulaComponent]) -> Double {
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return 0
        }
        return clamped(components.reduce(0) { $0 + clamped($1.score) * max(0, $1.weight) } / totalWeight)
    }

    private func formulaComponent(
        id: String,
        title: String,
        weight: Double,
        score: Double,
        source: String,
        explanation: String
    ) -> MedicationTrendFormulaComponent {
        MedicationTrendFormulaComponent(
            id: id,
            title: title,
            weight: max(0, weight),
            score: clamped(score),
            source: source,
            explanation: explanation
        )
    }

    private func aggregateFormulaComponents(
        topic: MedicationTrendTopic,
        points: [MedicationTrendPoint],
        componentBuilder: (MedicationTrendPoint) -> [MedicationTrendFormulaComponent]
    ) -> [MedicationTrendFormulaComponent] {
        let recent = Array(points.suffix(7))
        guard !recent.isEmpty else {
            return []
        }
        let grouped = Dictionary(grouping: recent.flatMap(componentBuilder), by: \.id)
        return grouped.keys.sorted().compactMap { id in
            guard let components = grouped[id], let first = components.first else {
                return nil
            }
            let averageScore = components.reduce(0) { $0 + $1.score } / Double(components.count)
            return formulaComponent(
                id: "\(topic.rawValue).\(id)",
                title: first.title,
                weight: first.weight,
                score: averageScore,
                source: first.source,
                explanation: first.explanation
            )
        }
    }

    private func disciplineComponentsForPoint(_ point: MedicationTrendPoint) -> [MedicationTrendFormulaComponent] {
        let scheduled = max(1, point.scheduledCount)
        return [
            formulaComponent(id: "completion", title: "完成覆盖", weight: 0.62, score: Double(point.completedCount) / Double(scheduled), source: "已服用/已修正记录", explanation: "记录按计划完成的比例越高，纪律分越稳定。"),
            formulaComponent(id: "delay", title: "稍后影响", weight: 0.22, score: 1 - Double(point.delayedCount) / Double(scheduled) * 0.65, source: "稍后记录", explanation: "稍后不等同漏服，但会降低节奏稳定性。"),
            formulaComponent(id: "skip", title: "忽略影响", weight: 0.16, score: 1 - Double(point.skippedCount) / Double(scheduled), source: "忽略记录", explanation: "忽略记录用于提示复盘，不判断治疗效果。")
        ]
    }

    private func timingComponentsForPoint(_ point: MedicationTrendPoint) -> [MedicationTrendFormulaComponent] {
        [
            formulaComponent(id: "timeOffset", title: "时间偏差", weight: 0.7, score: point.score, source: "提醒时间与记录时间", explanation: "平均偏离提醒时间越小，时间稳定分越高。"),
            formulaComponent(id: "handledCoverage", title: "记录覆盖", weight: 0.3, score: eventCoverageScore(points: [point]), source: "已处理记录", explanation: "缺少记录会降低时间趋势可信度。")
        ]
    }

    private func healthSignalComponentsForPoint(_ point: MedicationTrendPoint) -> [MedicationTrendFormulaComponent] {
        [
            formulaComponent(id: "stability", title: "指标稳定", weight: 0.68, score: point.healthSignalCount == 0 ? 0 : point.score, source: "授权 Apple 健康样本", explanation: "按同类指标中位数和波动幅度估计稳定度。"),
            formulaComponent(id: "coverage", title: "样本覆盖", weight: 0.32, score: point.healthSignalCount == 0 ? 0 : min(1, Double(point.healthSignalCount) / 6), source: "Apple 健康样本数量", explanation: "样本数量只影响观察可信度，不生成诊断。")
        ]
    }

    private func periodComparison(
        points: [MedicationTrendPoint],
        topic: MedicationTrendTopic,
        requiredDays: Int
    ) -> MedicationTrendPeriodComparison {
        let recent = Array(points.suffix(7))
        let previous = Array(points.dropLast(7).suffix(7))
        let recentScore = averageScore(recent)
        let previousScore = previous.isEmpty ? nil : averageScore(previous)
        let delta = previousScore.map { recentScore - $0 }
        let slope = linearSlopePerDay(points: recent)
        let trendStrength = trendStrengthScore(slopePerDay: slope, dayCount: recent.count)
        let recentScheduled = recent.reduce(0) { $0 + $1.scheduledCount }
        let previousScheduled = previous.reduce(0) { $0 + $1.scheduledCount }
        let eventCoverage = eventCoverageScore(points: recent)
        let healthCoverage = topic == .healthSignal ? healthCoverageScore(points: recent) : 1
        let dayCoverage = min(1, Double(recent.count) / Double(max(1, requiredDays))) * 0.48
        let previousCoverage = min(1, Double(previous.count) / 7) * 0.24
        let scheduledCoverage = min(1, Double(recentScheduled) / Double(max(1, recent.count))) * 0.12
        let confidence = clamped(dayCoverage + previousCoverage + eventCoverage * 0.12 + scheduledCoverage + healthCoverage * 0.04)
        let evidenceSummary = evidenceSummary(
            topic: topic,
            recent: recent,
            previous: previous,
            eventCoverage: eventCoverage,
            healthCoverage: healthCoverage
        )

        return MedicationTrendPeriodComparison(
            recentScore: clamped(recentScore),
            previousScore: previousScore.map(clamped),
            delta: delta,
            trendSlopePerDay: slope,
            trendStrengthScore: trendStrength,
            confidenceScore: confidence,
            recentDayCount: recent.count,
            previousDayCount: previous.count,
            recentScheduledCount: recentScheduled,
            previousScheduledCount: previousScheduled,
            evidenceSummary: evidenceSummary
        )
    }

    private func direction(
        from comparison: MedicationTrendPeriodComparison,
        topic: MedicationTrendTopic,
        points: [MedicationTrendPoint],
        requiredDays: Int
    ) -> MedicationTrendDirection {
        guard comparison.recentDayCount >= requiredDays else {
            return .needsData
        }
        if topic == .healthSignal, Array(points.suffix(7)).allSatisfy({ $0.healthSignalCount == 0 }) {
            return .needsData
        }
        guard let change = comparison.delta, comparison.previousDayCount >= 4 else {
            if comparison.trendStrengthScore >= 0.25 {
                if comparison.trendSlopePerDay > 0 {
                    return .improving
                }
                return comparison.recentScore >= 0.85 ? .fluctuating : .declining
            }
            return .stable
        }
        let blendedSignal = change * 0.65 + comparison.trendStrengthScore * (comparison.trendSlopePerDay >= 0 ? 0.35 : -0.35)
        if blendedSignal >= 0.08 {
            return .improving
        }
        if blendedSignal <= -0.08 {
            if comparison.recentScore >= 0.85 && change > -0.18 {
                return .fluctuating
            }
            return .declining
        }
        return .stable
    }

    private func dashboardDirection(metrics: [MedicationTrendMetric]) -> MedicationTrendDirection {
        guard !metrics.isEmpty else {
            return .needsData
        }
        let scored = metrics.filter { $0.direction != .needsData }
        guard !scored.isEmpty else {
            return .needsData
        }
        let recentOverall = scored.reduce(0) { $0 + $1.comparison.recentScore } / Double(scored.count)
        let decliningMetrics = scored.filter { $0.direction == .declining }
        let hasDecliningDiscipline = decliningMetrics.contains { $0.topic == .discipline && $0.comparison.recentScore < 0.85 }
        let hasSevereSingleDrop = decliningMetrics.contains { $0.comparison.recentScore < 0.55 }
        if hasDecliningDiscipline || recentOverall < 0.82 || decliningMetrics.count >= 2 || hasSevereSingleDrop {
            return .declining
        }
        if scored.contains(where: { $0.direction == .fluctuating || $0.direction == .declining }) {
            return .fluctuating
        }
        let disciplineDirection = scored.first { $0.topic == .discipline }?.direction
        if disciplineDirection == .improving || scored.allSatisfy({ $0.direction == .improving }) {
            return .improving
        }
        return disciplineDirection ?? .stable
    }

    private func eventCoverageScore(points: [MedicationTrendPoint]) -> Double {
        let scheduled = points.reduce(0) { $0 + $1.scheduledCount }
        guard scheduled > 0 else {
            return 0
        }
        let handled = points.reduce(0) { result, point in
            result + point.completedCount + point.delayedCount + point.skippedCount
        }
        return clamped(Double(handled) / Double(scheduled))
    }

    private func healthCoverageScore(points: [MedicationTrendPoint]) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        let daysWithHealthSignals = points.filter { $0.healthSignalCount > 0 }.count
        return clamped(Double(daysWithHealthSignals) / Double(points.count))
    }

    private func linearSlopePerDay(points: [MedicationTrendPoint]) -> Double {
        guard points.count >= 2 else {
            return 0
        }
        let indexedScores = points.enumerated().map { index, point in
            (x: Double(index), y: point.score)
        }
        let averageX = indexedScores.reduce(0) { $0 + $1.x } / Double(indexedScores.count)
        let averageY = indexedScores.reduce(0) { $0 + $1.y } / Double(indexedScores.count)
        let numerator = indexedScores.reduce(0) { result, pair in
            result + (pair.x - averageX) * (pair.y - averageY)
        }
        let denominator = indexedScores.reduce(0) { result, pair in
            result + pow(pair.x - averageX, 2)
        }
        guard denominator > 0 else {
            return 0
        }
        return numerator / denominator
    }

    private func trendStrengthScore(slopePerDay: Double, dayCount: Int) -> Double {
        guard dayCount >= 2 else {
            return 0
        }
        let projectedWeeklyChange = abs(slopePerDay) * Double(min(dayCount, 7) - 1)
        return clamped(projectedWeeklyChange)
    }

    private func evidenceSummary(
        topic: MedicationTrendTopic,
        recent: [MedicationTrendPoint],
        previous: [MedicationTrendPoint],
        eventCoverage: Double,
        healthCoverage: Double
    ) -> String {
        let recentScheduled = recent.reduce(0) { $0 + $1.scheduledCount }
        let handled = recent.reduce(0) { $0 + $1.completedCount + $1.delayedCount + $1.skippedCount }
        var parts = [
            "近 7 天覆盖 \(recent.count) 个有提醒日期",
            "前 7 天覆盖 \(previous.count) 个有提醒日期",
            "近期 \(handled)/\(recentScheduled) 项已有处理记录"
        ]
        if topic == .healthSignal {
            parts.append("健康数据覆盖 \(Int((healthCoverage * 100).rounded()))%")
        } else {
            parts.append("事件覆盖 \(Int((eventCoverage * 100).rounded()))%")
        }
        return parts.joined(separator: "，")
    }

    private func contributorSummary(
        topic: MedicationTrendTopic,
        points: [MedicationTrendPoint],
        comparison: MedicationTrendPeriodComparison
    ) -> [String] {
        let recent = Array(points.suffix(7))
        guard !recent.isEmpty else {
            return ["继续记录后生成贡献因素。"]
        }
        switch topic {
        case .discipline:
            let completed = recent.reduce(0) { $0 + $1.completedCount }
            let delayed = recent.reduce(0) { $0 + $1.delayedCount }
            let skipped = recent.reduce(0) { $0 + $1.skippedCount }
            return [
                "完成记录 \(completed) 项",
                "稍后记录 \(delayed) 项",
                "忽略记录 \(skipped) 项"
            ]
        case .timing:
            let delayed = recent.reduce(0) { $0 + $1.delayedCount }
            return [
                "按提醒时间和实际记录时间差估算",
                "近期稍后记录 \(delayed) 项",
                confidenceText(comparison.confidenceScore)
            ]
        case .doseChange:
            let changes = recent.reduce(0) { $0 + $1.doseChangeCount }
            return [
                "近期剂量变化 \(changes) 次",
                "剂量调整日前后需要分段观察",
                "只记录变化，不评价疗效"
            ]
        case .regimenLoad:
            let averageScheduled = Double(recent.reduce(0) { $0 + $1.scheduledCount }) / Double(recent.count)
            let prescription = recent.reduce(0) { $0 + $1.prescriptionMedicationCount }
            let interrupted = recent.reduce(0) { $0 + $1.interruptedMedicationCount }
            return [
                "平均每日 \(averageScheduled.formatted(.number.precision(.fractionLength(1)))) 项提醒",
                "处方药计划 \(prescription) 项次",
                "中断状态 \(interrupted) 项次"
            ]
        case .healthSignal:
            let samples = recent.reduce(0) { $0 + $1.healthSignalCount }
            return [
                "授权健康数据 \(samples) 条",
                "按同类指标中位数和波动幅度估算稳定度",
                "仅展示时间关系，不做诊断"
            ]
        }
    }

    private func confidenceText(_ confidence: Double) -> String {
        if confidence >= 0.82 {
            return "数据质量较高"
        }
        if confidence >= 0.55 {
            return "数据质量中等"
        }
        return "数据仍需积累"
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
        sampleCount == 0 ? "等待用户授权并导入 Apple 健康数据后，再观察生命体征与用药记录的时间关系。" : "已接入 \(sampleCount) 条授权健康数据，仅作为趋势和复诊资料的背景信号。"
    }

    private func dashboardTitle(direction: MedicationTrendDirection) -> String {
        switch direction {
        case .improving:
            return "用药趋势改善"
        case .stable:
            return "用药趋势平稳"
        case .fluctuating:
            return "用药趋势近期波动"
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

    private func dataQualitySummary(metrics: [MedicationTrendMetric], requiredDays: Int) -> String {
        let comparisons = metrics.map(\.comparison)
        guard !comparisons.isEmpty else {
            return "继续记录后提高趋势可信度。"
        }
        let averageConfidence = comparisons.reduce(0) { $0 + $1.confidenceScore } / Double(comparisons.count)
        let recentDayCount = comparisons.map(\.recentDayCount).max() ?? 0
        let previousDayCount = comparisons.map(\.previousDayCount).max() ?? 0
        if recentDayCount < requiredDays {
            return "近 7 天仅覆盖 \(recentDayCount) 个有提醒日期，达到 \(requiredDays) 天后再生成稳定趋势。"
        }
        if previousDayCount < 4 {
            return "近期记录已可查看，但前一周期不足，趋势方向以观察为主。"
        }
        if averageConfidence >= 0.82 {
            return "近期和前一周期记录较完整，可用于复诊沟通前的客观回顾。"
        }
        if averageConfidence >= 0.55 {
            return "趋势已有参考价值，继续补齐漏记和 Apple 健康授权数据会更稳。"
        }
        return "数据质量仍偏低，建议继续记录至少一周后再解读变化。"
    }

    private func loadAnnotation(doseCount: Int, archivedCount: Int, interruptedCount: Int, prescriptionCount: Int) -> String {
        if archivedCount > 0 {
            return "\(archivedCount) 个归档操作"
        }
        if interruptedCount > 0 {
            return "\(interruptedCount) 个中断状态"
        }
        if doseCount >= 5 {
            return "当天提醒较多"
        }
        if prescriptionCount > 0 {
            return "\(prescriptionCount) 个处方药计划"
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
