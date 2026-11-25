import SwiftSensors
import SwiftUI

/// High-density telemetry panel designed for iPadOS Slide Over (floating side drawer
/// next to full-screen games or editing apps), respecting user visibility toggles.
struct SlideOverHUDView: View {
    @Environment(\.sensorsViewModel) private var viewModel
    @Bindable var hudController: PiPHUDController
    @State private var showCustomizationSheet: Bool = false

    private var snapshot: TelemetrySnapshot {
        self.hudController.latestSnapshot
    }

    private var config: TelemetryVisibilityConfig {
        self.hudController.visibilityConfig
    }

    private var showHeroSection: Bool {
        self.config.showSlideOverHeroSLA && self.config.hasAnyNetworkMetric
    }

    private var showThermalsSection: Bool {
        self.config.showSlideOverThermals && (
            self.config.showCPUTemp || (self.config.showGPUTemp && self.snapshot.gpuTemperature != nil)
        )
    }

    private var showNetworkCardSection: Bool {
        self.config.showSlideOverNetworkCard
    }

    private var showSystemSection: Bool {
        self.config.showSlideOverSystemCard && (
            self.config.showCPULoad
                || self.config.showRAM
                || self.config.showPowerWatts
                || self.config.showBattery
                || self.config.showThermalState
        )
    }

