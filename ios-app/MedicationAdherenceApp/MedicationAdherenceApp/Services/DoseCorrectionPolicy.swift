import Foundation

enum DoseCorrectionPolicy {
    static func taskReasonForSavedStatus(
        previousStatus: StoredDoseStatus,
        newStatus: StoredDoseStatus,
        trimmedNote: String
    ) -> String {
        if newStatus == .pending {
            return ""
        }
        if newStatus != previousStatus && isSystemGeneratedRecordNote(trimmedNote) {
            return ""
        }
        return trimmedNote
    }

    static func isSystemGeneratedRecordNote(_ text: String) -> Bool {
        [
            "自动记录为忽略",
            "未来提醒已停用",
            "用户撤销后等待确认",
            "用户将已处理记录撤销为待处理",
            "同一剂量重复提醒已随本次记录修正合并"
        ].contains { marker in
            text.contains(marker)
        }
    }
}
