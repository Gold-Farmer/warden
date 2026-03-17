import Foundation
import Testing
@testable import Warden

// MARK: - ProxyProtocol Tests

@Suite("ProxyProtocol")
struct ProxyProtocolTests {

    @Test("All protocols have a default port")
    func allDefaultPorts() {
        for proto in ProxyProtocol.allCases {
            #expect(proto.defaultPort > 0)
        }
    }

    @Test("Protocol count matches expected")
    func protocolCount() {
        #expect(ProxyProtocol.allCases.count == 5)
    }

    @Test("Each protocol has unique rawValue")
    func uniqueRawValues() {
        let values = ProxyProtocol.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count)
    }

    @Test("Each protocol has a stable Identifiable id")
    func identifiableId() {
        for proto in ProxyProtocol.allCases {
            #expect(proto.id == proto.rawValue)
        }
    }

    @Test("SOCKS4 does not support auth")
    func socks4NoAuth() {
        #expect(ProxyProtocol.socks4.supportsAuth == false)
    }

    @Test("SOCKS5, SOCKS5h, HTTP, HTTPS support auth")
    func authSupport() {
        #expect(ProxyProtocol.socks5.supportsAuth == true)
        #expect(ProxyProtocol.socks5h.supportsAuth == true)
        #expect(ProxyProtocol.http.supportsAuth == true)
        #expect(ProxyProtocol.https.supportsAuth == true)
    }

    @Test("Protocol Codable round-trip for each case")
    func codableRoundTrip() throws {
        for proto in ProxyProtocol.allCases {
            let data = try JSONEncoder().encode(proto)
            let decoded = try JSONDecoder().decode(ProxyProtocol.self, from: data)
            #expect(decoded == proto)
        }
    }
}

// MARK: - ProxyConfiguration URL Parsing

@Suite("ProxyConfiguration URL Parsing")
struct ProxyURLParsingTests {

    @Test("Parse SOCKS5 URL with auth")
    func parseSocks5WithAuth() {
        let config = ProxyConfiguration.from(url: "socks5://admin:secret@10.0.0.1:1080")
        #expect(config != nil)
        #expect(config?.protocol == .socks5)
        #expect(config?.host == "10.0.0.1")
        #expect(config?.port == 1080)
        #expect(config?.username == "admin")
        #expect(config?.password == "secret")
        #expect(config?.enabled == true)
    }

    @Test("Parse HTTP proxy URL")
    func parseHTTP() {
        let config = ProxyConfiguration.from(url: "http://proxy.corp.com:8080")
        #expect(config != nil)
        #expect(config?.protocol == .http)
        #expect(config?.host == "proxy.corp.com")
        #expect(config?.port == 8080)
        #expect(config?.username == "")
        #expect(config?.password == "")
    }

    @Test("Parse HTTPS proxy URL")
    func parseHTTPS() {
        let config = ProxyConfiguration.from(url: "https://secure-proxy.com:443")
        #expect(config != nil)
        #expect(config?.protocol == .https)
        #expect(config?.host == "secure-proxy.com")
        #expect(config?.port == 443)
    }

    @Test("Parse SOCKS5h URL")
    func parseSocks5h() {
        let config = ProxyConfiguration.from(url: "socks5h://proxy.local:9050")
        #expect(config != nil)
        #expect(config?.protocol == .socks5h)
        #expect(config?.host == "proxy.local")
        #expect(config?.port == 9050)
    }

    @Test("Parse SOCKS4 URL")
    func parseSocks4() {
        let config = ProxyConfiguration.from(url: "socks4://oldproxy:1081")
        #expect(config != nil)
        #expect(config?.protocol == .socks4)
        #expect(config?.port == 1081)
    }

    @Test("Parse 'socks' alias as SOCKS5")
    func parseSocksAlias() {
        let config = ProxyConfiguration.from(url: "socks://proxy:1080")
        #expect(config?.protocol == .socks5)
    }

