import SwiftSensors
import SwiftUI

/// Centralized visual tokens and semantic telemetry color rules (2026 Operate Mode).
enum TelemetryTheme {
    // MARK: - Layout Tokens

    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let gridSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let compactPadding: CGFloat = 12
    static let minTouchTarget: CGFloat = 44

    // MARK: - Semantic Surfaces (Light & Dark Adaptive)

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtleBorder = Color(uiColor: .separator).opacity(0.35)

    // MARK: - Telemetry Semantic Colors

    static func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        if celsius >= 55 { return .red }
        if celsius >= 45 { return .orange }
        if celsius >= 38 { return .yellow }
        return .green
    }

    static func usageColor(_ percent: Double) -> Color {
        if percent >= 85 { return .red }
        if percent >= 65 { return .orange }
        return .blue
    }

    static func pingColor(_ pingMs: Double?, isLost: Bool = false) -> Color {
        if isLost { return .red }
        guard let pingMs else { return .secondary }
        if pingMs <= 30 { return .green }
        if pingMs <= 65 { return .teal }
        if pingMs <= 110 { return .orange }
        return .red
    }

    static func lossColor(isLostNow: Bool, lossPercent: Double) -> Color {
        if isLostNow || lossPercent > 5.0 { return .red }
        if lossPercent > 0.0 { return .orange }
        return .green
    }

    static func thermalStateColor(_ state: ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    static func localizedThermalState(_ rawValue: String) -> String {
        switch rawValue {
        case "Nominal": return L10n.tr("Nominal")
        case "Fair": return L10n.tr("Fair")
        case "Serious": return L10n.tr("Serious")
        case "Critical": return L10n.tr("Critical")
        default: return rawValue
        }
    }
}
