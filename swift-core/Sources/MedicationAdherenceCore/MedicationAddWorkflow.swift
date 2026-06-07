import Foundation

public enum MedicationAddMethod: String, Codable, Sendable, CaseIterable, Equatable {
    case manual
    case prescriptionDocumentOCR
    case barcodeScan

    public var title: String {
        switch self {
        case .manual:
            "手动添加"
        case .prescriptionDocumentOCR:
            "医嘱/OCR 导入"
        case .barcodeScan:
            "药盒条码扫描"
        }
    }
}

public struct MedicationAddOption: Codable, Identifiable, Sendable, Equatable {
    public var id: MedicationAddMethod
    public var title: String
    public var description: String
    public var requiresUserConfirmation: Bool
    public var requiresMedicalAIReview: Bool
    public var requiresReliableExternalAPI: Bool
    public var disclaimer: String

    public init(
        id: MedicationAddMethod,
        title: String,
        description: String,
        requiresUserConfirmation: Bool,
        requiresMedicalAIReview: Bool,
        requiresReliableExternalAPI: Bool,
        disclaimer: String
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.requiresUserConfirmation = requiresUserConfirmation
        self.requiresMedicalAIReview = requiresMedicalAIReview
        self.requiresReliableExternalAPI = requiresReliableExternalAPI
        self.disclaimer = disclaimer
    }
}

public enum MedicationAddWorkflow {
    public static let options: [MedicationAddOption] = [
        MedicationAddOption(
            id: .manual,
            title: MedicationAddMethod.manual.title,
            description: "用户逐项填写药品名称、剂型、规格、剂量和提醒计划。",
            requiresUserConfirmation: true,
            requiresMedicalAIReview: false,
            requiresReliableExternalAPI: false,
            disclaimer: "手动录入内容需要按药品包装、说明书或医嘱核对。"
        ),
        MedicationAddOption(
            id: .prescriptionDocumentOCR,
            title: MedicationAddMethod.prescriptionDocumentOCR.title,
            description: "识别手写或打印医嘱，生成待确认导入草稿。",
            requiresUserConfirmation: true,
            requiresMedicalAIReview: true,
            requiresReliableExternalAPI: false,
            disclaimer: "OCR 或医疗 AI 返回结果必须由用户按原始医嘱二次确认。"
        ),
        MedicationAddOption(
            id: .barcodeScan,
            title: MedicationAddMethod.barcodeScan.title,
            description: "扫描药盒条码并通过可靠数据源补全药品信息。",
            requiresUserConfirmation: true,
            requiresMedicalAIReview: true,
            requiresReliableExternalAPI: true,
            disclaimer: "条码结果只用于辅助录入，保存前必须核对药盒、说明书和导入来源。"
        )
    ]
}