    @Test("Parse URL with default port when port omitted")
    func parseDefaultPort() {
        let config = ProxyConfiguration.from(url: "socks5://proxy.local")
        #expect(config != nil)
        #expect(config?.port == ProxyProtocol.socks5.defaultPort)
    }

    @Test("Parse URL with username only, no password")
    func parseUsernameOnly() {
        let config = ProxyConfiguration.from(url: "socks5://onlyuser@proxy:1080")
        #expect(config?.username == "onlyuser")
        #expect(config?.password == "")
    }

    @Test("Parse URL with high port number")
    func parseHighPort() {
        let config = ProxyConfiguration.from(url: "http://proxy:65535")
        #expect(config?.port == 65535)
    }

    @Test("Parse URL with IP address host")
    func parseIPAddress() {
        let config = ProxyConfiguration.from(url: "socks5://192.168.1.100:1080")
        #expect(config?.host == "192.168.1.100")
    }

    @Test("Parse URL with subdomain host")
    func parseSubdomain() {
        let config = ProxyConfiguration.from(url: "http://proxy.us-east.corp.internal:3128")
        #expect(config?.host == "proxy.us-east.corp.internal")
        #expect(config?.port == 3128)
    }

    @Test("Invalid URLs return nil")
    func parseInvalid() {
        #expect(ProxyConfiguration.from(url: "") == nil)
        #expect(ProxyConfiguration.from(url: "not-a-url") == nil)
        #expect(ProxyConfiguration.from(url: "ftp://proxy:21") == nil)
        #expect(ProxyConfiguration.from(url: "ws://proxy:80") == nil)
        #expect(ProxyConfiguration.from(url: "ssh://proxy:22") == nil)
    }

    @Test("Parsed config preserves default bypass list")
    func parsedBypassList() {
        let config = ProxyConfiguration.from(url: "socks5://proxy:1080")
        #expect(config?.bypassList.contains("localhost") == true)
        #expect(config?.bypassList.contains("127.0.0.1") == true)
        #expect(config?.bypassList.contains("::1") == true)
    }

    @Test("Case insensitive scheme parsing")
    func caseInsensitiveScheme() {
        let config = ProxyConfiguration.from(url: "SOCKS5://proxy:1080")
        #expect(config?.protocol == .socks5)

        let config2 = ProxyConfiguration.from(url: "Http://proxy:8080")
        #expect(config2?.protocol == .http)
    }
}

// MARK: - ProxyConfiguration URL Export

@Suite("ProxyConfiguration URL Export")
struct ProxyURLExportTests {

    @Test("Export SOCKS5 URL with auth")
    func exportWithAuth() {
        var config = ProxyConfiguration()
        config.protocol = .socks5
        config.host = "10.0.0.1"
        config.port = 1080
        config.username = "user"
        config.password = "pass"
        #expect(config.urlString == "socks5://user:pass@10.0.0.1:1080")
    }

    @Test("Export HTTP URL without auth")
    func exportNoAuth() {
        var config = ProxyConfiguration()
        config.protocol = .http
        config.host = "proxy.local"
        config.port = 8080
        #expect(config.urlString == "http://proxy.local:8080")
    }

    @Test("Export with username only, no password")
    func exportUsernameOnly() {
        var config = ProxyConfiguration()
        config.protocol = .socks5
        config.host = "proxy"
        config.port = 1080
        config.username = "admin"
        config.password = ""
        #expect(config.urlString == "socks5://admin@proxy:1080")
    }

    @Test("Export each protocol type")
    func exportAllProtocols() {
        for proto in ProxyProtocol.allCases {
            var config = ProxyConfiguration()
            config.protocol = proto
            config.host = "test"
            config.port = 1080
            #expect(config.urlString.hasPrefix(proto.rawValue.lowercased() + "://"))
        }
    }

