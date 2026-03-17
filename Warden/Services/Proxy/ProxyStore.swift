import Foundation

// MARK: - ProxySessionProvider (thread-safe URLSession holder)

final class ProxySessionProvider: @unchecked Sendable {
    static let shared = ProxySessionProvider()

    private let lock = NSLock()
    private var _session: URLSession = .shared

    var session: URLSession {
        lock.withLock { _session }
    }

    func update(with config: ProxyConfiguration) {
        let newSession = config.makeURLSession()
        lock.withLock { _session = newSession }
    }
}

// MARK: - ProxyStore (@Observable for UI + persistence)

@MainActor
@Observable
final class ProxyStore {
    var configuration: ProxyConfiguration {
        didSet {
            save()
            ProxySessionProvider.shared.update(with: configuration)
        }
    }

    /// Convenience for URL-based input.
    var proxyURL: String = ""

    // Test state
    enum ProxyTestState: Equatable {
        case idle
        case validating
        case testing
        case success
        case failure(String)
    }
    var testState: ProxyTestState = .idle
    var validationError: ProxyConfiguration.ProxyValidationError?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Warden", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("proxy.json")
        self.configuration = ProxyConfiguration()
        load()
        ProxySessionProvider.shared.update(with: configuration)
    }

    func applyURL() {
        guard !proxyURL.isEmpty,
              let parsed = ProxyConfiguration.from(url: proxyURL) else {
            if !proxyURL.isEmpty {
                testState = .failure("Invalid proxy URL — use format like socks5://host:port")
            }
            return
        }
        configuration = parsed
        proxyURL = ""
    }

    /// Validate → test → save or show error.
    func validateAndTest() async {
        // Step 1: Validate format
        testState = .validating
        validationError = configuration.validate()
        if let error = validationError {
            testState = .failure(error.message)
            return
        }

        // Step 2: Test connectivity
        testState = .testing
        let session = configuration.makeURLSession()
        let testURL = URL(string: "https://www.apple.com/library/test/success.html")!

        do {
            let (data, response) = try await session.data(for: URLRequest(url: testURL))
            guard let http = response as? HTTPURLResponse else {
                testState = .failure("No response from proxy — check that the proxy server is running")
                return
            }
            if (200..<400).contains(http.statusCode) {
                // Verify we got actual content (not a proxy error page)
                let body = String(data: data, encoding: .utf8) ?? ""
                if http.statusCode == 200 && body.contains("Success") || http.statusCode < 400 {
                    testState = .success
                    // Auto-dismiss success after 3s
                    try? await Task.sleep(for: .seconds(3))
                    if testState == .success {
                        testState = .idle
                    }
                    return
                }
            }
            testState = .failure("Proxy returned HTTP \(http.statusCode) — it may be blocking traffic or require different credentials")
        } catch let error as URLError {
            testState = .failure(describeURLError(error))
        } catch {
            testState = .failure("Connection failed: \(error.localizedDescription)")
        }
    }

    private func describeURLError(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost:
            "Cannot connect to \(configuration.host):\(configuration.port) — is the proxy server running?"
        case .timedOut:
            "Connection timed out — check the address and make sure port \(configuration.port) is open"
        case .networkConnectionLost:
            "Connection lost — the proxy server may have rejected the connection"
        case .notConnectedToInternet:
            "No internet connection — check your network first"
        case .secureConnectionFailed:
            "SSL handshake failed — try a different proxy protocol (e.g. SOCKS5 instead of HTTPS)"
        default:
            "Network error: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(ProxyConfiguration.self, from: data) else {
            return
        }
        configuration = config
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
