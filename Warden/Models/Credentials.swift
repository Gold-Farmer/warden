import Foundation

enum Credentials: Codable, Sendable, Equatable {
    case aws(accessKeyId: String, secretAccessKey: String, region: String, sessionToken: String? = nil)
    case gcp(serviceAccountJSON: Data)
    case azure(tenantId: String, clientId: String, clientSecret: String, subscriptionId: String)
    case cloudflare(apiToken: String, accountId: String)
    case openai(apiKey: String, organizationId: String? = nil)
    case openaiOAuth(accessToken: String, refreshToken: String, expiresAt: Date, accountId: String)
    case anthropic(apiKey: String)
    case gemini(apiKey: String)
    case grok(apiKey: String)

    var provider: Provider {
        switch self {
        case .aws: .aws
        case .gcp: .gcp
        case .azure: .azure
        case .cloudflare: .cloudflare
        case .openai: .openai
        case .openaiOAuth: .openai
        case .anthropic: .anthropic
        case .gemini: .gemini
        case .grok: .grok
        }
    }

    /// Checks if the credential has all required fields non-empty.
    var isValid: Bool {
        switch self {
        case .aws(let key, let secret, let region, _):
            !key.isEmpty && !secret.isEmpty && !region.isEmpty
        case .gcp(let json):
            !json.isEmpty
        case .azure(let tenant, let client, let secret, let sub):
            !tenant.isEmpty && !client.isEmpty && !secret.isEmpty && !sub.isEmpty
        case .cloudflare(let token, let account):
            !token.isEmpty && !account.isEmpty
        case .openai(let key, _):
            !key.isEmpty
        case .openaiOAuth(let access, let refresh, _, let accountId):
            !access.isEmpty && !refresh.isEmpty && !accountId.isEmpty
        case .anthropic(let key):
            !key.isEmpty
        case .gemini(let key):
            !key.isEmpty
        case .grok(let key):
            !key.isEmpty
        }
    }
}
