import Foundation

enum AWSProfileResolver {

    struct ResolvedCredentials: Sendable {
        let accessKeyId: String
        let secretAccessKey: String
        let region: String
        let sessionToken: String?
    }

    enum ResolverError: LocalizedError {
        case profileNotFound(String)
        case missingField(String, profile: String)
        case noRegion(String)

        var errorDescription: String? {
            switch self {
            case .profileNotFound(let name):
                "AWS profile '\(name)' not found in ~/.aws/credentials"
            case .missingField(let field, let profile):
                "AWS profile '\(profile)' is missing '\(field)'"
            case .noRegion(let name):
                "No region found for profile '\(name)' — set it in ~/.aws/config or specify manually"
            }
        }
    }

    /// Resolve a named profile to usable credentials.
    static func resolve(profileName: String, regionOverride: String?) throws -> ResolvedCredentials {
        let credentialsFile = parseINI(at: awsCredentialsPath)
        let configFile = parseINI(at: awsConfigPath)

        guard let section = credentialsFile[profileName] else {
            throw ResolverError.profileNotFound(profileName)
        }

        guard let accessKeyId = section["aws_access_key_id"], !accessKeyId.isEmpty else {
            throw ResolverError.missingField("aws_access_key_id", profile: profileName)
        }
        guard let secretAccessKey = section["aws_secret_access_key"], !secretAccessKey.isEmpty else {
            throw ResolverError.missingField("aws_secret_access_key", profile: profileName)
        }

        let sessionToken = section["aws_session_token"]

        // Region priority: override > credentials file > config file > error
        let configProfileKey = profileName == "default" ? "default" : "profile \(profileName)"
        let region = regionOverride
            ?? section["region"]
            ?? configFile[configProfileKey]?["region"]
            ?? configFile["default"]?["region"]

        guard let region, !region.isEmpty else {
            throw ResolverError.noRegion(profileName)
        }

        return ResolvedCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region,
            sessionToken: sessionToken
        )
    }

    /// List all profile names found in ~/.aws/credentials.
    static func availableProfiles() -> [String] {
        let sections = parseINI(at: awsCredentialsPath)
        return sections.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return a < b
        }
    }

    // MARK: - INI Parser

    private static var awsCredentialsPath: String {
        NSHomeDirectory() + "/.aws/credentials"
    }

    private static var awsConfigPath: String {
        NSHomeDirectory() + "/.aws/config"
    }

    private static func parseINI(at path: String) -> [String: [String: String]] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [String: String]] = [:]
        var currentSection: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if result[currentSection!] == nil {
                    result[currentSection!] = [:]
                }
            } else if let eqIdx = trimmed.firstIndex(of: "="), let section = currentSection {
                let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                result[section, default: [:]][key] = value
            }
        }
        return result
    }
}
