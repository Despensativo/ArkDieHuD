import SwiftSensors
import SwiftUI

/// Display section for disk information

struct DiskInfoSection: View {
    /// The sensor view model
    var viewModel: SensorsViewModel

    var body: some View {
        Section(header: Text(L10n.tr("Disk Information"))) {
            if self.viewModel.diskStats != nil, self.viewModel.formattedDiskValues.count >= 3 {
                InfoRow(label: L10n.tr("Total"), value: self.viewModel.formattedDiskValues[0])
                InfoRow(label: L10n.tr("Used"), value: self.viewModel.formattedDiskValues[1])
                InfoRow(label: L10n.tr("Free"), value: self.viewModel.formattedDiskValues[2])
            } else {
                Text(L10n.tr("Loading disk information..."))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}