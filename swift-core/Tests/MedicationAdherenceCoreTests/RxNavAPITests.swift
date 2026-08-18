import Testing
@testable import MedicationAdherenceCore

@Test func rxNormConceptStoresIdentifier() async throws {
    let concept = RxNormConcept(rxcui: "5640")

    #expect(concept.rxcui == "5640")
}

@Test func drugClassStoresSource() async throws {
    let drugClass = DrugClass(classID: "N0000175722", name: "Analgesics", source: "MEDRT")

    #expect(drugClass.classID == "N0000175722")
    #expect(drugClass.name == "Analgesics")
    #expect(drugClass.source == "MEDRT")
}
