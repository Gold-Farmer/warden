import Foundation
import Testing
@testable import Warden

@Suite("Credentials")
struct CredentialsTests {

    // MARK: - Provider Mapping

    @Test("Each credential case maps to correct provider")
    func providerMapping() {
        let cases: [(Credentials, Provider)] = [
            (.aws(accessKeyId: "k", secretAccessKey: "s", region: "r"), .aws),
            (.gcp(serviceAccountJSON: Data()), .gcp),
            (.azure(tenantId: "t", clientId: "c", clientSecret: "s", subscriptionId: "sub"), .azure),
            (.cloudflare(apiToken: "t", accountId: "a"), .cloudflare),
            (.openai(apiKey: "k"), .openai),
            (.openaiOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date(), accountId: "id"), .openai),
            (.anthropic(apiKey: "k"), .anthropic),
            (.anthropicOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date()), .anthropic),
            (.gemini(apiKey: "k"), .gemini),
            (.grok(apiKey: "k"), .grok),
        ]

        for (creds, expectedProvider) in cases {
            #expect(creds.provider == expectedProvider)
        }
    }

    // MARK: - Validation

    @Test("Valid credentials pass isValid")
    func validCredentials() {
        #expect(Credentials.openai(apiKey: "sk-123").isValid)
        #expect(Credentials.anthropic(apiKey: "sk-ant-123").isValid)
        #expect(Credentials.aws(accessKeyId: "A", secretAccessKey: "S", region: "us-east-1").isValid)
        #expect(Credentials.cloudflare(apiToken: "t", accountId: "a").isValid)
        #expect(Credentials.openaiOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date(), accountId: "id").isValid)
        #expect(Credentials.anthropicOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date()).isValid)
    }

    @Test("Empty API key is invalid")
    func emptyKeyInvalid() {
        #expect(!Credentials.openai(apiKey: "").isValid)
        #expect(!Credentials.anthropic(apiKey: "").isValid)
        #expect(!Credentials.gemini(apiKey: "").isValid)
        #expect(!Credentials.grok(apiKey: "").isValid)
    }

    @Test("Empty required fields are invalid")
    func emptyFieldsInvalid() {
        #expect(!Credentials.aws(accessKeyId: "", secretAccessKey: "s", region: "r").isValid)
        #expect(!Credentials.aws(accessKeyId: "k", secretAccessKey: "", region: "r").isValid)
        #expect(!Credentials.aws(accessKeyId: "k", secretAccessKey: "s", region: "").isValid)
        #expect(!Credentials.cloudflare(apiToken: "", accountId: "a").isValid)
        #expect(!Credentials.cloudflare(apiToken: "t", accountId: "").isValid)
        #expect(!Credentials.azure(tenantId: "", clientId: "c", clientSecret: "s", subscriptionId: "sub").isValid)
    }

    @Test("OAuth with empty tokens is invalid")
    func emptyOAuthInvalid() {
        #expect(!Credentials.openaiOAuth(accessToken: "", refreshToken: "r", expiresAt: Date(), accountId: "id").isValid)
        #expect(!Credentials.openaiOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date(), accountId: "").isValid)
        #expect(!Credentials.anthropicOAuth(accessToken: "", refreshToken: "r", expiresAt: Date()).isValid)
        #expect(!Credentials.anthropicOAuth(accessToken: "a", refreshToken: "", expiresAt: Date()).isValid)
    }

    // MARK: - Codable Round-Trip

    @Test("JSON encode and decode round-trip for all types")
    func codableRoundTrip() throws {
        let cases: [Credentials] = [
            .aws(accessKeyId: "AKIA", secretAccessKey: "secret", region: "us-east-1", sessionToken: "tok"),
            .gcp(serviceAccountJSON: Data("{\"type\":\"service_account\"}".utf8)),
            .azure(tenantId: "t", clientId: "c", clientSecret: "s", subscriptionId: "sub"),
            .cloudflare(apiToken: "cf-tok", accountId: "cf-acct"),
            .openai(apiKey: "sk-openai", organizationId: "org-123"),
            .openai(apiKey: "sk-openai-no-org", organizationId: nil),
            .openaiOAuth(accessToken: "oat", refreshToken: "ort", expiresAt: Date(timeIntervalSince1970: 1700000000), accountId: "acct"),
            .anthropic(apiKey: "sk-ant-key"),
            .anthropicOAuth(accessToken: "ant-oat", refreshToken: "ant-ort", expiresAt: Date(timeIntervalSince1970: 1700000000)),
            .gemini(apiKey: "gem"),
            .grok(apiKey: "grok"),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(Credentials.self, from: data)
            #expect(decoded == original, "Codable round-trip failed for \(original.provider)")
        }
    }
}
