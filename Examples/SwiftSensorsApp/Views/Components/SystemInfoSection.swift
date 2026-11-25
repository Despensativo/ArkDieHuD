import SwiftSensors
import SwiftUI

/// Display section for system information

struct SystemInfoSection: View {
    /// The sensor view model
    var viewModel: SensorsViewModel

    var body: some View {
        Section(header: Text(L10n.tr("System"))) {
            HStack {
                Text(L10n.tr("Thermal State"))
                Spacer()
                Text(TelemetryTheme.localizedThermalState(self.viewModel.thermalState.rawValue))
                    .foregroundStyle(TelemetryTheme.thermalStateColor(self.viewModel.thermalState))
            }

            InfoRow(label: L10n.tr("Uptime"), value: self.viewModel.uptimeText)
        }
    }
}