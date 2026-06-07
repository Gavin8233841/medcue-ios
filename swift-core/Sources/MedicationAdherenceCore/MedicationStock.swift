import Foundation

public struct MedicationStock: Codable, Sendable, Equatable {
    public var medicationID: UUID
    public var remainingQuantity: Decimal
    public var unit: String
    public var lowStockThreshold: Decimal
    public var lastUpdated: Date

    public init(
        medicationID: UUID,
        remainingQuantity: Decimal,
        unit: String,
        lowStockThreshold: Decimal,
        lastUpdated: Date = Date()
    ) {
        self.medicationID = medicationID
        self.remainingQuantity = remainingQuantity
        self.unit = unit
        self.lowStockThreshold = lowStockThreshold
        self.lastUpdated = lastUpdated
    }
}

public enum MedicationStockIssueKind: String, Codable, Sendable, Equatable {
    case doseUnitMismatch
    case remainingBelowZero
    case insufficientConsumptionData
}

public struct MedicationStockIssue: Codable, Sendable, Equatable {
    public var kind: MedicationStockIssueKind
    public var message: String

    public init(kind: MedicationStockIssueKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct MedicationStockProjection: Codable, Sendable, Equatable {
    public var medicationID: UUID
    public var consumedQuantity: Decimal
    public var projectedRemainingQuantity: Decimal
    public var unit: String
    public var isLowStock: Bool
    public var needsRefillReminder: Bool
    public var averageDailyConsumption: Decimal?
    public var estimatedDaysRemaining: Int?
    public var trackedDayCount: Int
    public var message: String
    public var issues: [MedicationStockIssue]

    public init(
        medicationID: UUID,
        consumedQuantity: Decimal,
        projectedRemainingQuantity: Decimal,
        unit: String,
        isLowStock: Bool,
        needsRefillReminder: Bool,
        averageDailyConsumption: Decimal? = nil,
        estimatedDaysRemaining: Int? = nil,
        trackedDayCount: Int = 0,
        message: String,
        issues: [MedicationStockIssue]
    ) {
        self.medicationID = medicationID
        self.consumedQuantity = consumedQuantity
        self.projectedRemainingQuantity = projectedRemainingQuantity
        self.unit = unit
        self.isLowStock = isLowStock
        self.needsRefillReminder = needsRefillReminder
        self.averageDailyConsumption = averageDailyConsumption
        self.estimatedDaysRemaining = estimatedDaysRemaining
        self.trackedDayCount = trackedDayCount
        self.message = message
        self.issues = issues
    }
}

public struct MedicationStockEstimator: Sendable {
    public init() {}

    public func project(
        stock: MedicationStock,
        scheduledDoses: [ScheduledDose],
        events: [DoseEvent],
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = TimeZone.current
    ) -> MedicationStockProjection {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let latestEventByDoseID = Dictionary(grouping: events, by: \.scheduledDoseID).compactMapValues { doseEvents in
            doseEvents.sorted { $0.recordedAt < $1.recordedAt }.last
        }

        var consumedQuantity = Decimal(0)
        var hasUnitMismatch = false
        var consumedDayKeys: Set<String> = []

        for dose in scheduledDoses {
            guard let event = latestEventByDoseID[dose.id] else {
                continue
            }
            guard event.status == .taken || event.status == .corrected else {
                continue
            }
            guard normalized(dose.dose.unit).caseInsensitiveCompare(normalized(stock.unit)) == .orderedSame else {
                hasUnitMismatch = true
                continue
            }
            consumedQuantity += dose.dose.value
            consumedDayKeys.insert(dayKey(for: dose.dueAt, calendar: calendar))
        }

        let projectedRemaining = stock.remainingQuantity - consumedQuantity
        var issues: [MedicationStockIssue] = []

        if hasUnitMismatch {
            issues.append(MedicationStockIssue(
                kind: .doseUnitMismatch,
                message: "存在剂量单位与库存单位不一致的记录，请核对实物和已确认用药计划。"
            ))
        }

        if projectedRemaining < 0 {
            issues.append(MedicationStockIssue(
                kind: .remainingBelowZero,
                message: "估算剩余量低于 0，请核对库存数量、补记记录和剂量单位。"
            ))
        }

        let trackedDayCount = consumedDayKeys.count
        let averageDailyConsumption: Decimal?
        let estimatedDaysRemaining: Int?
        if trackedDayCount > 0 && consumedQuantity > 0 {
            averageDailyConsumption = consumedQuantity / Decimal(trackedDayCount)
            if let averageDailyConsumption, averageDailyConsumption > 0, projectedRemaining > 0 {
                estimatedDaysRemaining = max(0, Int(ceil((projectedRemaining / averageDailyConsumption).doubleValue)))
            } else {
                estimatedDaysRemaining = 0
            }
        } else {
            averageDailyConsumption = nil
            estimatedDaysRemaining = nil
            if !scheduledDoses.isEmpty {
                issues.append(MedicationStockIssue(
                    kind: .insufficientConsumptionData,
                    message: "还没有足够的已服用记录估算可用天数，请继续记录并核对实物库存。"
                ))
            }
        }

        let isLowStock = projectedRemaining <= stock.lowStockThreshold
        return MedicationStockProjection(
            medicationID: stock.medicationID,
            consumedQuantity: consumedQuantity,
            projectedRemainingQuantity: projectedRemaining,
            unit: stock.unit,
            isLowStock: isLowStock,
            needsRefillReminder: isLowStock,
            averageDailyConsumption: averageDailyConsumption,
            estimatedDaysRemaining: estimatedDaysRemaining,
            trackedDayCount: trackedDayCount,
            message: message(
                isLowStock: isLowStock,
                projectedRemaining: projectedRemaining,
                unit: stock.unit,
                estimatedDaysRemaining: estimatedDaysRemaining
            ),
            issues: issues
        )
    }

    private func message(
        isLowStock: Bool,
        projectedRemaining: Decimal,
        unit: String,
        estimatedDaysRemaining: Int?
    ) -> String {
        let daysText = estimatedDaysRemaining.map { "，按近期记录约可用 \($0) 天" } ?? ""
        if isLowStock {
            return "库存已达到低库存阈值，估算剩余 \(projectedRemaining) \(unit)\(daysText)，请及时核对实物库存。"
        }
        return "库存暂未达到低库存阈值，估算剩余 \(projectedRemaining) \(unit)\(daysText)。"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