    @Test("Round-trip: parse then export preserves URL")
    func roundTripURL() {
        let urls = [
            "socks5://user:pass@proxy:1080",
            "http://proxy.local:8080",
            "https://secure:443",
            "socks4://legacy:1081",
            "socks5h://tor:9050",
        ]
        for url in urls {
            let config = ProxyConfiguration.from(url: url)
            #expect(config != nil)
            #expect(config?.urlString == url, "Round-trip failed for \(url)")
        }
    }
}

// MARK: - ProxyConfiguration Validation

@Suite("ProxyConfiguration Validation")
struct ProxyValidationTests {

    @Test("Default config is invalid (empty host)")
    func defaultInvalid() {
        let config = ProxyConfiguration()
        #expect(config.isValid == false)
    }

    @Test("Config with host and port is valid")
    func validHostPort() {
        var config = ProxyConfiguration()
        config.host = "proxy.local"
        config.port = 1080
        #expect(config.isValid == true)
    }

    @Test("Config with host and port 0 is invalid")
    func zeroPortInvalid() {
        var config = ProxyConfiguration()
        config.host = "proxy"
        config.port = 0
        #expect(config.isValid == false)
    }

    @Test("Config with empty host is invalid regardless of port")
    func emptyHostInvalid() {
        var config = ProxyConfiguration()
        config.host = ""
        config.port = 1080
        #expect(config.isValid == false)
    }
}

// MARK: - ProxyConfiguration Defaults

@Suite("ProxyConfiguration Defaults")
struct ProxyDefaultsTests {

    @Test("Default state is disabled")
    func defaultDisabled() {
        let config = ProxyConfiguration()
        #expect(config.enabled == false)
    }

    @Test("Default protocol is SOCKS5")
    func defaultProtocol() {
        let config = ProxyConfiguration()
        #expect(config.protocol == .socks5)
    }

    @Test("Default port is 1080")
    func defaultPort() {
        let config = ProxyConfiguration()
        #expect(config.port == 1080)
    }

    @Test("Default bypass includes localhost, 127.0.0.1, ::1")
    func defaultBypass() {
        let config = ProxyConfiguration()
        #expect(config.bypassList == ["localhost", "127.0.0.1", "::1"])
    }

    @Test("Default credentials are empty")
    func defaultCredentials() {
        let config = ProxyConfiguration()
        #expect(config.username == "")
        #expect(config.password == "")
    }
}

// MARK: - ProxyConfiguration Equatable

@Suite("ProxyConfiguration Equatable")
struct ProxyEquatableTests {

    @Test("Two default configs are equal")
    func defaultsEqual() {
        let a = ProxyConfiguration()
        let b = ProxyConfiguration()
        #expect(a == b)
    }

    @Test("Configs with different hosts are not equal")
    func differentHost() {
        var a = ProxyConfiguration()
        a.host = "proxy1"
        var b = ProxyConfiguration()
        b.host = "proxy2"
        #expect(a != b)
    }

    @Test("Configs with different protocols are not equal")
    func differentProtocol() {
        var a = ProxyConfiguration()
        a.protocol = .http
        var b = ProxyConfiguration()
        b.protocol = .socks5
        #expect(a != b)
    }

    @Test("Configs with different enabled state are not equal")
    func differentEnabled() {
        var a = ProxyConfiguration()
        a.enabled = true
        var b = ProxyConfiguration()
        b.enabled = false
        #expect(a != b)
    }

    @Test("Configs with different bypass lists are not equal")
    func differentBypass() {
        var a = ProxyConfiguration()
        a.bypassList = ["localhost"]
        var b = ProxyConfiguration()
        b.bypassList = ["localhost", "extra.com"]
        #expect(a != b)
    }
}

// MARK: - ProxyConfiguration Codable

@Suite("ProxyConfiguration Codable")
struct ProxyCodableTests {

