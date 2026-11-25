import SwiftSensors
import SwiftUI

/// Primary real-time telemetry focal strip showing customizable live Silicon thermals,
/// power/RAM, battery, and competitive network metrics at the top of the app.
struct LiveTelemetryStripView: View {
    private struct StripTileItem: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let value: String
        let valueColor: Color
        let subtitle: String
        let destination: NavigationDestination?
    }

    let snapshot: TelemetrySnapshot
    var config: TelemetryVisibilityConfig = .gamerDefault

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var tiles: [StripTileItem] {
        var items: [StripTileItem] = []

        if self.config.showCPUTemp {
            let cpuT = self.cpuTemp
            items.append(StripTileItem(
                id: "cpu_temp",
                title: "CPU Die",
                systemImage: "cpu",
                value: cpuT.map { String(format: "%.1f°C", $0) } ?? "--°C",
                valueColor: TelemetryTheme.temperatureColor(cpuT),
                subtitle: self.snapshot.cpuSensorName ?? self.snapshot.peakSensorName ?? L10n.tr("CPU Silicon"),
                destination: nil
            ))
        }

        if self.config.showGPUTemp {
            items.append(StripTileItem(
                id: "gpu_temp",
                title: "GPU Die",
                systemImage: "square.grid.2x2",
                value: self.snapshot.gpuTemperature.map { String(format: "%.1f°C", $0) } ?? "--°C",
                valueColor: TelemetryTheme.temperatureColor(self.snapshot.gpuTemperature),
                subtitle: self.snapshot.gpuSensorName ?? L10n.tr("Graphics Core"),
                destination: nil
            ))
        }

        if self.config.showCPULoad {
            items.append(StripTileItem(
                id: "cpu_load",
                title: L10n.tr("CPU Load"),
                systemImage: "gauge.medium",
                value: String(format: "%.0f%%", self.snapshot.cpuTotalPercent),
                valueColor: TelemetryTheme.usageColor(self.snapshot.cpuTotalPercent),
                subtitle: self.snapshot.topology.localizedCoreDescription,
                destination: .sectionDetail(section: .cpu)
            ))
        }

        if self.config.showPowerWatts {
            let powerVal = self.snapshot.estimatedWatts.map { String(format: "%.1f W", $0) } ?? "-- W"
            let state = TelemetryTheme.localizedThermalState(self.snapshot.thermalState)
            items.append(StripTileItem(
                id: "power",
                title: L10n.tr("Power"),
                systemImage: "bolt.fill",
                value: powerVal,
                valueColor: .orange,
                subtitle: self.config.showRAM
                    ? L10n.fmt("State: %@", state)
                    : String(format: "RAM %.1f GB • %@", self.snapshot.memoryUsedGB, state),
                destination: nil
            ))
        }

        if self.config.showRAM {
            items.append(StripTileItem(
                id: "ram",
                title: L10n.tr("Memory RAM"),
                systemImage: "memorychip",
                value: String(format: "%.1f GB", self.snapshot.memoryUsedGB),
                valueColor: TelemetryTheme.usageColor(self.snapshot.memoryUsedPercent),
                subtitle: L10n.fmt("%.0f%% of %.0f GB", self.snapshot.memoryUsedPercent, self.snapshot.memoryTotalGB),
                destination: .sectionDetail(section: .memory)
            ))
        }

        if self.config.showBattery {
            let batVal = self.snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
            items.append(StripTileItem(
                id: "battery",
                title: L10n.tr("Battery"),
                systemImage: self.snapshot.isCharging ? "battery.100percent.bolt" : "battery.100percent",
                value: batVal,
                valueColor: (self.snapshot.batteryPercent ?? 100) <= 20 ? .red : .green,
                subtitle: self.snapshot.isCharging ? L10n.tr("Charging") : L10n.tr("Discharging"),
                destination: .sectionDetail(section: .system)
            ))
        }

        if self.config.showThermalState {
            let state = self.snapshot.thermalStateLocalized
            let parsedState = ThermalState(rawValue: self.snapshot.thermalState) ?? .unknown
            items.append(StripTileItem(
                id: "thermal_state",
                title: L10n.tr("Thermal State"),
                systemImage: "thermometer.medium",
                value: state,
                valueColor: TelemetryTheme.thermalStateColor(parsedState),
                subtitle: L10n.tr("iPadOS Rating"),
                destination: .sectionDetail(section: .system)
            ))
        }

        if self.config.showPing {
            let pingTitle = self.snapshot.network.route.isVPNActive ? "Ping • VPN" : "Ping / RTT"
            items.append(StripTileItem(
                id: "network_primary",
                title: pingTitle,
                systemImage: self.snapshot.network.route.isVPNActive ? "lock.shield" : "globe",
                value: self.pingText,
                valueColor: TelemetryTheme.pingColor(
                    self.snapshot.network.pingMs,
                    isLost: self.snapshot.network.isLastProbeLost
                ),
                subtitle: self.snapshot.network.target.name,
                destination: .networkDiagnostics
            ))
        }

        if self.config.showPacketLoss {
            let totalLost = self.snapshot.network.totalLostCount
            let lossPct = self.snapshot.network.totalLossPercent
            let lossVal = self.snapshot.network.isLastProbeLost
                ? "DROP!"
                : String(format: "%.1f%%", lossPct)
            items.append(StripTileItem(
                id: "network_loss",
                title: L10n.tr("Packet Loss"),
                systemImage: "exclamationmark.triangle",
                value: lossVal,
                valueColor: TelemetryTheme.lossColor(
                    isLostNow: self.snapshot.network.isLastProbeLost,
                    lossPercent: lossPct
                ),
                subtitle: L10n.fmt("%lldp lost • 120s: %.1f%%", totalLost, self.snapshot.network.lossPercent120s),
                destination: .networkDiagnostics
            ))
        }

        if self.config.showUDPPing {
            let udpLost = self.snapshot.network.isUDPLastLost
            let udpValue = udpLost
                ? "DROP"
                : (self.snapshot.network.udpPingMs.map { String(format: "%.0f ms", $0) } ?? "-- ms")
            items.append(StripTileItem(
                id: "network_udp",
                title: L10n.tr("UDP Probe"),
                systemImage: "bolt.horizontal.fill",
                value: udpValue,
                valueColor: TelemetryTheme.pingColor(self.snapshot.network.udpPingMs, isLost: udpLost),
                subtitle: L10n.fmt("Loss %.1f%% • %@", self.snapshot.network.udpLossPercent, self.snapshot.network.udpProbeHost),
                destination: .networkDiagnostics
            ))
        }

        if self.config.showGatewayPing {
            let gwLost = self.snapshot.network.isGatewayLastProbeLost
            let gwValue = gwLost
                ? "DROP"
                : (self.snapshot.network.gatewayPingMs.map { String(format: "%.1f ms", $0) } ?? "-- ms")
            items.append(StripTileItem(
                id: "network_gw",
                title: L10n.tr("Local Router"),
                systemImage: "wifi.router",
                value: gwValue,
                valueColor: TelemetryTheme.pingColor(self.snapshot.network.gatewayPingMs, isLost: gwLost),
                subtitle: self.snapshot.network.gatewayHost ?? L10n.tr("Auto Gateway"),
                destination: .networkDiagnostics
            ))
        }

        if self.config.showJitter {
            let jitter = self.snapshot.network.jitterMs
            items.append(StripTileItem(
                id: "network_jitter",
                title: "Jitter RFC",
                systemImage: "waveform.path.ecg",
                value: String(format: "±%.1f ms", jitter),
                valueColor: jitter > 15 ? .orange : .green,
                subtitle: L10n.tr("Packet delay variation"),
                destination: .networkDiagnostics
            ))
        }

        return items
    }

    private var columns: [GridItem] {
        let maxCols = (self.horizontalSizeClass == .regular) ? 4 : 2
        let count = max(1, min(self.tiles.count, maxCols))
        return Array(repeating: GridItem(.flexible(), spacing: TelemetryTheme.gridSpacing), count: count)
    }

    var body: some View {
        let activeTiles = self.tiles
        LazyVGrid(columns: self.columns, spacing: TelemetryTheme.gridSpacing) {
            ForEach(activeTiles) { tile in
                if let destination = tile.destination {
                    NavigationLink(value: destination) {
                        self.metricTile(
                            title: tile.title,
                            systemImage: tile.systemImage,
                            value: tile.value,
                            valueColor: tile.valueColor,
                            subtitle: tile.subtitle,
                            showDisclosure: true
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    self.metricTile(
                        title: tile.title,
                        systemImage: tile.systemImage,
                        value: tile.value,
                        valueColor: tile.valueColor,
                        subtitle: tile.subtitle,
                        showDisclosure: false
                    )
                }
            }
        }
    }

    private var cpuTemp: Double? {
        self.snapshot.cpuTemperature ?? self.snapshot.peakTemperature
    }

    private var pingText: String {
        if self.snapshot.network.isLastProbeLost {
            return "DROP"
        }
        if let ping = self.snapshot.network.pingMs {
            return String(format: "%.0f ms", ping)
        }
        return "-- ms"
    }

    private func metricTile(
        title: String,
        systemImage: String,
        value: String,
        valueColor: Color,
        subtitle: String,
        showDisclosure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showDisclosure {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
