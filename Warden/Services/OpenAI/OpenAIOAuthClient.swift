import AppKit
import CryptoKit
import Foundation

/// Handles OpenAI ChatGPT OAuth flow (same flow as Codex CLI).
@MainActor
final class OpenAIOAuthClient: ObservableObject {
    static let authURL = "https://auth.openai.com/oauth/authorize"
    static let tokenURL = "https://auth.openai.com/oauth/token"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let scope = "openai.public"

    @Published var isAuthenticating = false
    @Published var error: String?

    private var codeVerifier: String?
    private var callbackServer: CallbackServer?

    /// Starts the OAuth flow: opens browser and waits for callback.
    func login() async -> Credentials? {
        isAuthenticating = true
        error = nil
        defer { isAuthenticating = false }

        // Generate PKCE
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Start local callback server
        let server = CallbackServer(port: 1455)
        callbackServer = server

        do {
            try server.start()
        } catch {
            self.error = "Failed to start callback server: \(error.localizedDescription)"
            return nil
        }

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            self.error = "Failed to build authorization URL"
            server.stop()
            return nil
        }

        // Open browser
        NSWorkspace.shared.open(url)

        // Wait for callback
        let code: String
        do {
            code = try await server.waitForCode(timeout: 120)
        } catch {
            self.error = "Login timed out or was cancelled"
            server.stop()
            return nil
        }

        server.stop()
        callbackServer = nil

        // Exchange code for tokens
        return await exchangeCode(code, verifier: verifier)
    }

    func cancel() {
        callbackServer?.stop()
        callbackServer = nil
        isAuthenticating = false
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, verifier: String) async -> Credentials? {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]

        guard let url = URL(string: Self.tokenURL) else { return nil }

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

            return .openaiOAuth(
                accessToken: token.access_token,
                refreshToken: token.refresh_token ?? "",
                expiresAt: expiresAt,
                accountId: token.account_id ?? ""
            )
        } catch {
            self.error = "Token exchange error: \(error.localizedDescription)"
            return nil
        }
    }

    /// Refresh an expired OAuth token.
    nonisolated static func refresh(_ credentials: Credentials) async -> Credentials? {
        guard case .openaiOAuth(_, let refreshToken, _, _) = credentials,
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

            return .openaiOAuth(
                accessToken: token.access_token,
                refreshToken: token.refresh_token ?? refreshToken,
                expiresAt: expiresAt,
                accountId: token.account_id ?? ""
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
        let account_id: String?
    }
}

// MARK: - Base64URL

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// MARK: - Local Callback Server

/// Minimal HTTP server that listens for the OAuth redirect callback.
private final class CallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: (any NSObjectProtocol)?
    private var fileHandle: FileHandle?
    private var socketHandle: Int32 = -1
    private var continuation: CheckedContinuation<String, Error>?

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        socketHandle = socket(AF_INET, SOCK_STREAM, 0)
        guard socketHandle >= 0 else { throw URLError(.cannotConnectToHost) }

        var reuse: Int32 = 1
        setsockopt(socketHandle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketHandle)
            throw URLError(.cannotConnectToHost)
        }

        listen(socketHandle, 1)

        fileHandle = FileHandle(fileDescriptor: socketHandle, closeOnDealloc: false)
        listener = NotificationCenter.default.addObserver(
            forName: .NSFileHandleConnectionAccepted,
            object: fileHandle,
            queue: .main
        ) { [weak self] notification in
            self?.handleConnection(notification)
        }
        fileHandle?.acceptConnectionInBackgroundAndNotify()
    }

    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            // Timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.continuation?.resume(throwing: URLError(.timedOut))
                self?.continuation = nil
            }
        }
    }

    func stop() {
        if let listener {
            NotificationCenter.default.removeObserver(listener)
        }
        listener = nil
        fileHandle = nil
        if socketHandle >= 0 {
            close(socketHandle)
            socketHandle = -1
        }
    }

    private func handleConnection(_ notification: Notification) {
        guard let clientHandle = notification.userInfo?[NSFileHandleNotificationFileHandleItem] as? FileHandle else {
            return
        }

        let data = clientHandle.availableData
        let request = String(data: data, encoding: .utf8) ?? ""

        // Parse code from GET /auth/callback?code=XXX
        var code: String?
        if let urlLine = request.components(separatedBy: "\r\n").first,
           let pathPart = urlLine.split(separator: " ").dropFirst().first,
           let components = URLComponents(string: String(pathPart)),
           let codeParam = components.queryItems?.first(where: { $0.name == "code" })?.value {
            code = codeParam
        }

        // Send response
        let html: String
        if code != nil {
            html = "<html><body><h2>Login successful!</h2><p>You can close this tab and return to Warden.</p></body></html>"
        } else {
            html = "<html><body><h2>Login failed</h2><p>No authorization code received.</p></body></html>"
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
        clientHandle.write(Data(response.utf8))
        clientHandle.closeFile()

        if let code {
            continuation?.resume(returning: code)
            continuation = nil
        }
    }
}
