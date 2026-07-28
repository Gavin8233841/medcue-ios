import Foundation

public enum DemoDrugLabels {
    public static let all: [MedicationLabel] = [
        MedicationLabel(
            name: "Ibuprofen",
            source: .demo,
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=ibuprofen"),
            sections: [
                DrugLabelSection(
                    title: "禁忌或不得使用",
                    text: "曾对布洛芬、阿司匹林或其他止痛退热药发生过敏反应者不应使用；冠状动脉搭桥手术前后不应使用。"
                ),
                DrugLabelSection(
                    title: "警示",
                    text: "布洛芬属于 NSAID，可能导致严重胃出血。60 岁及以上、既往胃溃疡或出血、每日饮酒 3 杯以上（alcohol）、超过说明书用量或时间时风险更高。"
                ),
                DrugLabelSection(
                    title: "药物相互作用",
                    text: "正在使用阿司匹林预防心梗或卒中（stroke）、抗凝药、激素类药物，或其他含 NSAID 药物时，使用前应咨询医生或药师。"
                ),
                DrugLabelSection(
                    title: "不良反应",
                    text: "若出现胃痛、呕血、黑便、持续胃部不适、胸痛、呼吸困难、皮疹或面部肿胀等，应停止使用并尽快寻求医疗帮助。"
                ),
                DrugLabelSection(
                    title: "用法用量",
                    text: "请按药盒或说明书方向使用；如医生另有医嘱，应以医嘱为准。App 只记录提醒，不自动改变剂量。"
                )
            ]
        ),
        MedicationLabel(
            name: "Acetaminophen",
            source: .demo,
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=acetaminophen"),
            sections: [
                DrugLabelSection(
                    title: "警示",
                    text: "对乙酰氨基酚可能导致严重肝损伤，尤其是 24 小时内超过 4000 mg、同时使用其他含对乙酰氨基酚药物，或每日饮酒 3 杯以上时。"
                ),
                DrugLabelSection(
                    title: "禁忌或不得使用",
                    text: "正在使用其他含对乙酰氨基酚的处方或非处方药时，使用前必须核对成分，避免重复用药。"
                ),
                DrugLabelSection(
                    title: "不良反应",
                    text: "可能出现严重皮肤反应，如皮肤发红、水疱、皮疹；若出现应停止使用并尽快寻求医疗帮助。"
                ),
                DrugLabelSection(
                    title: "用法用量",
                    text: "请按药盒、说明书或医嘱确认剂量和间隔；App 只提供提醒和记录。"
                )
            ]
        ),
        MedicationLabel(
            name: "Artificial Tears",
            source: .demo,
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=artificial%20tears"),
            sections: [
                DrugLabelSection(
                    title: "适应症",
                    text: "Temporary relief of burning and irritation due to dryness of the eye."
                ),
                DrugLabelSection(
                    title: "警示",
                    text: "仅供外用。为避免污染，不要让瓶口接触任何表面；溶液变色或浑浊时不要使用。"
                ),
                DrugLabelSection(
                    title: "不良反应",
                    text: "若出现眼痛、视力变化、持续红肿或刺激，或症状加重、持续超过 72 小时，应停止使用并咨询医生。"
                ),
                DrugLabelSection(
                    title: "用法用量",
                    text: "可按需向受影响眼睛滴入 1 到 2 滴；具体频次以说明书、医生或药师建议为准。"
                )
            ]
        ),
        MedicationLabel(
            name: "Loratadine",
            source: .demo,
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=loratadine"),
            sections: [
                DrugLabelSection(
                    title: "适应症",
                    text: "用于暂时缓解花粉症或其他上呼吸道过敏相关的流涕、眼痒流泪、打喷嚏、鼻或咽喉发痒。"
                ),
                DrugLabelSection(
                    title: "禁忌或不得使用",
                    text: "曾对氯雷他定或本品任何成分发生过敏反应者不应使用。"
                ),
                DrugLabelSection(
                    title: "注意事项",
                    text: "有肝病或肾病者使用前应咨询医生，由医生判断是否需要不同剂量；妊娠期或哺乳期使用前应咨询专业人员。"
                ),
                DrugLabelSection(
                    title: "不良反应",
                    text: "不要超过说明书用量；超过用量可能导致嗜睡。若发生过敏反应，应停止使用并尽快寻求医疗帮助。"
                ),
                DrugLabelSection(
                    title: "用法用量",
                    text: "按说明书或医生、药师建议使用；App 只记录提醒，不自动改变剂量。"
                )
            ]
        ),
        MedicationLabel(
            name: "Vitamin D3",
            source: .demo,
            sourceURL: URL(string: "https://ods.od.nih.gov/factsheets/VitaminD-Consumer/"),
            sections: [
                DrugLabelSection(
                    title: "注意事项",
                    text: "维生素 D 过量可能导致血钙升高。已有高钙血症、高磷血症、肾功能不全或正在接受相关治疗者，使用前应咨询医生或药师。"
                ),
                DrugLabelSection(
                    title: "药物相互作用",
                    text: "与高剂量含钙制剂、其他维生素 D 制剂、噻嗪类利尿药或洋地黄类药物合用时，需咨询医生或药师并关注血钙风险。"
                ),
                DrugLabelSection(
                    title: "不良反应",
                    text: "若出现明显乏力、食欲下降、恶心、便秘、口渴或尿量增多等疑似高钙相关表现，应记录并咨询医生或药师。"
                ),
                DrugLabelSection(
                    title: "儿童用药",
                    text: "儿童应在成人监护下使用，并按说明书或医生、药师建议核对剂量。"
                ),
                DrugLabelSection(
                    title: "老年用药",
                    text: "老年人长期使用前请咨询医生或药师。"
                )
            ]
        )
    ]
}
