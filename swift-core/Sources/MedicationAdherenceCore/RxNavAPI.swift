import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RxNormConcept: Codable, Sendable, Equatable {
    public var rxcui: String

    public init(rxcui: String) {
        self.rxcui = rxcui
    }
}

public protocol DrugNameNormalizing: Sendable {
    func concept(for drugName: String) async throws -> RxNormConcept
}

public struct RxNormDrugNameNormalizer: DrugNameNormalizing {
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://rxnav.nlm.nih.gov/REST/Prescribe/rxcui.json") else {
            preconditionFailure("The bundled RxNorm endpoint is invalid")
        }
        return url
    }()

    public var endpoint: URL
    private let httpClient: JSONHTTPClient

    public init(
        endpoint: URL = RxNormDrugNameNormalizer.defaultEndpoint,
        dataLoader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) {
        self.endpoint = endpoint
        httpClient = JSONHTTPClient(dataLoader: dataLoader)
    }

    public func concept(for drugName: String) async throws -> RxNormConcept {
        let trimmed = drugName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DrugAPIError.invalidSearchText
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "search", value: "2")
        ]
        guard let url = components?.url else {
            throw DrugAPIError.invalidURL
        }

        let response = try await httpClient.get(RxNormRxcuiResponse.self, from: url)
        guard let rxcui = response.idGroup.rxnormId?.first else {
            throw DrugAPIError.emptyResponse
        }
        return RxNormConcept(rxcui: rxcui)
    }
}

public struct DrugClass: Codable, Sendable, Equatable {
    public var classID: String
    public var name: String
    public var source: String?

    public init(classID: String, name: String, source: String? = nil) {
        self.classID = classID
        self.name = name
        self.source = source
    }
}

public protocol DrugClassProviding: Sendable {
    func classes(forRxcui rxcui: String) async throws -> [DrugClass]
}

public struct RxClassDrugClassProvider: DrugClassProviding {
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://rxnav.nlm.nih.gov/REST/rxclass/class/byRxcui.json") else {
            preconditionFailure("The bundled RxClass endpoint is invalid")
        }
        return url
    }()

    public var endpoint: URL
    private let httpClient: JSONHTTPClient

    public init(
        endpoint: URL = RxClassDrugClassProvider.defaultEndpoint,
        dataLoader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) {
        self.endpoint = endpoint
        httpClient = JSONHTTPClient(dataLoader: dataLoader)
    }

    public func classes(forRxcui rxcui: String) async throws -> [DrugClass] {
        let trimmed = rxcui.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DrugAPIError.invalidSearchText
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "rxcui", value: trimmed)
        ]
        guard let url = components?.url else {
            throw DrugAPIError.invalidURL
        }

        let response = try await httpClient.get(RxClassResponse.self, from: url)
        let classes = response.rxclassDrugInfoList?.rxclassDrugInfo.compactMap { info -> DrugClass? in
            guard let concept = info.rxclassMinConceptItem else {
                return nil
            }
            return DrugClass(
                classID: concept.classId,
                name: concept.className,
                source: info.relaSource
            )
        } ?? []

        guard !classes.isEmpty else {
            throw DrugAPIError.emptyResponse
        }
        return classes
    }
}

private struct RxNormRxcuiResponse: Decodable {
    var idGroup: RxNormIDGroup
}

private struct RxNormIDGroup: Decodable {
    var rxnormId: [String]?
}

private struct RxClassResponse: Decodable {
    var rxclassDrugInfoList: RxClassDrugInfoList?
}

private struct RxClassDrugInfoList: Decodable {
    var rxclassDrugInfo: [RxClassDrugInfo]
}

private struct RxClassDrugInfo: Decodable {
    var relaSource: String?
    var rxclassMinConceptItem: RxClassMinConceptItem?
}

private struct RxClassMinConceptItem: Decodable {
    var classId: String
    var className: String
}
