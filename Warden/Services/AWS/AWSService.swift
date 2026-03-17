import Foundation
import CryptoKit

actor AWSService: ProviderService {
    let provider = Provider.aws
    private(set) var isConfigured = false
    private var accessKeyId = ""
    private var secretAccessKey = ""
    private var region = ""
    private var sessionToken: String?

    func configure(with credentials: Credentials) throws {
        switch credentials {
        case .aws(let key, let secret, let reg, let token):
            accessKeyId = key
            secretAccessKey = secret
            region = reg
            sessionToken = token
        case .awsProfile(let profileName, let regionOverride):
            let resolved = try AWSProfileResolver.resolve(profileName: profileName, regionOverride: regionOverride)
            accessKeyId = resolved.accessKeyId
            secretAccessKey = resolved.secretAccessKey
            region = resolved.region
            sessionToken = resolved.sessionToken
        default:
            throw ProviderServiceError.invalidCredentials
        }
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        async let ec2 = fetchEC2Instances()
        async let lambda = fetchLambdaFunctions()
        async let s3 = fetchS3Buckets()
        async let cost = fetchCostAndUsage()

        var resources: [ResourceQuota] = []
        if let r = try? await ec2 { resources.append(contentsOf: r) }
        if let r = try? await lambda { resources.append(contentsOf: r) }
        if let r = try? await s3 { resources.append(contentsOf: r) }
        if let r = try? await cost { resources.append(contentsOf: r) }

        let totalCost = resources
            .compactMap(\.cost)
            .reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .aws,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    // MARK: - EC2

    private func fetchEC2Instances() async throws -> [ResourceQuota] {
        let url = URL(string: "https://ec2.\(region).amazonaws.com/?Action=DescribeInstances&Version=2016-11-15")!
        let headers = try signRequest(url: url, service: "ec2", method: "GET")
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: headers)

        guard (200..<300).contains(statusCode) else {
            throw ProviderServiceError.apiError(statusCode: statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        // Parse XML response for instance count
        let responseStr = String(data: data, encoding: .utf8) ?? ""
        let runningCount = responseStr.components(separatedBy: "<instanceState>")
            .filter { $0.contains("<name>running</name>") }
            .count

        return [
            ResourceQuota(
                id: "aws-ec2-running",
                category: .compute,
                name: "EC2 Running Instances",
                used: Double(runningCount),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Lambda

    private func fetchLambdaFunctions() async throws -> [ResourceQuota] {
        let url = URL(string: "https://lambda.\(region).amazonaws.com/2015-03-31/functions/")!
        let headers = try signRequest(url: url, service: "lambda", method: "GET")
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: headers)

        guard (200..<300).contains(statusCode) else {
            throw ProviderServiceError.apiError(statusCode: statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        struct LambdaListResponse: Decodable {
            let Functions: [LambdaFunction]?
            struct LambdaFunction: Decodable {
                let FunctionName: String
            }
        }

        let response = try JSONDecoder().decode(LambdaListResponse.self, from: data)
        let count = response.Functions?.count ?? 0

        return [
            ResourceQuota(
                id: "aws-lambda-functions",
                category: .serverless,
                name: "Lambda Functions",
                used: Double(count),
                limit: 1000, // default AWS limit
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - S3

    private func fetchS3Buckets() async throws -> [ResourceQuota] {
        let url = URL(string: "https://s3.\(region).amazonaws.com/")!
        let headers = try signRequest(url: url, service: "s3", method: "GET")
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: headers)

        guard (200..<300).contains(statusCode) else {
            throw ProviderServiceError.apiError(statusCode: statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        let responseStr = String(data: data, encoding: .utf8) ?? ""
        let bucketCount = responseStr.components(separatedBy: "<Bucket>").count - 1

        return [
            ResourceQuota(
                id: "aws-s3-buckets",
                category: .storage,
                name: "S3 Buckets",
                used: Double(max(bucketCount, 0)),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Cost Explorer

    private func fetchCostAndUsage() async throws -> [ResourceQuota] {
        let url = URL(string: "https://ce.\(region).amazonaws.com/")!
        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let body: [String: Any] = [
            "TimePeriod": [
                "Start": df.string(from: startOfMonth),
                "End": df.string(from: now)
            ],
            "Granularity": "MONTHLY",
            "Metrics": ["BlendedCost"]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var headers = try signRequest(url: url, service: "ce", method: "POST", body: bodyData)
        headers["X-Amz-Target"] = "AWSInsightsIndexService.GetCostAndUsage"
        headers["Content-Type"] = "application/x-amz-json-1.1"

        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, method: "POST", headers: headers, body: bodyData)

        guard (200..<300).contains(statusCode) else { return [] }

        struct CostResponse: Decodable {
            let ResultsByTime: [ResultByTime]?
            struct ResultByTime: Decodable {
                let Total: [String: MetricValue]?
                struct MetricValue: Decodable {
                    let Amount: String?
                }
            }
        }

        if let response = try? JSONDecoder().decode(CostResponse.self, from: data),
           let amount = response.ResultsByTime?.first?.Total?["BlendedCost"]?.Amount,
           let value = Double(amount) {
            return [
                ResourceQuota(
                    id: "aws-monthly-cost",
                    category: .billing,
                    name: "Month-to-Date Cost",
                    used: value,
                    limit: nil,
                    unit: .dollars,
                    cost: Decimal(value),
                    updatedAt: Date()
                )
            ]
        }

        return []
    }

    // MARK: - AWS Signature V4

    private func signRequest(
        url: URL,
        service: String,
        method: String,
        body: Data? = nil
    ) throws -> [String: String] {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        df.timeZone = TimeZone(identifier: "UTC")
        let amzDate = df.string(from: now)

        df.dateFormat = "yyyyMMdd"
        let dateStamp = df.string(from: now)

        let host = url.host ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query ?? ""

        let bodyHash = SHA256.hash(data: body ?? Data()).hexString

        let canonicalHeaders = "host:\(host)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-date"

        let canonicalRequest = [
            method, path, query,
            canonicalHeaders, signedHeaders, bodyHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        let kDate = hmacSHA256(key: Data("AWS4\(secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).hexString

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var headers = [
            "Authorization": authorization,
            "X-Amz-Date": amzDate,
            "X-Amz-Content-Sha256": bodyHash,
        ]
        if let sessionToken {
            headers["X-Amz-Security-Token"] = sessionToken
        }
        return headers
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