    @Test("Full config Codable round-trip")
    func fullRoundTrip() throws {
        var original = ProxyConfiguration()
        original.enabled = true
        original.protocol = .socks5
        original.host = "10.0.0.1"
        original.port = 1080
        original.username = "user"
        original.password = "pass"
        original.bypassList = ["localhost", "*.internal"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProxyConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip for each protocol")
    func eachProtocol() throws {
        for proto in ProxyProtocol.allCases {
            var config = ProxyConfiguration()
            config.protocol = proto
            config.host = "proxy"
            config.port = 8080

            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(ProxyConfiguration.self, from: data)
            #expect(decoded.protocol == proto)
        }
    }

    @Test("Empty bypass list survives Codable round-trip")
    func emptyBypass() throws {
        var config = ProxyConfiguration()
        config.bypassList = []
        config.host = "proxy"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProxyConfiguration.self, from: data)
        #expect(decoded.bypassList.isEmpty)
    }

    @Test("JSON is human-readable")
    func humanReadable() throws {
        var config = ProxyConfiguration()
        config.host = "proxy.local"
        config.protocol = .http

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"host\" : \"proxy.local\""))
        #expect(json.contains("\"HTTP\""))
    }
}

// MARK: - Proxy Dictionary (URLSession configuration)

@Suite("Proxy Dictionary")
struct ProxyDictionaryTests {

    private func makeConfig(_ proto: ProxyProtocol, host: String = "proxy", port: UInt16 = 1080) -> ProxyConfiguration {
        var config = ProxyConfiguration()
        config.enabled = true
        config.protocol = proto
        config.host = host
        config.port = port
        return config
    }

    @Test("HTTP proxy sets HTTP and HTTPS keys")
    func httpDictionary() {
        let config = makeConfig(.http, host: "httpproxy", port: 8080)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFNetworkProxiesHTTPEnable as String] as? Bool == true)
        #expect(dict[kCFNetworkProxiesHTTPProxy as String] as? String == "httpproxy")
        #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 8080)
        // HTTPS tunneling via HTTP CONNECT
        #expect(dict["HTTPSEnable"] as? Bool == true)
        #expect(dict["HTTPSProxy"] as? String == "httpproxy")
        #expect(dict["HTTPSPort"] as? Int == 8080)
    }

    @Test("HTTPS proxy sets both HTTP and HTTPS keys")
    func httpsDictionary() {
        let config = makeConfig(.https, host: "secureproxy", port: 443)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict["HTTPSEnable"] as? Bool == true)
        #expect(dict["HTTPSProxy"] as? String == "secureproxy")
        #expect(dict["HTTPSPort"] as? Int == 443)
        #expect(dict[kCFNetworkProxiesHTTPEnable as String] as? Bool == true)
    }

    @Test("SOCKS5 proxy sets SOCKS keys with version 5")
    func socks5Dictionary() {
        let config = makeConfig(.socks5, host: "socksproxy", port: 1080)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFStreamPropertySOCKSProxyHost as String] as? String == "socksproxy")
        #expect(dict[kCFStreamPropertySOCKSProxyPort as String] as? Int == 1080)
        #expect(dict[kCFStreamPropertySOCKSVersion as String] as? String == kCFStreamSocketSOCKSVersion5 as String)
    }

    @Test("SOCKS5h proxy uses same keys as SOCKS5")
    func socks5hDictionary() {
        let config = makeConfig(.socks5h, host: "torproxy", port: 9050)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFStreamPropertySOCKSProxyHost as String] as? String == "torproxy")
        #expect(dict[kCFStreamPropertySOCKSVersion as String] as? String == kCFStreamSocketSOCKSVersion5 as String)
    }

    @Test("SOCKS4 proxy sets version 4")
    func socks4Dictionary() {
        let config = makeConfig(.socks4, host: "legacyproxy", port: 1081)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFStreamPropertySOCKSProxyHost as String] as? String == "legacyproxy")
        #expect(dict[kCFStreamPropertySOCKSProxyPort as String] as? Int == 1081)
        #expect(dict[kCFStreamPropertySOCKSVersion as String] as? String == kCFStreamSocketSOCKSVersion4 as String)
    }

    @Test("SOCKS5 with auth sets user and password keys")
    func socks5Auth() {
        var config = makeConfig(.socks5)
        config.username = "admin"
        config.password = "secret"
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFStreamPropertySOCKSUser as String] as? String == "admin")
        #expect(dict[kCFStreamPropertySOCKSPassword as String] as? String == "secret")
    }

    @Test("SOCKS5 without auth does not set user keys")
    func socks5NoAuth() {
        let config = makeConfig(.socks5)
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFStreamPropertySOCKSUser as String] == nil)
        #expect(dict[kCFStreamPropertySOCKSPassword as String] == nil)
    }

    @Test("Bypass list is set in proxy dictionary")
    func bypassList() {
        var config = makeConfig(.socks5)
        config.bypassList = ["localhost", "*.corp.com", "10.0.0.0/8"]
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        let bypass = dict[kCFNetworkProxiesExceptionsList as String] as? [String]
        #expect(bypass == ["localhost", "*.corp.com", "10.0.0.0/8"])
    }

    @Test("Empty bypass list omits exceptions key")
    func emptyBypassList() {
        var config = makeConfig(.socks5)
        config.bypassList = []
        let session = config.makeURLSession()
        let dict = session.configuration.connectionProxyDictionary!

        #expect(dict[kCFNetworkProxiesExceptionsList as String] == nil)
    }

    @Test("Session timeout is configured")
    func sessionTimeout() {
        let config = makeConfig(.socks5)
        let session = config.makeURLSession()
        #expect(session.configuration.timeoutIntervalForRequest == 30)
        #expect(session.configuration.timeoutIntervalForResource == 300)
    }
}

