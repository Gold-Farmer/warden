import Foundation

struct HTTPClient: Sendable {
    static let shared = HTTPClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request<T: Decodable & Sendable>(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ProviderServiceError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderServiceError.networkError(
                underlying: URLError(.badServerResponse)
            )
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw ProviderServiceError.rateLimited(retryAfter: retryAfter)
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ProviderServiceError.apiError(statusCode: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ProviderServiceError.decodingError(underlying: error)
        }
    }

    /// Performs a request and returns the raw response with headers (useful for rate limit info).
    func rawRequest(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (data: Data, statusCode: Int, headers: [AnyHashable: Any]) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderServiceError.networkError(underlying: URLError(.badServerResponse))
        }

        return (data, http.statusCode, http.allHeaderFields)
    }
}
