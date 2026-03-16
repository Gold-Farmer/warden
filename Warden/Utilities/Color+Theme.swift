import SwiftUI

// MARK: - Grafana-Inspired Color Palette

extension Color {
    // Canvas / backgrounds
    static let grafanaBg = Color(hex: 0x111217)
    static let grafanaPanelBg = Color(hex: 0x181B1F)
    static let grafanaPanelBorder = Color(hex: 0x2C3035)
    static let grafanaPanelHeaderBg = Color(hex: 0x1D2025)
    static let grafanaHoverBg = Color(hex: 0x22252B)

    // Text
    static let grafanaTextPrimary = Color(hex: 0xEEEEEE)
    static let grafanaTextSecondary = Color(hex: 0x8E8E8E)
    static let grafanaTextDisabled = Color(hex: 0x5A5A5A)

    // Threshold palette
    static let grafanaGreen = Color(hex: 0x73BF69)
    static let grafanaYellow = Color(hex: 0xFF9830)
    static let grafanaOrange = Color(hex: 0xFF780A)
    static let grafanaRed = Color(hex: 0xF2495C)

    // Accent / brand
    static let grafanaBlue = Color(hex: 0x5794F2)
    static let grafanaPurple = Color(hex: 0xB877D9)
    static let grafanaCyan = Color(hex: 0x4ECDC4)

    // Stat value colors
    static func forFraction(_ fraction: Double?) -> Color {
        guard let fraction else { return .grafanaTextDisabled }
        if fraction >= 0.9 { return .grafanaRed }
        if fraction >= 0.7 { return .grafanaYellow }
        return .grafanaGreen
    }

    static func forHealth(_ health: ProviderStatus.Health) -> Color {
        switch health {
        case .healthy: .grafanaGreen
        case .warning: .grafanaYellow
        case .critical: .grafanaRed
        case .unknown: .grafanaTextDisabled
        }
    }

    static func forUtilization(_ level: UtilizationLevel) -> Color {
        switch level {
        case .healthy: .grafanaGreen
        case .warning: .grafanaYellow
        case .critical: .grafanaRed
        case .unknown: .grafanaTextDisabled
        }
    }

    // Gradient for bar gauges (green → yellow → red)
    static let grafanaThresholdGradient = LinearGradient(
        colors: [.grafanaGreen, .grafanaYellow, .grafanaOrange, .grafanaRed],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// Allow .grafanaXxx in foregroundStyle() context
extension ShapeStyle where Self == Color {
    static var grafanaBg: Color { .grafanaBg }
    static var grafanaPanelBg: Color { .grafanaPanelBg }
    static var grafanaPanelBorder: Color { .grafanaPanelBorder }
    static var grafanaPanelHeaderBg: Color { .grafanaPanelHeaderBg }
    static var grafanaHoverBg: Color { .grafanaHoverBg }
    static var grafanaTextPrimary: Color { .grafanaTextPrimary }
    static var grafanaTextSecondary: Color { .grafanaTextSecondary }
    static var grafanaTextDisabled: Color { .grafanaTextDisabled }
    static var grafanaGreen: Color { .grafanaGreen }
    static var grafanaYellow: Color { .grafanaYellow }
    static var grafanaOrange: Color { .grafanaOrange }
    static var grafanaRed: Color { .grafanaRed }
    static var grafanaBlue: Color { .grafanaBlue }
    static var grafanaPurple: Color { .grafanaPurple }
    static var grafanaCyan: Color { .grafanaCyan }
}

// MARK: - Provider brand colors (Grafana-compatible, vibrant on dark)

extension Provider {
    var grafanaColor: Color {
        switch self {
        case .aws: Color(hex: 0xFF9900)
        case .gcp: Color(hex: 0x4285F4)
        case .azure: Color(hex: 0x00BCF2)
        case .cloudflare: Color(hex: 0xF6821F)
        case .openai: Color(hex: 0x74AA9C)
        case .anthropic: Color(hex: 0xD4A574)
        case .gemini: Color(hex: 0x8E75B2)
        case .grok: Color(hex: 0xEE4D2D)
        }
    }
}