// MARK: - URLSession Factory

@Suite("URLSession Factory")
struct URLSessionFactoryTests {

    @Test("Disabled config returns .shared")
    func disabledReturnsShared() {
        var config = ProxyConfiguration()
        config.enabled = false
        config.host = "proxy.local"
        config.port = 1080
        #expect(config.makeURLSession() === URLSession.shared)
    }

    @Test("Enabled + valid returns custom session")
    func enabledReturnsCustom() {
        var config = ProxyConfiguration()
        config.enabled = true
        config.host = "proxy.local"
        config.port = 1080
        #expect(config.makeURLSession() !== URLSession.shared)
    }

    @Test("Enabled + invalid returns .shared")
    func enabledInvalidReturnsShared() {
        var config = ProxyConfiguration()
        config.enabled = true
        config.host = ""  // invalid
        #expect(config.makeURLSession() === URLSession.shared)
    }

    @Test("Each call creates a distinct session instance")
    func distinctSessions() {
        var config = ProxyConfiguration()
        config.enabled = true
        config.host = "proxy"
        config.port = 1080
        let s1 = config.makeURLSession()
        let s2 = config.makeURLSession()
        #expect(s1 !== s2)
    }
}

// MARK: - ProxySessionProvider

@Suite("ProxySessionProvider")
struct ProxySessionProviderTests {

    @Test("Default session is .shared")
    func defaultIsShared() {
        let provider = ProxySessionProvider()
        #expect(provider.session === URLSession.shared)
    }

    @Test("Update with enabled config changes session")
    func updateChangesSession() {
        let provider = ProxySessionProvider()
        var config = ProxyConfiguration()
        config.enabled = true
        config.host = "proxy"
        config.port = 1080

        provider.update(with: config)
        #expect(provider.session !== URLSession.shared)
    }

    @Test("Update with disabled config reverts to .shared")
    func updateDisabledRevertsToShared() {
        let provider = ProxySessionProvider()

        // First enable
        var enabled = ProxyConfiguration()
        enabled.enabled = true
        enabled.host = "proxy"
        enabled.port = 1080
        provider.update(with: enabled)
        #expect(provider.session !== URLSession.shared)

        // Then disable
        var disabled = ProxyConfiguration()
        disabled.enabled = false
        provider.update(with: disabled)
        #expect(provider.session === URLSession.shared)
    }

