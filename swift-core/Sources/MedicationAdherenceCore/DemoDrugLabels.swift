import Foundation

public enum DemoDrugLabels {
    public static let all: [MedicationLabel] = [
        MedicationLabel(
            name: "Ibuprofen",
            source: .demo,
            sourceURL: URL(string: "https://open.fda.gov/apis/drug/label/"),
            sections: [
                DrugLabelSection(
                    title: "Warnings",
                    text: "Stomach bleeding warning applies. Ask a doctor or pharmacist before use if you are taking aspirin for heart attack or stroke, blood thinning medicine, steroid drug, or any other drug."
                ),
                DrugLabelSection(
                    title: "Dosage And Administration",
                    text: "Use only as directed on the label unless a doctor provides a different instruction."
                )
            ]
        ),
        MedicationLabel(
            name: "Acetaminophen",
            source: .demo,
            sourceURL: URL(string: "https://open.fda.gov/apis/drug/label/"),
            sections: [
                DrugLabelSection(
                    title: "Warnings",
                    text: "Liver warning: severe liver damage may occur if you take more than directed or with other drugs containing acetaminophen. Alcohol warning: ask a doctor before use if you consume alcoholic drinks."
                )
            ]
        ),
        MedicationLabel(
            name: "Artificial Tears",
            source: .demo,
            sections: [
                DrugLabelSection(
                    title: "Use",
                    text: "Temporary relief of burning and irritation due to dryness of the eye."
                ),
                DrugLabelSection(
                    title: "Warnings",
                    text: "For external use only. Stop use and ask a doctor if you experience eye pain, changes in vision, continued redness, or irritation."
                )
            ]
        )
    ]
}

