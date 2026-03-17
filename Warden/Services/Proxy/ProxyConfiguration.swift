import Foundation

// MARK: - ProxyProtocol

enum ProxyProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case http       = "HTTP"
    case https      = "HTTPS"
    case socks5     = "SOCKS5"
    case socks5h    = "SOCKS5h"  // remote DNS
    case socks4     = "SOCKS4"

    var id: String { rawValue }

    var defaultPort: UInt16 {
        switch self {
        case .http:   1080
        case .https:  1080
        case .socks5, .socks5h: 1080
        case .socks4: 1080
        }
    }

    var supportsAuth: Bool {
        switch self {
        case .http, .https, .socks5, .socks5h: true
        case .socks4: false
        }
    }
}

// MARK: - ProxyConfiguration

struct ProxyConfiguration: Codable, Sendable, Equatable {
    var enabled: Bool = false
    var `protocol`: ProxyProtocol = .socks5
    var host: String = ""
    var port: UInt16 = 1080
    var username: String = ""
    var password: String = ""
    var bypassList: [String] = ["localhost", "127.0.0.1", "::1"]

    /// Parse a proxy URL like `socks5://user:pass@host:port`.
    static func from(url string: String) -> ProxyConfiguration? {
        guard let url = URL(string: string),
              let host = url.host, !host.isEmpty else {
            return nil
        }

        let proto: ProxyProtocol
        switch url.scheme?.lowercased() {
        case "http":    proto = .http
        case "https":   proto = .https
        case "socks5":  proto = .socks5
        case "socks5h": proto = .socks5h
        case "socks4":  proto = .socks4
        case "socks":   proto = .socks5
        default:        return nil
        }

        var config = ProxyConfiguration()
        config.enabled = true
        config.protocol = proto
        config.host = host
        config.port = UInt16(url.port ?? Int(proto.defaultPort))
        config.username = url.user ?? ""
        config.password = url.password ?? ""
        return config
    }

    /// Export as a proxy URL string.
    var urlString: String {
        var s = "\(`protocol`.rawValue.lowercased())://"
        if !username.isEmpty {
            s += username
            if !password.isEmpty { s += ":\(password)" }
            s += "@"
        }
        s += "\(host):\(port)"
        return s
    }

    var isValid: Bool {
        !host.isEmpty && port > 0
    }

    /// Returns nil if valid, or a user-friendly error message if not.
    func validate() -> ProxyValidationError? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyHost
        }
        if host.contains(" ") {
            return .invalidHost(host)
        }
        if port == 0 {
            return .invalidPort
        }
        return nil
    }

    enum ProxyValidationError: Equatable {
        case emptyHost
        case invalidHost(String)
        case invalidPort

        var message: String {
            switch self {
            case .emptyHost:
                "Please enter the proxy server address"
            case .invalidHost(let h):
                "'\(h)' doesn't look like a valid address — remove any spaces"
            case .invalidPort:
                "Port must be between 1 and 65535"
            }
        }

        var field: String {
            switch self {
            case .emptyHost, .invalidHost: "host"
            case .invalidPort: "port"
            }
        }
    }
}

// MARK: - URLSession factory

extension ProxyConfiguration {

    func makeURLSession() -> URLSession {
        guard enabled, isValid else { return .shared }

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = proxyDictionary()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }

    private func proxyDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        switch `protocol` {
        case .http:
            dict[kCFNetworkProxiesHTTPEnable as String] = true
            dict[kCFNetworkProxiesHTTPProxy as String] = host
            dict[kCFNetworkProxiesHTTPPort as String] = Int(port)
            // Also route HTTPS traffic through this HTTP proxy (CONNECT method)
            dict["HTTPSEnable"] = true
            dict["HTTPSProxy"] = host
            dict["HTTPSPort"] = Int(port)

        case .https:
            dict["HTTPSEnable"] = true
            dict["HTTPSProxy"] = host
            dict["HTTPSPort"] = Int(port)
            dict[kCFNetworkProxiesHTTPEnable as String] = true
            dict[kCFNetworkProxiesHTTPProxy as String] = host
            dict[kCFNetworkProxiesHTTPPort as String] = Int(port)

        case .socks5, .socks5h:
            dict[kCFStreamPropertySOCKSProxyHost as String] = host
            dict[kCFStreamPropertySOCKSProxyPort as String] = Int(port)
            dict[kCFStreamPropertySOCKSVersion as String] = kCFStreamSocketSOCKSVersion5 as String
            if !username.isEmpty {
                dict[kCFStreamPropertySOCKSUser as String] = username
                dict[kCFStreamPropertySOCKSPassword as String] = password
            }

        case .socks4:
            dict[kCFStreamPropertySOCKSProxyHost as String] = host
            dict[kCFStreamPropertySOCKSProxyPort as String] = Int(port)
            dict[kCFStreamPropertySOCKSVersion as String] = kCFStreamSocketSOCKSVersion4 as String
        }

        if !bypassList.isEmpty {
            dict[kCFNetworkProxiesExceptionsList as String] = bypassList
        }

        return dict
    }
}
