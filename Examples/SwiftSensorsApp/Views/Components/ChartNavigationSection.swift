import SwiftUI

/// Navigation section for charts

struct ChartNavigationSection: View {
    /// Action for temperature charts
    var onTemperatureChartsSelected: () -> Void

    /// Action for power charts
    var onPowerChartsSelected: () -> Void

    var body: some View {
        Section {
            Button {
                self.onTemperatureChartsSelected()
            } label: {
                Text(L10n.tr("View Temperature Charts"))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                self.onPowerChartsSelected()
            } label: {
                Text(L10n.tr("View Power Charts"))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}