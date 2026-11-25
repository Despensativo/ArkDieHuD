import SwiftUI

/// UI for selecting time window for charts
struct TimeWindowPicker: View {
    /// The selected time window
    @Binding var timeWindow: TimeInterval

    var body: some View {
        Picker(L10n.tr("Time Window"), selection: self.$timeWindow) {
            Text(L10n.tr("1 minute")).tag(TimeInterval(60))
            Text(L10n.tr("5 minutes")).tag(TimeInterval(5 * 60))
            Text(L10n.tr("15 minutes")).tag(TimeInterval(15 * 60))
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.top, 8)
    }
}