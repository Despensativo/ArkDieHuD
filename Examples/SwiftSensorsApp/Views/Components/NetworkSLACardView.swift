import SwiftSensors
import SwiftUI

/// Dedicated real-time Network SLA & Cumulative Packet Loss card shared between
/// Slide Over HUD and main telemetry screens (100% SF Symbols, tabular digits).
struct NetworkSLACardView: View {
    @Bindable var hudController: PiPHUDController
    @State private var showTargetConfig: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var resetTrigger: Int = 0

    private var network: NetworkQualityMetrics {
        self.hudController.latestSnapshot.network
    }

    private var borderHighlight: Color {
        if self.network.isLastProbeLost {
            return Color.red.opacity(0.45)
        }
        if self.network.lostCount60s > 0 {
            return Color.orange.opacity(0.35)
        }
        return TelemetryTheme.subtleBorder
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header & Target Probe Selector
            HStack {
                Label(L10n.tr("Network & Connection SLA"), systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    ForEach(NetworkProbeTarget.defaultTargets) { target in
                        Button(target.name) {
                            Task {
                                await SwiftSensors.shared.setNetworkProbeTarget(target)
                            }
                        }
                    }

                    Divider()

                    Button {
                        Task {
                            await SwiftSensors.shared.setNetworkProbeProtocol(.simultaneous)
                        }
                    } label: {
                        Label(
                            L10n.tr("Simultaneous Mode (ICMP+UDP+TCP)"),
                            systemImage: self.network.protocolPreference == .simultaneous
                                ? "checkmark"
                                : "square.stack.3d.up"
                        )
                    }

                    Button {
                        Task {
                            await SwiftSensors.shared.setNetworkProbeProtocol(.auto)
                        }
                    } label: {
                        Label(
                            L10n.tr("Light Mode (Auto ICMP->TCP)"),
                            systemImage: self.network.protocolPreference == .auto
                                ? "checkmark"
                                : "waveform"
                        )
                    }

                    Divider()

                    Button(L10n.tr("Customize Server / Router..."), systemImage: "slider.horizontal.3") {
                        self.showTargetConfig = true
                    }
                } label: {
                    Label(self.network.target.name, systemImage: "chevron.up.chevron.down")
                        .font(.footnote.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 34)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .sensoryFeedback(.selection, trigger: self.network.target.id)
            }

            // Compact Dual Probe (Router vs External) & Active Route/VPN Bar
            HStack(spacing: 8) {
                Label(
                    self.gatewayCompactText,
                    systemImage: "wifi.router"
                )
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(
                    self.network.isGatewayLastProbeLost ? .red : .secondary
                )

                Spacer()

                Label(
                    self.network.route.isVPNActive
                        ? "\(self.network.route.localizedSummary) • \(self.network.activeTransport.rawValue)"
                        : self.network.activeTransport.rawValue,
                    systemImage: self.network.route.isVPNActive ? "lock.shield.fill" : "waveform"
                )
                .font(.caption.bold())
                .foregroundStyle(self.network.route.isVPNActive ? .orange : .secondary)
                .lineLimit(1)
            }

            if self.network.isMultiProtocolActive {
                HStack(spacing: 10) {
                    self.protocolInlinePill(
                        name: "ICMP",
                        pingMs: self.network.icmpPingMs,
                        isLost: self.network.isICMPLastLost
                    )
                    Text("|").font(.caption2).foregroundStyle(.tertiary)
                    self.protocolInlinePill(
                        name: "UDP",
                        pingMs: self.network.udpPingMs,
                        isLost: self.network.isUDPLastLost
                    )
                    Text("|").font(.caption2).foregroundStyle(.tertiary)
                    self.protocolInlinePill(
                        name: "TCP",
                        pingMs: self.network.tcpPingMs,
                        isLost: self.network.isTCPLastLost
                    )
                    Spacer()
                }
                .font(.caption)
                .monospacedDigit()
            }

            // Ping, Jitter & 1s Probe State
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ping / RTT")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if self.network.isLastProbeLost {
                        Text(L10n.tr("LOST"))
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                    } else if let ping = self.network.pingMs {
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(String(format: "%.0f", ping))
                                .font(.title2.bold())
                                .monospacedDigit()
                                .foregroundStyle(TelemetryTheme.pingColor(ping))
                            Text("ms")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("-- ms")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jitter (RFC)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "±%.1f", self.network.jitterMs))
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(self.network.jitterMs > 15 ? .orange : .green)
                        Text("ms")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.tr("1s Probe"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Label(
                        self.network.isLastProbeLost ? "DROP" : L10n.tr("Stable"),
                        systemImage: self.network.isLastProbeLost ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.footnote.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (self.network.isLastProbeLost ? Color.red : Color.green).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(self.network.isLastProbeLost ? .red : .green)
                }
            }

