import SwiftSensors
import SwiftUI
import UniformTypeIdentifiers

/// Transferable wrapper so ShareLink builds and exports the .csv report on demand.
struct NetworkCSVDocument: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { _ in
            let csv = await SwiftSensors.shared.exportNetworkDiagnosticsCSV()
            return Data(csv.utf8)
        }
    }
}

/// Dedicated network quality, dual-probe (router vs external target), latency percentiles,
/// and chronological incident log view.
struct NetworkDiagnosticsView: View {
    enum IncidentFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drops = "Drops"
        case spikes = "Spikes"
        case routes = "Routes"

        var id: String { self.rawValue }

        var localizedTitle: String {
            L10n.tr(self.rawValue)
        }
    }

    @Bindable var hudController: PiPHUDController

    @State private var samples: [NetworkProbeSample] = []
    @State private var incidents: [NetworkIncidentEvent] = []
    @State private var filter: IncidentFilter = .all
    @State private var showTargetConfig: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var resetTrigger: Int = 0

    private var metrics: NetworkQualityMetrics {
        self.hudController.latestSnapshot.network
    }

    private var filteredIncidents: [NetworkIncidentEvent] {
        let ordered = self.incidents.reversed()
        switch self.filter {
        case .all:
            return Array(ordered)
        case .drops:
            return ordered.filter {
                $0.kind == .ispDrop
                    || $0.kind == .localDrop
                    || $0.kind == .protocolDrop
                    || $0.kind == .drop
                    || $0.kind == .burst
            }
        case .spikes:
            return ordered.filter { $0.kind == .spike }
        case .routes:
            return ordered.filter { $0.kind == .routeChange }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelemetryTheme.sectionSpacing) {
                self.dualProbeSection
                self.slaPercentilesSection
                NetworkLatencyChartView(
                    samples: self.samples,
                    isMultiProtocol: self.metrics.isMultiProtocolActive
                )
                self.incidentsSection
            }
            .padding()
        }
        .background(TelemetryTheme.groupedBackground)
        .navigationTitle(L10n.tr("Network & Packet Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(L10n.tr("Configure Target"), systemImage: "slider.horizontal.3") {
                    self.showTargetConfig = true
                }

                ShareLink(
                    item: NetworkCSVDocument(),
                    preview: SharePreview("ArkDieHuD_Network.csv", image: Image(systemName: "doc.text"))
                ) {
                    Label(L10n.tr("Export CSV"), systemImage: "square.and.arrow.up")
                }

                Button(L10n.tr("Reset Counters"), systemImage: "arrow.counterclockwise") {
                    self.showResetConfirmation = true
                }
                .sensoryFeedback(.warning, trigger: self.resetTrigger)
            }
        }
        .sheet(isPresented: self.$showTargetConfig) {
            NetworkTargetSheetView(
                currentTarget: self.metrics.target,
                detectedGatewayIP: self.metrics.route.detectedGatewayIP,
                initialCustomGateway: self.metrics.isGatewayCustom ? self.metrics.gatewayHost : nil,
                isGatewayCustomInitial: self.metrics.isGatewayCustom,
                currentProtocol: self.metrics.protocolPreference
            ) {
                Task {
                    await self.refreshHistoryAndIncidents()
                }
            }
        }
        .alert(L10n.tr("Reset network history?"), isPresented: self.$showResetConfirmation) {
            Button(L10n.tr("Reset All"), role: .destructive) {
                self.resetTrigger += 1
                Task {
                    await SwiftSensors.shared.resetNetworkStats()
                    await self.refreshHistoryAndIncidents()
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("This will clear the chart samples (up to 1h), the incident log, and the current session packet loss counters."))
        }
        .task {
            while !Task.isCancelled {
                await self.refreshHistoryAndIncidents()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Section 1: Dual Probe & Root-Cause Summary

    private var dualProbeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.tr("Simultaneous Dual Probe"), systemImage: "arrow.triangle.branch")
                    .font(.headline)

                Spacer()

                Label(
                    self.metrics.route.localizedSummary,
                    systemImage: self.metrics.route.isVPNActive ? "lock.shield.fill" : "wifi"
                )
                .font(.footnote.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (self.metrics.route.isVPNActive ? Color.orange : Color.accentColor).opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(self.metrics.route.isVPNActive ? .orange : Color.accentColor)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: TelemetryTheme.gridSpacing) {
                    self.gatewayTile
                    self.externalTargetTile
                }
                VStack(spacing: TelemetryTheme.gridSpacing) {
                    self.gatewayTile
                    self.externalTargetTile
                }
            }

            if self.metrics.isMultiProtocolActive {
                self.multiProtocolComparisonCard
            }

            self.rootCauseBanner
        }
    }

    private var multiProtocolComparisonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.tr("Multi-Protocol Comparison"), systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text(L10n.fmt("UDP on %@:53", self.metrics.udpProbeHost))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                self.protocolBadgeCell(
                    name: "ICMP",
                    icon: "globe",
                    accent: Color.accentColor,
                    pingMs: self.metrics.icmpPingMs,
                    isLost: self.metrics.isICMPLastLost,
                    lostCount: self.metrics.icmpLostCount,
                    lossPercent: self.metrics.icmpLossPercent
                )
                self.protocolBadgeCell(
                    name: "UDP",
                    icon: "bolt.horizontal.fill",
                    accent: .orange,
                    pingMs: self.metrics.udpPingMs,
                    isLost: self.metrics.isUDPLastLost,
                    lostCount: self.metrics.udpLostCount,
                    lossPercent: self.metrics.udpLossPercent
                )
                self.protocolBadgeCell(
                    name: "TCP",
                    icon: "arrow.left.arrow.right",
                    accent: .purple,
                    pingMs: self.metrics.tcpPingMs,
                    isLost: self.metrics.isTCPLastLost,
                    lostCount: self.metrics.tcpLostCount,
                    lossPercent: self.metrics.tcpLossPercent
                )
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

    private func protocolBadgeCell(
        name: String,
        icon: String,
        accent: Color,
        pingMs: Double?,
        isLost: Bool,
        lostCount: Int,
        lossPercent: Double
    ) -> some View {
        let pingText: String = {
            if isLost { return "DROP" }
            if let pingMs { return String(format: "%.0f ms", pingMs) }
            return "--"
        }()

        return VStack(alignment: .leading, spacing: 3) {
            Label(name, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(accent)

            Text(pingText)
                .font(.headline.bold())
                .monospacedDigit()
                .foregroundStyle(isLost ? .red : TelemetryTheme.pingColor(pingMs, isLost: false))

            Text(String(format: "%.1f%% (%dp)", lossPercent, lostCount))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(lostCount > 0 ? .orange : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.08))
        )
    }

    private var gatewayTile: some View {
        let pingValue: String = {
            if self.metrics.isGatewayLastProbeLost { return "DROP" }
            if let gw = self.metrics.gatewayPingMs { return String(format: "%.1f ms", gw) }
            return "-- ms"
        }()

        let pingColor: Color = self.metrics.gatewayHost == nil
            ? .secondary
            : TelemetryTheme.pingColor(self.metrics.gatewayPingMs, isLost: self.metrics.isGatewayLastProbeLost)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.tr("Local Router"), systemImage: "wifi.router")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(self.metrics.isGatewayCustom ? L10n.tr("Manual") : L10n.tr("Auto"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(pingValue)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(pingColor)

            Text(self.metrics.gatewayHost ?? L10n.tr("Gateway not detected"))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(L10n.fmt("Local loss: %.1f%% (%lldp)", self.metrics.gatewayTotalLossPercent, self.metrics.gatewayTotalLostCount))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(self.metrics.gatewayTotalLostCount > 0 ? .red : .secondary)
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

    private var externalTargetTile: some View {
        let pingValue: String = {
            if self.metrics.isLastProbeLost { return "DROP" }
            if let ping = self.metrics.pingMs { return String(format: "%.0f ms", ping) }
            return "-- ms"
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.tr("External Target"), systemImage: "globe")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(self.metrics.activeTransport.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Text(pingValue)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(
                    TelemetryTheme.pingColor(self.metrics.pingMs, isLost: self.metrics.isLastProbeLost)
                )

            Text("\(self.metrics.target.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(L10n.fmt("External loss: %.1f%% (%lldp)", self.metrics.totalLossPercent, self.metrics.totalLostCount))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(
                    TelemetryTheme.lossColor(
                        isLostNow: self.metrics.isLastProbeLost,
                        lossPercent: self.metrics.totalLossPercent
                    )
                )
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

    private var rootCauseBanner: some View {
        let tint: Color
        let icon: String
        let text: String

        if self.metrics.localAndExternalDropCount > 0 {
            tint = .red
            icon = "wifi.exclamationmark"
            text = L10n.fmt("Simultaneous router drops (%lldx): check local Wi-Fi signal or router.", self.metrics.localAndExternalDropCount)
        } else if self.metrics.ispOnlyDropCount > 0 {
            tint = .orange
            icon = "exclamationmark.triangle.fill"
            text = L10n.fmt("External drops (%lldx) while local router is stable: direct sign of ISP route or VPN issue.", self.metrics.ispOnlyDropCount)
        } else if self.metrics.isMultiProtocolActive && self.metrics.udpLostCount > 0 && (self.metrics.icmpLostCount == 0 || self.metrics.tcpLostCount == 0) {
            tint = .orange
            icon = "bolt.slash.fill"
            text = L10n.fmt("Isolated UDP loss (%lldx): indicates CGNAT/NAT UDP bottleneck or QoS (affects games like PUBG).", self.metrics.udpLostCount)
        } else if self.metrics.isMultiProtocolActive && self.metrics.icmpLostCount > 0 && self.metrics.udpLostCount == 0 && self.metrics.tcpLostCount == 0 {
            tint = Color.accentColor
            icon = "info.circle.fill"
            text = L10n.fmt("Isolated ICMP-only loss (%lldx): likely server ping rate limit; UDP/TCP stable (does not affect gaming).", self.metrics.icmpLostCount)
        } else {
            tint = .green
            icon = "checkmark.shield.fill"
            text = self.metrics.isMultiProtocolActive
                ? L10n.tr("Multi-probe active: comparing ICMP, UDP & TCP against your local router every 1s.")
                : L10n.fmt("Dual probe active: comparing your local router with %@ every 1s.", self.metrics.target.host)
        }

        return Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TelemetryTheme.compactPadding)
            .background(
                RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                    .fill(tint.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                    )
            )
    }

    // MARK: - Section 2: Percentiles, Burst & Cycle Stats

    private var slaPercentilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Latency SLA & Stability"))
                .font(.headline)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                self.statCell(
                    label: L10n.tr("P50 (Median)"),
                    value: self.metrics.p50Ms.map { String(format: "%.0f ms", $0) } ?? "--"
                )
                self.statCell(
                    label: "P95",
                    value: self.metrics.p95Ms.map { String(format: "%.0f ms", $0) } ?? "--"
                )
                self.statCell(
                    label: L10n.tr("P99 (Worst 1%)"),
                    value: self.metrics.p99Ms.map { String(format: "%.0f ms", $0) } ?? "--"
                )
                self.statCell(
                    label: "Jitter RFC",
                    value: String(format: "±%.1f ms", self.metrics.jitterMs)
                )
                self.statCell(
                    label: L10n.tr("Max Burst"),
                    value: "\(self.metrics.maxBurstLoss) pkts"
                )
                self.statCell(
                    label: L10n.tr("ISP Cycle"),
                    value: self.metrics.detectedCycleSeconds.map { String(format: "~%.0fs", $0) } ?? L10n.tr("Monitoring")
                )
            }
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

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section 3: Chronological Incident Timeline

    private var incidentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("Incident Log"))
                    .font(.headline)
                Spacer()
                Text(L10n.fmt("%lld events", self.filteredIncidents.count))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker(L10n.tr("Filter"), selection: self.$filter) {
                ForEach(IncidentFilter.allCases) { item in
                    Text(item.localizedTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if self.filteredIncidents.isEmpty {
                ContentUnavailableView(
                    L10n.tr("No incidents recorded"),
                    systemImage: "checkmark.shield",
                    description: Text(L10n.tr("Drops, bursts, latency spikes, and route switches will appear here chronologically."))
                )
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(self.filteredIncidents.prefix(120).enumerated()), id: \.element.id) { idx, event in
                        if idx > 0 {
                            Divider()
                        }
                        self.incidentRow(event)
                    }
                }
            }
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

    private func incidentRow(_ event: NetworkIncidentEvent) -> some View {
        let style = self.incidentVisuals(for: event.kind)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .foregroundStyle(style.color)

                Text(event.kind.localizedTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(style.color)

                if let delta = event.deltaSincePreviousDropSeconds {
                    Text(String(format: "Δ +%.0fs", delta))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(style.color.opacity(0.14), in: Capsule())
                        .foregroundStyle(style.color)
                }

                Spacer()

                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(event.details)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text("Seq #\(event.sequence) • \(event.routeLabel)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func incidentVisuals(for kind: NetworkIncidentKind) -> (icon: String, color: Color) {
        switch kind {
        case .ispDrop, .drop:
            return ("exclamationmark.triangle.fill", .red)
        case .localDrop:
            return ("wifi.exclamationmark", .red)
        case .protocolDrop:
            return ("bolt.slash.fill", .orange)
        case .burst:
            return ("flame.fill", .orange)
        case .spike:
            return ("waveform.path.ecg", .yellow)
        case .routeChange:
            return ("arrow.triangle.2.circlepath", Color.accentColor)
        }
    }

    private func refreshHistoryAndIncidents() async {
        async let samplesTask = SwiftSensors.shared.getNetworkProbeHistory(limit: 3600)
        async let incidentsTask = SwiftSensors.shared.getNetworkIncidents()

        let fetchedSamples = await samplesTask
        let fetchedIncidents = await incidentsTask

        self.samples = fetchedSamples
        self.incidents = fetchedIncidents
    }
}
