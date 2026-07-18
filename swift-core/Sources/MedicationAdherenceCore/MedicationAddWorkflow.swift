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
            "拍照导入医嘱"
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
    public static let manualOption = MedicationAddOption(
        id: .manual,
        title: MedicationAddMethod.manual.title,
        description: "逐项填写药品名称、剂型、规格、剂量和提醒计划。",
        requiresUserConfirmation: true,
        requiresMedicalAIReview: false,
        requiresReliableExternalAPI: false,
        disclaimer: "手动录入内容需要按药品包装、说明书或医嘱核对。"
    )

    public static let options: [MedicationAddOption] = [
        manualOption,
        MedicationAddOption(
            id: .prescriptionDocumentOCR,
            title: MedicationAddMethod.prescriptionDocumentOCR.title,
            description: "拍摄或选择医嘱图片，提取文字后再逐项确认。",
            requiresUserConfirmation: true,
            requiresMedicalAIReview: true,
            requiresReliableExternalAPI: false,
            disclaimer: "识别结果仅用于辅助录入，必须按原始医嘱逐项核对并二次确认。"
        ),
        MedicationAddOption(
            id: .barcodeScan,
            title: MedicationAddMethod.barcodeScan.title,
            description: "扫描或输入药盒条码，记录后再核对药品信息。",
            requiresUserConfirmation: true,
            requiresMedicalAIReview: true,
            requiresReliableExternalAPI: false,
            disclaimer: "条码结果只用于辅助核对药盒来源，保存前必须核对药盒和说明书并二次确认。"
        )
    ]
}
