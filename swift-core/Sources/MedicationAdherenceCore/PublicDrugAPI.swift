import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol DrugLabelProviding: Sendable {
    func label(for searchText: String) async throws -> MedicationLabel
}

public enum DrugAPIError: Error, Sendable, Equatable {
    case invalidSearchText
    case invalidURL
    case emptyResponse
    case unsupportedResponse
}

public struct DemoDrugLabelProvider: DrugLabelProviding {
    private let labels: [String: MedicationLabel]

    public init(labels: [MedicationLabel] = DemoDrugLabels.all) {
        var indexed: [String: MedicationLabel] = [:]
        for label in labels {
            indexed[label.name.normalizedDrugKey] = label
        }
        self.labels = indexed
    }

    public func label(for searchText: String) async throws -> MedicationLabel {
        let key = searchText.normalizedDrugKey
        guard !key.isEmpty else {
            throw DrugAPIError.invalidSearchText
        }
        guard let label = labels[key] else {
            throw DrugAPIError.emptyResponse
        }
        return label
    }
}

public struct OpenFDADrugLabelProvider: DrugLabelProviding {
    public var endpoint: URL

    public init(endpoint: URL = URL(string: "https://api.fda.gov/drug/label.json")!) {
        self.endpoint = endpoint
    }

    public func label(for searchText: String) async throws -> MedicationLabel {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DrugAPIError.invalidSearchText
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search", value: "openfda.brand_name:\(trimmed)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else {
            throw DrugAPIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OpenFDALabelResponse.self, from: data)
        guard let result = response.results.first else {
            throw DrugAPIError.emptyResponse
        }

        let sections = result.sections
        guard !sections.isEmpty else {
            throw DrugAPIError.unsupportedResponse
        }

        return MedicationLabel(
            name: result.openfda?.brandName?.first ?? trimmed,
            source: .openFDA,
            sourceURL: url,
            sections: sections
        )
    }
}

public struct FallbackDrugLabelProvider: DrugLabelProviding {
    private let primary: any DrugLabelProviding
    private let fallback: any DrugLabelProviding

    public init(primary: any DrugLabelProviding, fallback: any DrugLabelProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    public func label(for searchText: String) async throws -> MedicationLabel {
        do {
            return try await primary.label(for: searchText)
        } catch {
            return try await fallback.label(for: searchText)
        }
    }
}

private struct OpenFDALabelResponse: Decodable {
    var results: [OpenFDALabelResult]
}

private struct OpenFDALabelResult: Decodable {
    var openfda: OpenFDAInfo?
    var warnings: [String]?
    var doNotUse: [String]?
    var askDoctor: [String]?
    var askDoctorOrPharmacist: [String]?
    var stopUse: [String]?
    var dosageAndAdministration: [String]?
    var adverseReactions: [String]?
    var drugInteractions: [String]?

    enum CodingKeys: String, CodingKey {
        case openfda
        case warnings
        case doNotUse = "do_not_use"
        case askDoctor = "ask_doctor"
        case askDoctorOrPharmacist = "ask_doctor_or_pharmacist"
        case stopUse = "stop_use"
        case dosageAndAdministration = "dosage_and_administration"
        case adverseReactions = "adverse_reactions"
        case drugInteractions = "drug_interactions"
    }

    var sections: [DrugLabelSection] {
        [
            ("Warnings", warnings),
            ("Do Not Use", doNotUse),
            ("Ask Doctor", askDoctor),
            ("Ask Doctor Or Pharmacist", askDoctorOrPharmacist),
            ("Stop Use", stopUse),
            ("Dosage And Administration", dosageAndAdministration),
            ("Adverse Reactions", adverseReactions),
            ("Drug Interactions", drugInteractions)
        ]
        .compactMap { title, values in
            guard let text = values?.joined(separator: "\n"), !text.isEmpty else {
                return nil
            }
            return DrugLabelSection(title: title, text: text)
        }
    }
}

private struct OpenFDAInfo: Decodable {
    var brandName: [String]?

    enum CodingKeys: String, CodingKey {
        case brandName = "brand_name"
    }
}

extension String {
    var normalizedDrugKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