            Divider()

            // Rolling 60s / 120s & Cumulative Session Loss
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("Loss (60s)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(self.network.lostCount60s)/60 pkts")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(self.network.lostCount60s > 0 ? .orange : .primary)
                    Text(String(format: "%.1f%%", self.network.lossPercent60s))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(self.network.lostCount60s > 0 ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("Loss (120s)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(self.network.lostCount120s)/120 pkts")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(self.network.lostCount120s > 0 ? .orange : .primary)
                    Text(String(format: "%.1f%%", self.network.lossPercent120s))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(self.network.lostCount120s > 0 ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.tr("Total Session"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%% (%dp)", self.network.totalLossPercent, self.network.totalLostCount))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(
                            TelemetryTheme.lossColor(
                                isLostNow: self.network.isLastProbeLost,
                                lossPercent: self.network.totalLossPercent
                            )
                        )
                    Text(L10n.fmt("%lld probes", self.network.totalProbes))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let seconds = self.network.secondsSinceLastLoss {
                HStack(spacing: 6) {
                    Label(L10n.fmt("Last loss %.0fs ago", seconds), systemImage: "timer")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let cycle = self.network.detectedCycleSeconds {
                        Label(L10n.fmt("Cycle: ~%.0fs", cycle), systemImage: "waveform.path.ecg")
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            // Throughput & Reset
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Download")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(self.network.downloadFormatted)
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Upload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(self.network.uploadFormatted)
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                }

                Spacer()

                Button {
                    self.showResetConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(
                            minWidth: TelemetryTheme.minTouchTarget,
                            minHeight: TelemetryTheme.minTouchTarget
                        )
                }
                .accessibilityLabel(L10n.tr("Reset session packet loss counters"))
                .sensoryFeedback(.warning, trigger: self.resetTrigger)
            }

            NavigationLink(value: NavigationDestination.networkDiagnostics) {
                HStack {
                    Label(L10n.tr("Open Chronological Log & Chart"), systemImage: "chart.xyaxis.line")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }
        }
        .padding(TelemetryTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                        .strokeBorder(self.borderHighlight, lineWidth: 1)
                )
        )
        .sheet(isPresented: self.$showTargetConfig) {
            NetworkTargetSheetView(
                currentTarget: self.network.target,
                detectedGatewayIP: self.network.route.detectedGatewayIP,
                initialCustomGateway: self.network.isGatewayCustom ? self.network.gatewayHost : nil,
                isGatewayCustomInitial: self.network.isGatewayCustom,
                currentProtocol: self.network.protocolPreference
            ) {}
        }
        .alert(L10n.tr("Reset network history?"), isPresented: self.$showResetConfirmation) {
            Button(L10n.tr("Reset All"), role: .destructive) {
                self.resetTrigger += 1
                Task {
                    await SwiftSensors.shared.resetNetworkStats()
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("This will clear the chart samples (up to 1h), the incident log, and the current session packet loss counters."))
        }
    }

    private func protocolInlinePill(name: String, pingMs: Double?, isLost: Bool) -> some View {
        let value: String = {
            if isLost { return "DROP" }
            if let pingMs { return String(format: "%.0fms", pingMs) }
            return "--"
        }()

        return HStack(spacing: 3) {
            Text(name)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(isLost ? .red : TelemetryTheme.pingColor(pingMs, isLost: false))
        }
    }

    private var gatewayCompactText: String {
        guard let host = self.network.gatewayHost else {
            return L10n.tr("Router: --")
        }
        if self.network.isGatewayLastProbeLost {
            return L10n.fmt("Router (%@): DROP", host)
        }
        if let gwMs = self.network.gatewayPingMs {
            return L10n.fmt("Router: %.1f ms", gwMs)
        }
        return L10n.fmt("Router: %@", host)
    }
}
