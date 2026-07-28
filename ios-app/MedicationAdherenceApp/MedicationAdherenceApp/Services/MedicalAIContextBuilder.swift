import Foundation
import MedicationAdherenceCore

struct MedicalAIContextBuilder {
    let medications: [StoredMedication]
    let plans: [StoredMedicationPlan]
    let tasks: [StoredDoseTask]
    let riskCards: [StoredRiskCard]
    let labels: [StoredMedicationLabel]

    func makeRequest(
        userMessage: String,
        consent: StoredAIConsent,
        environmentInsights: [MedicalAIEnvironmentInsight],
        localeIdentifier: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MedicalAIRequest {
        MedicalAIRequest(
            kind: .chat,
            userMessage: userMessage,
            authorization: consent.authorization,
            medicationSnapshots: medicationSnapshots(
                userMessage: userMessage,
                consent: consent,
                now: now,
                calendar: calendar
            ),
            environmentInsights: environmentInsights,
            localeIdentifier: localeIdentifier
        )
    }

    func tasksForContext(
        userMessage: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [StoredDoseTask] {
        guard isTodayQuestion(userMessage) else {
            return tasks.adherenceMeasurableTasks
        }
        return todayTasks(now: now, calendar: calendar)
    }

    private func medicationSnapshots(
        userMessage: String,
        consent: StoredAIConsent,
        now: Date,
        calendar: Calendar
    ) -> [MedicalAIMedicationSnapshot] {
        guard consent.sharesMedicationProfile else {
            return []
        }
        let measurableTasks = tasksForContext(
            userMessage: userMessage,
            now: now,
            calendar: calendar
        )
        return medications
            .filter { $0.lifecycleStatus == .active }
            .map { medication in
                let relatedTasks = measurableTasks.filter {
                    $0.medicationID == medication.id
                }
                let relatedPlans = consent.sharesMedicationPlans
                    ? plans
                        .filter { $0.medicationID == medication.id }
                        .compactMap { $0.corePlan(using: relatedTasks) }
                    : []
                let relatedRiskCards = consent.sharesRiskCards
                    ? riskCards
                        .filter {
                            $0.medicationID == medication.id && $0.isActive
                        }
                        .map(\.coreRiskCard)
                    : []
                return MedicalAIMedicationSnapshot(
                    medication: medication.coreMedication,
                    plans: relatedPlans,
                    scheduledDoses: consent.sharesDoseEvents
                        ? relatedTasks.map(\.coreScheduledDose)
                        : [],
                    doseEvents: consent.sharesDoseEvents
                        ? relatedTasks.compactMap(
                            \.coreDoseEventUsingEffectiveAdherenceDate
                        )
                        : [],
                    riskCards: relatedRiskCards,
                    labelSummary: consent.sharesDrugLabels
                        ? readableLabelSummary(for: medication)
                        : nil
                )
            }
    }

    private func todayTasks(
        now: Date,
        calendar: Calendar
    ) -> [StoredDoseTask] {
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        let relevantTasks = tasks.filter { task in
            guard task.isAdherenceMeasurable,
                  activeMedicationIDs.contains(task.medicationID)
            else {
                return false
            }
            if calendar.isDate(task.dueAt, inSameDayAs: now) {
                return true
            }
            return task.status == .delayed
                && task.recordedAt.map {
                    calendar.isDate($0, inSameDayAs: now)
                } == true
                && Self.isOpenStatus(task.status)
        }
        var tasksByLogicalDose: [String: StoredDoseTask] = [:]
        for task in relevantTasks {
            let key = DoseLogicalGroup.key(for: task)
            if let current = tasksByLogicalDose[key] {
                tasksByLogicalDose[key] = Self.preferredTask(current, task)
            } else {
                tasksByLogicalDose[key] = task
            }
        }
        return tasksByLogicalDose.values.sorted(by: Self.dueAtOrder)
    }

    func isTodayQuestion(_ userMessage: String) -> Bool {
        userMessage.contains("今日") || userMessage.contains("今天")
    }

    private func readableLabelSummary(
        for medication: StoredMedication
    ) -> ReadableLabelSummary? {
        guard let label = labels.first(where: {
            $0.medicationID == medication.id
        })?.coreLabel else {
            return nil
        }
        return ReadableLabelSummaryBuilder().build(from: label)
    }

    private static func preferredTask(
        _ lhs: StoredDoseTask,
        _ rhs: StoredDoseTask
    ) -> StoredDoseTask {
        let lhsScore = displayPriorityScore(for: lhs)
        let rhsScore = displayPriorityScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        let lhsReferenceDate = lhs.effectiveAdherenceDate
        let rhsReferenceDate = rhs.effectiveAdherenceDate
        if lhsReferenceDate != rhsReferenceDate {
            return lhsReferenceDate > rhsReferenceDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private static func displayPriorityScore(
        for task: StoredDoseTask
    ) -> Int {
        var score = task.recordedAt == nil ? 0 : 120
        switch task.status {
        case .taken, .corrected:
            score += 500
        case .skipped:
            score += 480
        case .delayed:
            score += 360
        case .pending:
            score += 300
        }
        return score
    }

    private static func isOpenStatus(_ status: StoredDoseStatus) -> Bool {
        status == .pending || status == .delayed
    }

    private static func dueAtOrder(
        _ lhs: StoredDoseTask,
        _ rhs: StoredDoseTask
    ) -> Bool {
        if lhs.dueAt == rhs.dueAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.dueAt < rhs.dueAt
    }
}

struct MedicalAIEnvironmentContextBuilder {
    func insights(
        userMessage: String,
        weatherHints: [WeatherMedicationHint],
        medications: [StoredMedication]
    ) -> [MedicalAIEnvironmentInsight] {
        guard MedicalAIEnvironmentQuestionDetector()
            .shouldAttachEnvironmentContext(to: userMessage) else {
            return []
        }

        if !weatherHints.isEmpty {
            return weatherHints.prefix(3).map { hint in
                MedicalAIEnvironmentInsight(
                    title: hint.title,
                    message: hint.message,
                    sourceSummary: hint.sourceSummary,
                    severityText: hint.severity.displayName
                )
            }
        }

        return EnvironmentMedicationInsightBuilder()
            .fallback(medications: activeProfiles(from: medications), limit: 3)
            .map { insight in
                MedicalAIEnvironmentInsight(
                    title: insight.title,
                    message: insight.message,
                    sourceSummary: insight.sourceSummary,
                    severityText: insight.severity.displayName
                )
            }
    }

    private func activeProfiles(
        from medications: [StoredMedication]
    ) -> [EnvironmentMedicationProfileItem] {
        medications
            .filter { $0.lifecycleStatus == .active }
            .map { medication in
                EnvironmentMedicationProfileItem(
                    id: medication.id,
                    displayName: MedicationNamePolicy.normalizedDisplayName(
                        medication.displayName
                    ) ?? "待核对药品名称",
                    genericName: medication.genericName,
                    form: medication.form,
                    notes: medication.notes,
                    isActive: true
                )
            }
    }
}