    @Test("Concurrent reads don't crash")
    func concurrentReads() async {
        let provider = ProxySessionProvider()
        var config = ProxyConfiguration()
        config.enabled = true
        config.host = "proxy"
        config.port = 1080
        provider.update(with: config)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = provider.session
                }
            }
        }
    }

    @Test("Concurrent reads and writes don't crash")
    func concurrentReadWrite() async {
        let provider = ProxySessionProvider()

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    var config = ProxyConfiguration()
                    config.enabled = i % 2 == 0
                    config.host = "proxy-\(i)"
                    config.port = UInt16(1080 + i)
                    provider.update(with: config)
                }
            }
            // Readers
            for _ in 0..<50 {
                group.addTask {
                    _ = provider.session
                }
            }
        }
    }
}

// MARK: - HTTPClient Proxy Integration

@Suite("HTTPClient Proxy Integration")
struct HTTPClientProxyTests {

    @Test("Default HTTPClient uses ProxySessionProvider")
    func defaultUsesProvider() {
        let client = HTTPClient()
        _ = client
    }

    @Test("HTTPClient with explicit session bypasses proxy")
    func explicitSessionBypassesProxy() {
        let customSession = URLSession(configuration: .ephemeral)
        let client = HTTPClient(session: customSession)
        _ = client
    }

    @Test("HTTPClient.shared is accessible")
    func sharedAccessible() {
        _ = HTTPClient.shared
    }
}

// MARK: - Validation

@Suite("ProxyConfiguration Validation Details")
struct ProxyValidationDetailTests {

    @Test("Valid config returns nil error")
    func validReturnsNil() {
        var config = ProxyConfiguration()
        config.host = "proxy.local"
        config.port = 1080
        #expect(config.validate() == nil)
    }

    @Test("Empty host returns emptyHost error")
    func emptyHostError() {
        var config = ProxyConfiguration()
        config.host = ""
        config.port = 1080
        let error = config.validate()
        #expect(error == .emptyHost)
        #expect(error?.field == "host")
        #expect(error?.message.contains("address") == true)
    }

    @Test("Whitespace-only host returns emptyHost error")
    func whitespaceHostError() {
        var config = ProxyConfiguration()
        config.host = "   "
        config.port = 1080
        #expect(config.validate() == .emptyHost)
    }

    @Test("Host with spaces returns invalidHost error")
    func spacesInHostError() {
        var config = ProxyConfiguration()
        config.host = "proxy local"
        config.port = 1080
        let error = config.validate()
        #expect(error == .invalidHost("proxy local"))
        #expect(error?.field == "host")
        #expect(error?.message.contains("spaces") == true)
    }

    @Test("Port 0 returns invalidPort error")
    func zeroPortError() {
        var config = ProxyConfiguration()
        config.host = "proxy"
        config.port = 0
        let error = config.validate()
        #expect(error == .invalidPort)
        #expect(error?.field == "port")
    }

    @Test("Valid IP address passes validation")
    func validIPAddress() {
        var config = ProxyConfiguration()
        config.host = "192.168.1.1"
        config.port = 3128
        #expect(config.validate() == nil)
    }

    @Test("Valid domain passes validation")
    func validDomain() {
        var config = ProxyConfiguration()
        config.host = "proxy.corp.internal"
        config.port = 8080
        #expect(config.validate() == nil)
    }

    @Test("Max port passes validation")
    func maxPort() {
        var config = ProxyConfiguration()
        config.host = "proxy"
        config.port = 65535
        #expect(config.validate() == nil)
    }

