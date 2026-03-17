import AppKit
import CryptoKit
import Foundation

/// Handles Anthropic Claude OAuth flow (same flow as Claude Code / OpenCode).
@MainActor
final class AnthropicOAuthClient: ObservableObject {
    static let authURL = "https://claude.ai/oauth/authorize"
    static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scope = "org:create_api_key user:profile user:inference"

    @Published var isAuthenticating = false
    @Published var error: String?
    @Published var waitingForCode = false

    private var codeVerifier: String?

    /// Starts the OAuth flow: opens browser, user pastes back the authorization code.
    func login() async -> Credentials? {
        isAuthenticating = true
        waitingForCode = false
        error = nil
        defer {
            isAuthenticating = false
            waitingForCode = false
        }

        // Generate PKCE
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: verifier),
        ]

        guard let url = components.url else {
            self.error = "Failed to build authorization URL"
            return nil
        }

        // Open browser
        NSWorkspace.shared.open(url)
        waitingForCode = true

        return nil // User must paste code back, handled by exchangeCode()
    }

    /// Exchange the authorization code (pasted by user) for tokens.
    func exchangeCode(_ rawCode: String) async -> Credentials? {
        isAuthenticating = true
        error = nil
        defer { isAuthenticating = false }

        guard let verifier = codeVerifier else {
            error = "No pending OAuth session"
            return nil
        }

        // Code may come as "code#state" — extract just the code
        let code = rawCode.components(separatedBy: "#").first ?? rawCode

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]

        guard let url = URL(string: Self.tokenURL) else {
            error = "Invalid token URL"
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                self.error = "Token exchange failed: \(msg)"
                return nil
            }

            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in))

            codeVerifier = nil
            waitingForCode = false

            return .anthropicOAuth(
                accessToken: token.access_token,
                refreshToken: token.refresh_token ?? "",
                expiresAt: expiresAt
            )
        } catch {
            self.error = "Token exchange error: \(error.localizedDescription)"
            return nil
        }
    }

    func cancel() {
        isAuthenticating = false
        waitingForCode = false
        codeVerifier = nil
    }

    /// Refresh an expired OAuth token.
    nonisolated static func refresh(_ credentials: Credentials) async -> Credentials? {
        guard case .anthropicOAuth(_, let refreshToken, _) = credentials,
              !refreshToken.isEmpty else { return nil }

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]

        guard let url = URL(string: tokenURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in))

            return .anthropicOAuth(
                accessToken: token.access_token,
                refreshToken: token.refresh_token ?? refreshToken,
                expiresAt: expiresAt
            )
        } catch {
            return nil
        }
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded
    }

    // MARK: - Types

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String?
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
