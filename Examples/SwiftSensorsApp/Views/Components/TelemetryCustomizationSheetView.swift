import SwiftUI

/// Interactive modal sheet allowing the user to customize which telemetry metrics
/// and UI sections appear across the PiP HUD, Slide Over drawer, and main dashboard.
struct TelemetryCustomizationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var hudController: PiPHUDController
    @State private var presetTrigger: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text(L10n.tr("Live PiP HUD Preview")),
                    footer: Text(L10n.tr("The Gamer Bar or Overlay size and blocks automatically adapt to enabled metrics."))
                ) {
                    PiPPreviewView(hudController: self.hudController)
                        .aspectRatio(self.hudController.currentCanvasAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                Section(header: Text(L10n.tr("Quick Presets"))) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                        spacing: 8
                    ) {
                        self.presetButton(
                            title: L10n.tr("Gamer (Default)"),
                            systemImage: "gamecontroller.fill",
                            preset: .gamerDefault
                        )
                        self.presetButton(
                            title: L10n.tr("Competitive Net"),
                            systemImage: "network",
                            preset: .networkCompetitive
                        )
                        self.presetButton(
                            title: L10n.tr("Ultra Minimal"),
                            systemImage: "minus.rectangle",
                            preset: .ultraMinimal
                        )
                        self.presetButton(
                            title: L10n.tr("Show All"),
                            systemImage: "checklist.checked",
                            preset: .allMetrics
                        )
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: self.presetTrigger)
                }

                Section(header: Text(L10n.tr("Hardware & Power (PiP, Slide Over & Dashboard)"))) {
                    Toggle(isOn: self.$hudController.visibilityConfig.showCPUTemp) {
                        Label("CPU °C (Die)", systemImage: "cpu")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showGPUTemp) {
                        Label("GPU °C (Die)", systemImage: "square.grid.2x2")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showCPULoad) {
                        Label(L10n.tr("CPU Load (%)"), systemImage: "gauge.medium")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showRAM) {
                        Label(L10n.tr("Memory RAM"), systemImage: "memorychip")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showPowerWatts) {
                        Label(L10n.tr("Power (Watts)"), systemImage: "bolt.fill")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showBattery) {
                        Label(L10n.tr("Battery (%)"), systemImage: "battery.100percent")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showThermalState) {
                        Label(L10n.tr("Thermal State"), systemImage: "thermometer.medium")
                    }
                }

                Section(
                    header: Text(L10n.tr("Network & Latency (PiP, Slide Over & Dashboard)")),
                    footer: Text(L10n.tr("Enabling UDP Probe automatically switches to Simultaneous mode (ICMP + UDP + TCP) for real-time UDP measurement."))
                ) {
                    Toggle(isOn: self.$hudController.visibilityConfig.showPing) {
                        Label("Ping / RTT (ms)", systemImage: "globe")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showPacketLoss) {
                        Label(L10n.tr("Packet Loss (%)"), systemImage: "exclamationmark.triangle")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showUDPPing) {
                        Label(L10n.tr("UDP Probe (DNS 53)"), systemImage: "bolt.horizontal.fill")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showGatewayPing) {
                        Label(L10n.tr("Local Router (Gateway)"), systemImage: "wifi.router")
                    }
                    Toggle(isOn: self.$hudController.visibilityConfig.showJitter) {
                        Label("Jitter (RFC 3550)", systemImage: "waveform.path.ecg")
                    }
                }

                Section(header: Text(L10n.tr("Visible Screens & Sections"))) {
                    Toggle(L10n.tr("Top Live Telemetry Strip"), isOn: self.$hudController.visibilityConfig.showDashboardLiveStrip)
                    Toggle(L10n.tr("PiP Control Card"), isOn: self.$hudController.visibilityConfig.showDashboardPiPCard)
                    Toggle(L10n.tr("Sensors & Diagnostics Grid"), isOn: self.$hudController.visibilityConfig.showDashboardSensorsGrid)

                    DisclosureGroup(L10n.tr("Choose grid modules")) {
                        ForEach(SensorSection.allCases, id: \.self) { section in
                            Toggle(
                                section.localizedTitle,
                                isOn: Binding(
                                    get: { self.hudController.visibilityConfig.isDashboardSectionVisible(section) },
                                    set: { self.hudController.visibilityConfig.setDashboardSection(section, visible: $0) }
                                )
                            )
                        }
                    }

                    Toggle(L10n.tr("Slide Over: Network Hero Card"), isOn: self.$hudController.visibilityConfig.showSlideOverHeroSLA)
                    Toggle(L10n.tr("Slide Over: CPU/GPU Thermal Cards"), isOn: self.$hudController.visibilityConfig.showSlideOverThermals)
                    Toggle(L10n.tr("Slide Over: Network & SLA Card"), isOn: self.$hudController.visibilityConfig.showSlideOverNetworkCard)
                    Toggle(L10n.tr("Slide Over: System & Power Card"), isOn: self.$hudController.visibilityConfig.showSlideOverSystemCard)
                    Toggle(L10n.tr("Slide Over: Gesture Hint"), isOn: self.$hudController.visibilityConfig.showSlideOverGestureHint)
                }
            }
            .navigationTitle(L10n.tr("Customize Metrics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done")) {
                        self.dismiss()
                    }
                }
            }
        }
    }

    private func presetButton(
        title: String,
        systemImage: String,
        preset: TelemetryVisibilityConfig
    ) -> some View {
        let isActive = self.hudController.visibilityConfig == preset
        return Button {
            self.hudController.visibilityConfig = preset
            self.presetTrigger += 1
        } label: {
            Label(title, systemImage: systemImage)
                .font(.footnote.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 8)
                .background(
                    (isActive ? Color.accentColor : Color.secondary).opacity(isActive ? 0.18 : 0.1),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
