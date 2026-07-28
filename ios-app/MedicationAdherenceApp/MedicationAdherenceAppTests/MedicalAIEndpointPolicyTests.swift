import Foundation
import Testing
@testable import MedicationAdherenceApp

struct MedicalAIEndpointPolicyTests {
    @Test
    func missingStoredConfigurationDefaultsToTheBrokerWithoutOverwritingExplicitProviders() {
        let fallback = MedicalAIConfigurationSelection.resolve(
            providerName: " ",
            modelName: nil,
            endpointURLString: ""
        )
        let explicitDoubao = MedicalAIConfigurationSelection.resolve(
            providerName: MedicalAIConfiguration.doubaoProviderName,
            modelName: MedicalAIConfiguration.doubaoDefaultModelName,
            endpointURLString: MedicalAIConfiguration.doubaoResponsesEndpoint
        )

        #expect(fallback.providerName == MedicalAIConfiguration.brokerProviderName)
        #expect(fallback.modelName == MedicalAIConfiguration.brokerDefaultModelName)
        #expect(fallback.endpointURLString == MedicalAIConfiguration.brokerRespondEndpoint)
        #expect(explicitDoubao.providerName == MedicalAIConfiguration.doubaoProviderName)
        #expect(explicitDoubao.endpointURLString == MedicalAIConfiguration.doubaoResponsesEndpoint)
    }

    @Test
    func releaseAcceptsCanonicalProviderEndpoints() throws {
        let doubao = configuration(
            providerName: MedicalAIConfiguration.doubaoProviderName,
            endpoint: MedicalAIConfiguration.doubaoResponsesEndpoint
        )
        let baichuan = configuration(
            providerName: MedicalAIConfiguration.baichuanProviderName,
            endpoint: MedicalAIConfiguration.baichuanChatEndpoint
        )

        #expect(try MedicalAIEndpointPolicy.validatedURL(for: doubao, enforcement: .release).absoluteString == MedicalAIConfiguration.doubaoResponsesEndpoint)
        #expect(try MedicalAIEndpointPolicy.validatedURL(for: baichuan, enforcement: .release).absoluteString == MedicalAIConfiguration.baichuanChatEndpoint)
    }

    @Test
    func releaseAcceptsOnlyTheCanonicalBrokerEndpoint() throws {
        let broker = configuration(
            providerName: MedicalAIConfiguration.brokerProviderName,
            endpoint: MedicalAIConfiguration.brokerRespondEndpoint
        )
        let decorated = configuration(
            providerName: MedicalAIConfiguration.brokerProviderName,
            endpoint: "\(MedicalAIConfiguration.brokerRespondEndpoint)?redirect=1"
        )

        #expect(
            try MedicalAIEndpointPolicy.validatedURL(
                for: broker,
                expectedProvider: .broker,
                enforcement: .release
            ).absoluteString == MedicalAIConfiguration.brokerRespondEndpoint
        )
        #expect(throws: MedicalAIEndpointPolicyError.unapprovedEndpoint) {
            try MedicalAIEndpointPolicy.validatedURL(for: decorated, enforcement: .release)
        }
    }

    @Test
    func releaseRejectsInsecureAndUntrustedEndpoints() {
        let insecure = configuration(
            providerName: MedicalAIConfiguration.doubaoProviderName,
            endpoint: "http://ark.cn-beijing.volces.com/api/v3/responses"
        )
        let lookalike = configuration(
            providerName: MedicalAIConfiguration.doubaoProviderName,
            endpoint: "https://ark.cn-beijing.volces.com.attacker.invalid/api/v3/responses"
        )

        #expect(throws: MedicalAIEndpointPolicyError.insecureTransport) {
            try MedicalAIEndpointPolicy.validatedURL(for: insecure, enforcement: .release)
        }
        #expect(throws: MedicalAIEndpointPolicyError.unapprovedEndpoint) {
            try MedicalAIEndpointPolicy.validatedURL(for: lookalike, enforcement: .release)
        }
    }

    @Test
    func releaseRejectsProviderEndpointMismatchAndURLDecoration() {
        let mismatch = configuration(
            providerName: MedicalAIConfiguration.baichuanProviderName,
            endpoint: MedicalAIConfiguration.doubaoResponsesEndpoint
        )
        let decorated = configuration(
            providerName: MedicalAIConfiguration.doubaoProviderName,
            endpoint: "\(MedicalAIConfiguration.doubaoResponsesEndpoint)?redirect=1"
        )

        #expect(throws: MedicalAIEndpointPolicyError.providerEndpointMismatch) {
            try MedicalAIEndpointPolicy.validatedURL(for: mismatch, enforcement: .release)
        }
        #expect(throws: MedicalAIEndpointPolicyError.unapprovedEndpoint) {
            try MedicalAIEndpointPolicy.validatedURL(for: decorated, enforcement: .release)
        }
    }

    @Test
    func debugAllowsAbsoluteCustomEndpointForLocalDevelopment() throws {
        let custom = configuration(
            providerName: "Local Debug Provider",
            endpoint: "http://127.0.0.1:8080/v1/responses"
        )

        let url = try MedicalAIEndpointPolicy.validatedURL(for: custom, enforcement: .debug)

        #expect(url.absoluteString == "http://127.0.0.1:8080/v1/responses")
    }

    @Test
    func debugStillRejectsRelativeOrCredentialBearingURLs() {
        let relative = configuration(providerName: "Debug", endpoint: "v1/responses")
        let credentialBearing = configuration(
            providerName: "Debug",
            endpoint: "https://user:password@example.invalid/v1/responses"
        )

        #expect(throws: MedicalAIEndpointPolicyError.invalidEndpoint) {
            try MedicalAIEndpointPolicy.validatedURL(for: relative, enforcement: .debug)
        }
        #expect(throws: MedicalAIEndpointPolicyError.embeddedCredentials) {
            try MedicalAIEndpointPolicy.validatedURL(for: credentialBearing, enforcement: .debug)
        }
    }

    @Test
    func responseURLMustRemainOnTheValidatedEndpoint() throws {
        let expected = try #require(URL(string: MedicalAIConfiguration.doubaoResponsesEndpoint))
        let redirected = try #require(URL(string: "https://example.invalid/api/v3/responses"))

        #expect(throws: MedicalAIEndpointPolicyError.unapprovedEndpoint) {
            try MedicalAIEndpointPolicy.validateResponseURL(redirected, expectedEndpoint: expected)
        }
        try MedicalAIEndpointPolicy.validateResponseURL(expected, expectedEndpoint: expected)
    }

    private func configuration(providerName: String, endpoint: String) -> MedicalAIConfiguration {
        MedicalAIConfiguration(
            providerName: providerName,
            modelName: "test-model",
            endpointURLString: endpoint,
            hasAPIKey: true
        )
    }
}
