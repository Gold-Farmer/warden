import SwiftUI

enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case aws
    case gcp
    case azure
    case cloudflare
    case openai
    case anthropic
    case gemini
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aws: "AWS"
        case .gcp: "Google Cloud"
        case .azure: "Azure"
        case .cloudflare: "Cloudflare"
        case .openai: "OpenAI"
        case .anthropic: "Claude / Anthropic"
        case .gemini: "Gemini / Google AI"
        case .grok: "Grok / xAI"
        }
    }

    var iconName: String {
        switch self {
        case .aws: "cloud.fill"
        case .gcp: "server.rack"
        case .azure: "cloud.bolt.fill"
        case .cloudflare: "shield.checkered"
        case .openai: "brain.head.profile"
        case .anthropic: "bubble.left.and.text.bubble.right"
        case .gemini: "sparkles"
        case .grok: "bolt.circle.fill"
        }
    }

    var brandColor: Color {
        switch self {
        case .aws: Color.orange
        case .gcp: Color.blue
        case .azure: Color.cyan
        case .cloudflare: Color.orange.opacity(0.8)
        case .openai: Color.green
        case .anthropic: Color(red: 0.82, green: 0.55, blue: 0.28)
        case .gemini: Color.indigo
        case .grok: Color.purple
        }
    }

    var shortName: String {
        switch self {
        case .aws: "AWS"
        case .gcp: "GCP"
        case .azure: "Azure"
        case .cloudflare: "CF"
        case .openai: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }

    var isCloudProvider: Bool {
        switch self {
        case .aws, .gcp, .azure, .cloudflare: true
        case .openai, .anthropic, .gemini, .grok: false
        }
    }

    var isAIProvider: Bool { !isCloudProvider }
}
