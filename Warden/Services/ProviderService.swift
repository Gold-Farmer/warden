import Foundation

protocol ProviderService: Actor {
    var provider: Provider { get }
    var isConfigured: Bool { get }

    func configure(with credentials: Credentials) throws
    func fetchStatus() async throws -> ProviderStatus
}

enum ProviderServiceError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case apiError(statusCode: Int, message: String)
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Provider is not configured. Please add your credentials in Settings."
        case .invalidCredentials:
            "Invalid credentials. Please check your API keys."
        case .apiError(let code, let message):
            "API error (\(code)): \(message)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            "Failed to parse response: \(error.localizedDescription)"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Rate limited. Retry after \(Int(retryAfter))s."
            } else {
                "Rate limited. Please try again later."
            }
        }
    }
}
