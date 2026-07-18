import Foundation

public enum MedicationNamePolicy {
    public static func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningfulDisplayName(trimmed) else {
            return nil
        }
        return trimmed
    }

    public static func isMeaningfulDisplayName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let cjkCount = trimmed.unicodeScalars.filter(isCJK).count
        let latinCount = trimmed.unicodeScalars.filter(isLatinLetter).count
        return cjkCount >= 2 || latinCount >= 3
    }

    public static func aiDisplayName(for medication: Medication) -> String {
        if let displayName = normalizedDisplayName(medication.displayName) {
            return displayName
        }
        let descriptors = [medication.strength, medication.form]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        guard !descriptors.isEmpty else {
            return "待核对药品名称"
        }
        return "待核对药品名称（\(descriptors.joined(separator: " · "))）"
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF:
            true
        default:
            false
        }
    }

    private static func isLatinLetter(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A:
            true
        default:
            false
        }
    }
}
