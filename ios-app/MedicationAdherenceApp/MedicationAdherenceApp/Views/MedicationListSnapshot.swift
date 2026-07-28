import Foundation
import MedicationAdherenceCore

struct MedicationListSnapshot {
    static var empty: MedicationListSnapshot {
        MedicationListSnapshot(
        medications: [],
        plans: [],
        tasks: [],
        doseChanges: [],
        stocks: [],
        now: Date(timeIntervalSinceReferenceDate: 0),
        isPlaceholder: true
        )
    }

    let medications: [StoredMedication]
    let measurableTasks: [StoredDoseTask]
    let stockSummaries: [MedicationStockSummary]
    let activeTaskCount: Int
    let lowStockCount: Int
    let completionRate: Double
    let trendInputID: String
    let trendInput: MedicationListTrendInput
    let isPlaceholder: Bool

    private let plansByMedicationID: [UUID: StoredMedicationPlan]
    private let tasksByMedicationID: [UUID: [StoredDoseTask]]
    private let nextTasksByMedicationID: [UUID: StoredDoseTask]
    private let stockProjectionByMedicationID: [UUID: MedicationStockProjection]
    private let lifecycleByMedicationID: [UUID: MedicationLifecycleClassification]
    private let lifecycleCounts: [StoredMedicationLifecycleStatus: Int]

    static func refreshID(
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        stocks: [StoredMedicationStock],
        calendar: Calendar = .current
    ) -> String {
        let todayStart = calendar.startOfDay(for: Date())
        let todayTaskMarker = tasks.reduce(into: TodayTaskMarker()) { marker, task in
            guard calendar.isDate(task.dueAt, inSameDayAs: todayStart) else {
                return
            }
            marker.count += 1
            if task.status == .pending || task.status == .delayed {
                marker.openCount += 1
            }
            marker.statusVersion &+= task.status.versionValue
            marker.recordedVersion &+= Int(task.recordedAt?.timeIntervalSinceReferenceDate.rounded() ?? 0)
        }
        var parts: [String] = []
        parts.reserveCapacity(14)
        parts.append(String(stableMedicationSignature(medications)))
        parts.append(String(stablePlanSignature(plans)))
        parts.append(String(stableTaskSignature(tasks)))
        parts.append(String(todayTaskMarker.count))
        parts.append(String(todayTaskMarker.openCount))
        parts.append(String(todayTaskMarker.statusVersion))
        parts.append(String(todayTaskMarker.recordedVersion))
        parts.append(String(stableDoseChangeSignature(doseChanges)))
        parts.append(String(stableStockSignature(stocks)))
        return parts.joined(separator: "|")
    }

