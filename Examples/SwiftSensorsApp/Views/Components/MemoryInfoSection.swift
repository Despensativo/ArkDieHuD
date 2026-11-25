import SwiftSensors
import SwiftUI

/// Display section for memory information

struct MemoryInfoSection: View {
    /// The sensor view model
    var viewModel: SensorsViewModel

    var body: some View {
        Section(header: Text(L10n.tr("Memory Information"))) {
            if self.viewModel.memoryStats != nil, self.viewModel.formattedMemoryValues.count >= 9 {
                // Display in exact specified order
                InfoRow(label: L10n.tr("Free"), value: self.viewModel.formattedMemoryValues[1])
                InfoRow(label: L10n.tr("Active"), value: self.viewModel.formattedMemoryValues[2])
                InfoRow(label: L10n.tr("Inactive"), value: self.viewModel.formattedMemoryValues[3])
                InfoRow(label: L10n.tr("Wired"), value: self.viewModel.formattedMemoryValues[4])
                InfoRow(label: L10n.tr("Compressed"), value: self.viewModel.formattedMemoryValues[5])
                InfoRow(label: L10n.tr("Sum"), value: self.viewModel.formattedMemoryValues[6])
                InfoRow(label: L10n.tr("Total Physical"), value: self.viewModel.formattedMemoryValues[0])
                InfoRow(label: L10n.tr("Available to App"), value: self.viewModel.formattedMemoryValues[7])
                InfoRow(label: L10n.tr("Unavailable Remainder"), value: self.viewModel.formattedMemoryValues[8])
            } else {
                Text(L10n.tr("Loading memory information..."))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}
