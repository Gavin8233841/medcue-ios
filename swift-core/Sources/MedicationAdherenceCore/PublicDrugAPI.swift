import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol DrugLabelProviding: Sendable {
    func label(for searchText: String) async throws -> MedicationLabel
}

public protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionHTTPDataLoader: HTTPDataLoading {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public enum DrugAPIError: Error, Sendable, Equatable {
    case invalidSearchText
    case invalidURL
    case unacceptableStatus(Int)
    case unsupportedContentType(String?)
    case transportFailure
    case decodingFailure
    case emptyResponse
    case unsupportedResponse

    fileprivate var permitsFallback: Bool {
        switch self {
        case .transportFailure, .emptyResponse:
            return true
        case let .unacceptableStatus(statusCode):
            return statusCode == 408 || statusCode == 429 || (500 ... 599).contains(statusCode)
        case .invalidSearchText,
             .invalidURL,
             .unsupportedContentType,
             .decodingFailure,
             .unsupportedResponse:
            return false
        }
    }
}

struct JSONHTTPClient: Sendable {
    private let dataLoader: any HTTPDataLoading

    init(dataLoader: any HTTPDataLoading) {
        self.dataLoader = dataLoader
    }

    func get<Response: Decodable>(
        _ responseType: Response.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader.data(for: URLRequest(url: url))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw DrugAPIError.transportFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DrugAPIError.unsupportedResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw DrugAPIError.unacceptableStatus(httpResponse.statusCode)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
        guard Self.isJSONContentType(contentType) else {
            throw DrugAPIError.unsupportedContentType(contentType)
        }
        guard !data.isEmpty else {
            throw DrugAPIError.emptyResponse
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw DrugAPIError.decodingFailure
        }
    }

    private static func isJSONContentType(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }
        let mediaType = rawValue
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let mediaType else { return false }
        return mediaType == "application/json"
            || mediaType == "text/json"
            || mediaType.hasSuffix("+json")
    }
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
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.fda.gov/drug/label.json") else {
            preconditionFailure("The bundled OpenFDA endpoint is invalid")
        }
        return url
    }()

    public var endpoint: URL
    private let httpClient: JSONHTTPClient

    public init(
        endpoint: URL = OpenFDADrugLabelProvider.defaultEndpoint,
        dataLoader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) {
        self.endpoint = endpoint
        httpClient = JSONHTTPClient(dataLoader: dataLoader)
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

        let decodedResponse = try await httpClient.get(OpenFDALabelResponse.self, from: url)
        guard let result = decodedResponse.results.first else {
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
        } catch let error as DrugAPIError where error.permitsFallback {
            return try await fallback.label(for: searchText)
        } catch let error as URLError where error.code != .cancelled {
            return try await fallback.label(for: searchText)
        } catch {
            throw error
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