    init(
        medications: [StoredMedication],
        plans: [StoredMedicationPlan],
        tasks: [StoredDoseTask],
        doseChanges: [StoredMedicationDoseChange],
        stocks: [StoredMedicationStock],
        now: Date,
        calendar: Calendar = .current,
        isPlaceholder: Bool = false
    ) {
        self.medications = medications
        self.isPlaceholder = isPlaceholder
        let activeMedicationIDs = Set(
            medications
                .filter { $0.lifecycleStatus == .active }
                .map(\.id)
        )
        let measurableTasks = tasks.adherenceMeasurableTasks
        self.measurableTasks = measurableTasks
        self.plansByMedicationID = Dictionary(
            plans.reversed().map { ($0.medicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.tasksByMedicationID = Dictionary(grouping: measurableTasks, by: \.medicationID)
        let todayOpenTasks = measurableTasks
            .filter { task in
                activeMedicationIDs.contains(task.medicationID)
                    && calendar.isDateInToday(task.dueAt)
                    && (task.status == .pending || task.status == .delayed)
            }
            .sorted { lhs, rhs in
                if lhs.dueAt != rhs.dueAt {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        self.activeTaskCount = todayOpenTasks.count
        self.nextTasksByMedicationID = Dictionary(
            todayOpenTasks.map { ($0.medicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let estimator = MedicationStockEstimator()
        var projectionByMedicationID: [UUID: MedicationStockProjection] = [:]
        for stock in stocks {
            guard projectionByMedicationID[stock.medicationID] == nil else {
                continue
            }
            let relatedTasks = tasksByMedicationID[stock.medicationID] ?? []
            projectionByMedicationID[stock.medicationID] = estimator.project(
                stock: stock.coreStock,
                scheduledDoses: relatedTasks.map(\.coreScheduledDose),
                events: relatedTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
            )
        }
        self.stockProjectionByMedicationID = projectionByMedicationID
        self.stockSummaries = medications.filter { $0.lifecycleStatus == .active }.compactMap { medication in
            guard let projection = projectionByMedicationID[medication.id] else {
                return nil
            }
            return MedicationStockSummary(medication: medication, projection: projection)
        }
        .sorted { lhs, rhs in
            if lhs.projection.needsRefillReminder != rhs.projection.needsRefillReminder {
                return lhs.projection.needsRefillReminder && !rhs.projection.needsRefillReminder
            }
            return lhs.medication.displayName < rhs.medication.displayName
        }
        self.lowStockCount = stockSummaries.filter(\.projection.needsRefillReminder).count

        let scheduledDoses = measurableTasks.map(\.coreScheduledDose)
        let doseEvents = measurableTasks.compactMap(\.coreDoseEventUsingEffectiveAdherenceDate)
        self.completionRate = AdherenceInsightBuilder().build(
            scheduledDoses: scheduledDoses,
            events: doseEvents,
            timeZone: TimeZone.current,
            now: now
        ).completionRate

        let classifier = MedicationLifecycleClassifier()
        var lifecycleByMedicationID: [UUID: MedicationLifecycleClassification] = [:]
        var lifecycleCounts: [StoredMedicationLifecycleStatus: Int] = [:]
        for medication in medications {
            let classification = classifier.classify(
                medication: medication,
                plans: plans,
                tasks: tasksByMedicationID[medication.id] ?? [],
                now: now
            )
            lifecycleByMedicationID[medication.id] = classification
            lifecycleCounts[classification.displayStatus, default: 0] += 1
        }
        self.lifecycleByMedicationID = lifecycleByMedicationID
        self.lifecycleCounts = lifecycleCounts
        self.trendInput = MedicationListTrendInput(
            medications: medications,
            plans: plans,
            tasks: measurableTasks,
            doseChanges: doseChanges
        )
        self.trendInputID = medications.isEmpty
            && plans.isEmpty
            && measurableTasks.isEmpty
            && doseChanges.isEmpty
            && stocks.isEmpty
            ? "empty"
            : "ready"
    }

    func visibleMedications(for status: StoredMedicationLifecycleStatus) -> [StoredMedication] {
        medications.filter { lifecycleClassification(for: $0).displayStatus == status }
    }

    func count(for status: StoredMedicationLifecycleStatus) -> Int {
        lifecycleCounts[status, default: 0]
    }

    func plan(for medication: StoredMedication) -> StoredMedicationPlan? {
        plansByMedicationID[medication.id]
    }

    func taskCount(for medication: StoredMedication) -> Int {
        tasksByMedicationID[medication.id]?.count ?? 0
    }

    func nextTask(for medication: StoredMedication) -> StoredDoseTask? {
        nextTasksByMedicationID[medication.id]
    }

    func stockProjection(for medication: StoredMedication) -> MedicationStockProjection? {
        stockProjectionByMedicationID[medication.id]
    }

    func lifecycleClassification(for medication: StoredMedication) -> MedicationLifecycleClassification {
        lifecycleByMedicationID[medication.id] ?? MedicationLifecycleClassification(
            displayStatus: medication.lifecycleStatus,
            reason: medication.lifecycleStatus == .archived ? .archived : .ongoing,
            shouldPromptReview: false
        )
    }
}

struct MedicationListTrendInput {
    let medications: [StoredMedication]
    let plans: [StoredMedicationPlan]
    let tasks: [StoredDoseTask]
    let doseChanges: [StoredMedicationDoseChange]
}

func stableMedicationSignature(_ medications: [StoredMedication]) -> Int {
    var hasher = Hasher()
    hasher.combine(medications.count)
    for medication in medications {
        hasher.combine(medication.id)
        hasher.combine(medication.displayName)
        hasher.combine(medication.genericName)
        hasher.combine(medication.kindRaw)
        hasher.combine(medication.form)
        hasher.combine(medication.strength)
        hasher.combine(medication.inputSourceRaw)
        hasher.combine(medication.photoSymbolName)
        hasher.combine(medication.photoData?.count ?? 0)
        hasher.combine(medication.boxNumber)
        hasher.combine(medication.notes)
        hasher.combine(medication.lifecycleStatusRaw)
        hasher.combine(medication.isDemoContent)
        hasher.combine(Int(medication.createdAt.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stablePlanSignature(_ plans: [StoredMedicationPlan]) -> Int {
    var hasher = Hasher()
    hasher.combine(plans.count)
    for plan in plans {
        hasher.combine(plan.id)
        hasher.combine(plan.medicationID)
        hasher.combine(plan.doseValue)
        hasher.combine(plan.doseUnit)
        hasher.combine(plan.timingSummary)
        hasher.combine(plan.timeZonePolicyRaw)
        hasher.combine(plan.sourceNote)
        hasher.combine(plan.requiresUserConfirmation)
        hasher.combine(plan.courseStartAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(plan.courseEndAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(plan.reminderTimesRaw ?? "")
        hasher.combine(plan.reminderDeliveryRaw ?? "")
        hasher.combine(Int(plan.createdAt.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stableTaskSignature(_ tasks: [StoredDoseTask]) -> Int {
    var hasher = Hasher()
    hasher.combine(tasks.count)
    for task in tasks {
        hasher.combine(task.id)
        hasher.combine(task.medicationID)
        hasher.combine(task.planID)
        hasher.combine(Int(task.dueAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(task.doseValue)
        hasher.combine(task.doseUnit)
        hasher.combine(task.statusRaw)
        hasher.combine(task.recordedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(task.reason)
    }
    return hasher.finalize()
}

func stableDoseChangeSignature(_ doseChanges: [StoredMedicationDoseChange]) -> Int {
    var hasher = Hasher()
    hasher.combine(doseChanges.count)
    for change in doseChanges {
        hasher.combine(change.id)
        hasher.combine(change.medicationID)
        hasher.combine(change.planID)
        hasher.combine(change.previousDoseValue)
        hasher.combine(change.previousDoseUnit)
        hasher.combine(change.newDoseValue)
        hasher.combine(change.newDoseUnit)
        hasher.combine(Int(change.effectiveFrom.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(Int(change.changedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(change.note)
    }
    return hasher.finalize()
}

func stableStockSignature(_ stocks: [StoredMedicationStock]) -> Int {
    var hasher = Hasher()
    hasher.combine(stocks.count)
    for stock in stocks {
        hasher.combine(stock.id)
        hasher.combine(stock.medicationID)
        hasher.combine(stock.remainingQuantity)
        hasher.combine(stock.unit)
        hasher.combine(stock.lowStockThreshold)
        hasher.combine(Int(stock.lastUpdated.timeIntervalSinceReferenceDate.rounded()))
    }
    return hasher.finalize()
}

func stableRiskCardSignature(_ riskCards: [StoredRiskCard]) -> Int {
    var hasher = Hasher()
    hasher.combine(riskCards.count)
    for card in riskCards {
        hasher.combine(card.id)
        hasher.combine(card.medicationID)
        hasher.combine(card.kindRaw)
        hasher.combine(card.severityRaw)
        hasher.combine(card.sourceKindRaw)
        hasher.combine(card.displayPriority)
        hasher.combine(card.title)
        hasher.combine(card.message)
        hasher.combine(card.sourceTitle)
        hasher.combine(card.sourceExcerpt)
        hasher.combine(card.detectionSignature)
        hasher.combine(card.requiresProfessionalReview)
        hasher.combine(card.safetyNote)
        hasher.combine(Int(card.firstDetectedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(Int(card.lastDetectedAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(card.readAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.resolvedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.resolutionNote)
        hasher.combine(card.reviewedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.archivedAt.map { Int($0.timeIntervalSinceReferenceDate.rounded()) } ?? 0)
        hasher.combine(card.reviewNote)
    }
    return hasher.finalize()
}

func stableLifecycleEventSignature(_ lifecycleEvents: [StoredMedicationLifecycleEvent]) -> Int {
    var hasher = Hasher()
    hasher.combine(lifecycleEvents.count)
    for event in lifecycleEvents {
        hasher.combine(event.id)
        hasher.combine(event.medicationID)
        hasher.combine(event.statusRaw)
        hasher.combine(Int(event.occurredAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(event.note)
    }
    return hasher.finalize()
}

func stableHealthSignalSignature(_ healthSignals: [HealthSignalSample]) -> Int {
    var hasher = Hasher()
    hasher.combine(healthSignals.count)
    for signal in healthSignals {
        hasher.combine(signal.id)
        hasher.combine(signal.kind.rawValue)
        hasher.combine(Int(signal.measuredAt.timeIntervalSinceReferenceDate.rounded()))
        hasher.combine(signal.value)
        hasher.combine(signal.unit)
    }
    return hasher.finalize()
}

struct TodayTaskMarker {
    var count = 0
    var openCount = 0
    var statusVersion = 0
    var recordedVersion = 0
}

extension StoredDoseStatus {
    var versionValue: Int {
        switch self {
        case .pending:
            1
        case .taken:
            2
        case .delayed:
            3
        case .skipped:
            4
        case .corrected:
            5
        }
    }
}

struct MedicationStockSummary: Identifiable {
    let id: UUID
    let medication: StoredMedication
    let projection: MedicationStockProjection

    init(medication: StoredMedication, projection: MedicationStockProjection) {
        self.id = medication.id
        self.medication = medication
        self.projection = projection
    }
}
