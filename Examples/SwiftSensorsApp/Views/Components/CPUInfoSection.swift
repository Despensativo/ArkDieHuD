import SwiftSensors
import SwiftUI

/// Display section for CPU information

struct CPUInfoSection: View {
    /// The sensor view model
    var viewModel: SensorsViewModel

    var body: some View {
        Section(header: Text(L10n.tr("CPU Information"))) {
            if let stats = viewModel.cpuStats, viewModel.formattedCPUValues.count >= 3 {
                InfoRow(label: L10n.tr("CPU Usage"), value: self.viewModel.formattedCPUValues[0])
                InfoRow(label: L10n.tr("User"), value: self.viewModel.formattedCPUValues[1])
                InfoRow(label: L10n.tr("System"), value: self.viewModel.formattedCPUValues[2])
                InfoRow(label: L10n.tr("Active Processors"), value: "\(stats.activeProcessors) / \(stats.totalProcessors)")
            } else {
                Text(L10n.tr("Loading CPU information..."))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}