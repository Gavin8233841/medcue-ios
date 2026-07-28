import Foundation
import Testing
@testable import MedicationAdherenceCore

@Test
func doseAmountNormalizesKnownUnitWithoutChangingRawValue() throws {
    let amount = DoseAmount(value: 1, unit: " tablets ")

    #expect(amount.unit == " tablets ")
    #expect(amount.normalizedUnit.kind == .tablet)
    #expect(amount.normalizedUnit.canonicalUnit == "片")

    let roundTrip = try JSONDecoder().decode(
        DoseAmount.self,
        from: JSONEncoder().encode(amount)
    )
    #expect(roundTrip == amount)
}

@Test
func unknownDoseUnitRoundTripsWithoutLoss() throws {
    let amount = DoseAmount(value: 2, unit: "微量勺")

    #expect(amount.normalizedUnit.kind == .unknown)
    #expect(amount.normalizedUnit.originalUnit == "微量勺")
    #expect(try JSONDecoder().decode(DoseAmount.self, from: JSONEncoder().encode(amount)) == amount)
}

@Test
func drugLabelSectionDerivesTypedKindAndPreservesUnknownTitleAndText() throws {
    let warnings = DrugLabelSection(title: "禁忌与警示", text: "保留来源原文。")
    let unknown = DrugLabelSection(title: "储藏与运输补充说明", text: "原文不得丢失。")

    #expect(warnings.kind == .warnings)
    #expect(unknown.kind == .other)
    let roundTrip = try JSONDecoder().decode(
        DrugLabelSection.self,
        from: JSONEncoder().encode(unknown)
    )
    #expect(roundTrip == unknown)
    #expect(roundTrip.title == "储藏与运输补充说明")
    #expect(roundTrip.text == "原文不得丢失。")
}
