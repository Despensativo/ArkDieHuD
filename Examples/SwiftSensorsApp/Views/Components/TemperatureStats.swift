import SwiftUI

/// Display for temperature statistics

struct TemperatureStats: View {
    /// Minimum temperature
    let minTemperature: Double

    /// Average temperature
    let avgTemperature: Double

    /// Maximum temperature
    let maxTemperature: Double

    var body: some View {
        HStack(spacing: 20) {
            StatBox(title: L10n.tr("Min"), value: String(format: "%.1f°C", self.minTemperature))
            StatBox(title: L10n.tr("Avg"), value: String(format: "%.1f°C", self.avgTemperature))
            StatBox(title: L10n.tr("Max"), value: String(format: "%.1f°C", self.maxTemperature))
        }
        .padding()
    }
}