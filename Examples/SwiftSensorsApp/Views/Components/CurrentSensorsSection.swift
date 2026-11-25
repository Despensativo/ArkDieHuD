import SwiftSensors
import SwiftUI

/// Display section for current sensors

struct CurrentSensorsSection: View {
    /// The sensor view model
    var viewModel: SensorsViewModel

    var body: some View {
        Section(header: Text(L10n.tr("Current Sensors"))) {
            ForEach(
                Array(zip(self.viewModel.currentSensorReadings.indices, self.viewModel.currentSensorReadings)),
                id: \.1.id
            ) { index, sensor in
                InfoRow(
                    label: sensor.name,
                    value: index < self.viewModel.formattedCurrents.count ? self.viewModel.formattedCurrents[index] : "\(sensor.current) A"
                )
            }

            if self.viewModel.currentSensorReadings.isEmpty {
                Text(L10n.tr("No current sensors found"))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}