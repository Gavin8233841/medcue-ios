import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MedicationAdherenceCore

private struct StubHTTPDataLoader: HTTPDataLoading {
    var data: Data
    var statusCode: Int
    var contentType: String

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": contentType]
              )
        else {
            throw DrugAPIError.invalidURL
        }
        return (data, response)
    }
}

private struct FailingDrugLabelProvider: DrugLabelProviding {
    var error: DrugAPIError

    func label(for searchText: String) async throws -> MedicationLabel {
        throw error
    }
}

private struct StaticDrugLabelProvider: DrugLabelProviding {
    var value: MedicationLabel

    func label(for searchText: String) async throws -> MedicationLabel {
        value
    }
}

@Test func openFDARejectsUnacceptableHTTPStatusBeforeUsingPayload() async {
    let payload = Data(#"{"results":[{"openfda":{"brand_name":["Demo"]},"warnings":["Review"]}]}"#.utf8)
    let provider = OpenFDADrugLabelProvider(
        dataLoader: StubHTTPDataLoader(
            data: payload,
            statusCode: 503,
            contentType: "application/json"
        )
    )

    do {
        _ = try await provider.label(for: "Demo")
        Issue.record("Expected an unacceptable-status error")
    } catch let error as DrugAPIError {
        #expect(error == .unacceptableStatus(503))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func openFDARejectsNonJSONPayloadBeforeDecoding() async {
    let payload = Data(#"{"results":[{"openfda":{"brand_name":["Demo"]},"warnings":["Review"]}]}"#.utf8)
    let provider = OpenFDADrugLabelProvider(
        dataLoader: StubHTTPDataLoader(
            data: payload,
            statusCode: 200,
            contentType: "text/html"
        )
    )

    do {
        _ = try await provider.label(for: "Demo")
        Issue.record("Expected an unsupported-content-type error")
    } catch let error as DrugAPIError {
        #expect(error == .unsupportedContentType("text/html"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func rxNormUsesTheSharedHTTPValidationBoundary() async {
    let payload = Data(#"{"idGroup":{"rxnormId":["5640"]}}"#.utf8)
    let normalizer = RxNormDrugNameNormalizer(
        dataLoader: StubHTTPDataLoader(
            data: payload,
            statusCode: 429,
            contentType: "application/json"
        )
    )

    do {
        _ = try await normalizer.concept(for: "ibuprofen")
        Issue.record("Expected an unacceptable-status error")
    } catch let error as DrugAPIError {
        #expect(error == .unacceptableStatus(429))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func fallbackDoesNotHideInvalidRequestsOrSchemaDefects() async {
    let fallbackLabel = MedicationLabel(
        name: "Fallback",
        source: .demo,
        sections: [DrugLabelSection(title: "Warnings", text: "Review")]
    )
    let provider = FallbackDrugLabelProvider(
        primary: FailingDrugLabelProvider(error: .invalidSearchText),
        fallback: StaticDrugLabelProvider(value: fallbackLabel)
    )

    do {
        _ = try await provider.label(for: "ibuprofen")
        Issue.record("Invalid input must not be silently replaced with fallback data")
    } catch let error as DrugAPIError {
        #expect(error == .invalidSearchText)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func fallbackStillHandlesTransientServiceFailures() async throws {
    let fallbackLabel = MedicationLabel(
        name: "Fallback",
        source: .demo,
        sections: [DrugLabelSection(title: "Warnings", text: "Review")]
    )
    let provider = FallbackDrugLabelProvider(
        primary: FailingDrugLabelProvider(error: .unacceptableStatus(503)),
        fallback: StaticDrugLabelProvider(value: fallbackLabel)
    )

    let label = try await provider.label(for: "ibuprofen")
    #expect(label == fallbackLabel)
}