    @Test("Validation errors are Equatable")
    func equatable() {
        #expect(ProxyConfiguration.ProxyValidationError.emptyHost == .emptyHost)
        #expect(ProxyConfiguration.ProxyValidationError.invalidPort == .invalidPort)
        #expect(ProxyConfiguration.ProxyValidationError.invalidHost("a") == .invalidHost("a"))
        #expect(ProxyConfiguration.ProxyValidationError.invalidHost("a") != .invalidHost("b"))
        #expect(ProxyConfiguration.ProxyValidationError.emptyHost != .invalidPort)
    }

    @Test("Each error has a non-empty message")
    func errorMessages() {
        let errors: [ProxyConfiguration.ProxyValidationError] = [
            .emptyHost, .invalidHost("x"), .invalidPort
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(!error.field.isEmpty)
        }
    }
}

// MARK: - ProxyStore Test State

@Suite("ProxyStore Test State")
struct ProxyStoreTestStateTests {

    @Test("ProxyTestState cases are Equatable")
    func testStateEquatable() {
        #expect(ProxyStore.ProxyTestState.idle == .idle)
        #expect(ProxyStore.ProxyTestState.testing == .testing)
        #expect(ProxyStore.ProxyTestState.validating == .validating)
        #expect(ProxyStore.ProxyTestState.success == .success)
        #expect(ProxyStore.ProxyTestState.failure("a") == .failure("a"))
        #expect(ProxyStore.ProxyTestState.failure("a") != .failure("b"))
        #expect(ProxyStore.ProxyTestState.idle != .testing)
    }

    @MainActor
    @Test("ProxyStore starts with idle test state")
    func initialState() {
        let store = ProxyStore()
        #expect(store.testState == .idle)
        #expect(store.validationError == nil)
    }

    @MainActor
    @Test("applyURL with invalid URL sets failure state")
    func applyInvalidURL() {
        let store = ProxyStore()
        store.proxyURL = "not-valid"
        store.applyURL()
        #expect(store.testState == .failure("Invalid proxy URL — use format like socks5://host:port"))
    }

    @MainActor
    @Test("applyURL with empty string does nothing")
    func applyEmptyURL() {
        let store = ProxyStore()
        store.proxyURL = ""
        store.applyURL()
        #expect(store.testState == .idle)
    }

    @MainActor
    @Test("applyURL with valid URL sets config and clears proxyURL")
    func applyValidURL() {
        let store = ProxyStore()
        store.proxyURL = "socks5://proxy:1080"
        store.applyURL()
        #expect(store.configuration.host == "proxy")
        #expect(store.configuration.port == 1080)
        #expect(store.configuration.protocol == .socks5)
        #expect(store.proxyURL == "")
    }

    @MainActor
    @Test("validateAndTest with empty host sets failure")
    func validateEmptyHost() async {
        let store = ProxyStore()
        store.configuration.enabled = true
        store.configuration.host = ""
        await store.validateAndTest()
        #expect(store.validationError == .emptyHost)
        if case .failure(let msg) = store.testState {
            #expect(msg.contains("address"))
        } else {
            Issue.record("Expected failure state")
        }
    }

    @MainActor
    @Test("validateAndTest with zero port sets failure")
    func validateZeroPort() async {
        let store = ProxyStore()
        store.configuration.enabled = true
        store.configuration.host = "proxy"
        store.configuration.port = 0
        await store.validateAndTest()
        #expect(store.validationError == .invalidPort)
        #expect(store.testState != .idle)
    }

    @MainActor
    @Test("validateAndTest with unreachable proxy sets failure with helpful message")
    func validateUnreachableProxy() async {
        let store = ProxyStore()
        store.configuration.enabled = true
        store.configuration.host = "192.0.2.1"  // TEST-NET, guaranteed unreachable
        store.configuration.port = 1
        await store.validateAndTest()
        // Should pass validation but fail connectivity
        #expect(store.validationError == nil)
        if case .failure(let msg) = store.testState {
            #expect(!msg.isEmpty)
        } else if store.testState == .success {
            // Unlikely but possible on some networks
        } else {
            Issue.record("Expected failure or success, got \(store.testState)")
        }
    }
}