    private var showAnySection: Bool {
        self.showHeroSection
            || self.showThermalsSection
            || self.showNetworkCardSection
            || self.showSystemSection
            || self.config.showSlideOverGestureHint
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Label("Slide Over HUD", systemImage: "sidebar.right")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Label(L10n.tr("Live"), systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                .padding(.top, 4)

                if !self.showAnySection {
                    ContentUnavailableView {
                        Label(L10n.tr("Slide Over Hidden"), systemImage: "slider.horizontal.3")
                    } description: {
                        Text(L10n.tr("Enable at least one section to display metrics here."))
                    } actions: {
                        Button(L10n.tr("Customize Slide Over")) {
                            self.showCustomizationSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 32)
                } else {
                    if self.showHeroSection {
                        self.heroSLACard
                    }

                    if self.showThermalsSection {
                        HStack(spacing: 10) {
                            if self.config.showCPUTemp {
                                self.thermalTile(
                                    title: "CPU Die",
                                    systemImage: "cpu",
                                    temp: self.snapshot.cpuTemperature ?? self.snapshot.peakTemperature,
                                    sensorName: self.snapshot.cpuSensorName ?? self.snapshot.peakSensorName ?? L10n.tr("CPU Silicon")
                                )
                            }

                            if self.config.showGPUTemp, let gpuTemp = self.snapshot.gpuTemperature {
                                self.thermalTile(
                                    title: "GPU Die",
                                    systemImage: "square.grid.2x2",
                                    temp: gpuTemp,
                                    sensorName: self.snapshot.gpuSensorName ?? L10n.tr("Graphics Core")
                                )
                            }
                        }
                    }

                    if self.showNetworkCardSection {
                        NetworkSLACardView(hudController: self.hudController)
                    }

                    if self.showSystemSection {
                        self.systemResourcesCard
                    }

                    if self.config.showSlideOverGestureHint {
                        self.gestureHintCard
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(TelemetryTheme.groupedBackground)
        .navigationTitle("Slide Over")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.tr("Customize"), systemImage: "slider.horizontal.3") {
                    self.showCustomizationSheet = true
                }
            }
        }
        .sheet(isPresented: self.$showCustomizationSheet) {
            TelemetryCustomizationSheetView(hudController: self.hudController)
        }
    }

    private var heroSLACard: some View {
        let net = self.snapshot.network
        let lossRatio = net.totalLossPercent / 100.0
        let healthRatio = min(1.0, max(0.05, 1.0 - lossRatio))
        let healthColor = TelemetryTheme.lossColor(isLostNow: net.isLastProbeLost, lossPercent: net.totalLossPercent)

        return VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                if self.config.showPing {
                    if net.isLastProbeLost {
                        Text("DROP")
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .foregroundStyle(.red)
                    } else if let ping = net.pingMs {
                        Text(String(format: "%.0f", ping))
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(TelemetryTheme.pingColor(ping))

                        Text("ms")
                            .font(.headline.bold())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .foregroundStyle(.secondary)

                        Text("ms")
                            .font(.headline.bold())
                            .foregroundStyle(.secondary)
                    }
                } else if self.config.showUDPPing {
                    let udpVal = net.isUDPLastLost
                        ? "DROP"
                        : (net.udpPingMs.map { String(format: "%.0f ms", $0) } ?? "-- ms")
                    Text(udpVal)
                        .font(.system(.title, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(TelemetryTheme.pingColor(net.udpPingMs, isLost: net.isUDPLastLost))
                } else if self.config.showGatewayPing {
                    let gwVal = net.isGatewayLastProbeLost
                        ? "DROP"
                        : (net.gatewayPingMs.map { String(format: "%.1f ms", $0) } ?? "-- ms")
                    Text(gwVal)
                        .font(.system(.title, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(TelemetryTheme.pingColor(net.gatewayPingMs, isLost: net.isGatewayLastProbeLost))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if self.config.showPacketLoss {
                        HStack(spacing: 4) {
                            Text(L10n.tr("Loss:"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(net.totalLostCount > 0
                                ? String(format: "%.1f%% (%dp)", net.totalLossPercent, net.totalLostCount)
                                : "0.0%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                            .foregroundStyle(net.totalLostCount > 0 ? .red : .green)
                        }
                    }
                    if self.config.showJitter {
                        HStack(spacing: 4) {
                            Text("Jitter:")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(format: "±%.1f ms", net.jitterMs))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(net.jitterMs > 15 ? .orange : .green)
                        }
                    }
                }
            }

            if self.config.showUDPPing || self.config.showGatewayPing {
                HStack(spacing: 12) {
                    if self.config.showUDPPing {
                        let udpStr = net.isUDPLastLost
                            ? "UDP: DROP"
                            : (net.udpPingMs.map { String(format: "UDP: %.0f ms", $0) } ?? "UDP: --")
                        Text(udpStr)
                            .foregroundStyle(net.isUDPLastLost ? .red : .secondary)
                    }
                    if self.config.showGatewayPing {
                        let gwStr = net.isGatewayLastProbeLost
                            ? L10n.tr("Router: DROP")
                            : (net.gatewayPingMs.map { L10n.fmt("Router: %.1f ms", $0) } ?? L10n.tr("Router: --"))
                        Text(gwStr)
                            .foregroundStyle(net.isGatewayLastProbeLost ? .red : .secondary)
                    }
                    Spacer()
                }
                .font(.caption)
                .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(healthColor)
                        .frame(width: geo.size.width * CGFloat(healthRatio))
                }
            }
            .frame(height: 5)
        }
        .padding(TelemetryTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }

    private var systemResourcesCard: some View {
        VStack(spacing: 10) {
            if self.config.showCPULoad || self.config.showRAM {
                HStack {
                    if self.config.showCPULoad {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("CPU Load"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", self.snapshot.cpuTotalPercent))
                                .font(.headline.bold())
                                .monospacedDigit()
                                .foregroundStyle(TelemetryTheme.usageColor(self.snapshot.cpuTotalPercent))
                            Text(self.snapshot.topology.localizedCoreDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if self.config.showCPULoad && self.config.showRAM {
                        Spacer()
                    }

                    if self.config.showRAM {
                        VStack(alignment: self.config.showCPULoad ? .trailing : .leading, spacing: 2) {
                            Text(L10n.tr("Memory RAM"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f GB (%.0f%%)", self.snapshot.memoryUsedGB, self.snapshot.memoryUsedPercent))
                                .font(.headline.bold())
                                .monospacedDigit()
                                .foregroundStyle(TelemetryTheme.usageColor(self.snapshot.memoryUsedPercent))
                            Text(L10n.fmt("Free: %.1f GB", self.snapshot.memoryFreeGB))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !self.config.showCPULoad || !self.config.showRAM {
                        Spacer()
                    }
                }
            }

            if self.config.showPowerWatts, let watts = self.snapshot.estimatedWatts {
                if self.config.showCPULoad || self.config.showRAM {
                    Divider()
                }
                HStack {
                    Text(L10n.tr("Estimated Power"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f W", watts))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
            }

            if self.config.showBattery, let bat = self.snapshot.batteryPercent {
                if self.config.showCPULoad || self.config.showRAM || self.config.showPowerWatts {
                    Divider()
                }
                HStack {
                    Text(L10n.tr("Battery"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(self.snapshot.isCharging ? L10n.fmt("%lld%% (Charging)", bat) : "\(bat)%")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(bat <= 20 ? .red : .green)
                }
            }

            if self.config.showThermalState {
                if self.config.showCPULoad || self.config.showRAM || self.config.showPowerWatts || self.config.showBattery {
                    Divider()
                }
                HStack {
                    Text(L10n.tr("Thermal State"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(self.snapshot.thermalStateLocalized)
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            TelemetryTheme.thermalStateColor(
                                ThermalState(rawValue: self.snapshot.thermalState) ?? .unknown
                            )
                        )
                }
            }
        }
        .padding(TelemetryTheme.compactPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }

    private var gestureHintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.tr("Slide Over Gestures"), systemImage: "hand.draw")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)

            Text(L10n.tr("Drag the top grab bar toward the right edge to tuck this panel away over games; swipe from the right edge to bring it back anytime."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TelemetryTheme.compactPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func thermalTile(
        title: String,
        systemImage: String,
        temp: Double?,
        sensorName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(temp.map { String(format: "%.1f°C", $0) } ?? "--°C")
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(TelemetryTheme.temperatureColor(temp))

            Text(sensorName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(TelemetryTheme.compactPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }
}
