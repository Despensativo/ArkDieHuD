import SwiftUI
import UIKit

/// Interactive instrument control card that previews and launches the floating
/// Picture-in-Picture (PiP) telemetry overlay or opens the Slide Over drawer.
struct HUDDashboardSection: View {
    @Bindable var hudController: PiPHUDController
    @State private var showCustomizationSheet: Bool = false
    @State private var showMetalHUDOpacityGuide: Bool = false
    @State private var copiedURLTrigger: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.tr("Floating HUD (PiP)"), systemImage: "pip.enter")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Label(
                    self.hudController.isPiPActive ? L10n.tr("Active") : L10n.tr("Ready"),
                    systemImage: self.hudController.isPiPActive ? "record.circle" : "circle.dashed"
                )
                .font(.footnote.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (self.hudController.isPiPActive ? Color.green : Color.accentColor).opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(self.hudController.isPiPActive ? .green : Color.accentColor)
            }

            // Live inline preview of the exact PiP overlay canvas
            PiPPreviewView(hudController: self.hudController)
                .aspectRatio(self.hudController.currentCanvasAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )

            self.layoutModeRow

            Button {
                self.showCustomizationSheet = true
            } label: {
                HStack {
                    Label(
                        L10n.fmt("Customize Metrics (%lld/12)", self.hudController.visibilityConfig.enabledMetricCount),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    self.primaryPiPButton
                    self.slideOverButton
                }
                VStack(spacing: 10) {
                    self.primaryPiPButton
                    self.slideOverButton
                }
            }

            Toggle(L10n.tr("Auto-start when leaving the app"), isOn: self.$hudController.autoStartOnBackground)
                .font(.subheadline)

            Toggle(L10n.tr("Record telemetry logs (24h)"), isOn: self.$hudController.isRecordingLogs)
                .font(.subheadline)

            Toggle(L10n.tr("Monitor on PC/Mac (no screen PiP)"), isOn: self.$hudController.isRemoteWebServerEnabled)
                .font(.subheadline)

            if self.hudController.isRemoteWebServerEnabled {
                self.remoteMonitorCard
            }

            Text(self.hudController.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        .sheet(isPresented: self.$showCustomizationSheet) {
            TelemetryCustomizationSheetView(hudController: self.hudController)
        }
    }

    private var layoutModeRow: some View {
        HStack(spacing: 10) {
            Text(L10n.tr("HUD Layout"))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Menu {
                ForEach(HUDLayoutMode.allCases) { mode in
                    Button {
                        self.hudController.layoutMode = mode
                    } label: {
                        if self.hudController.layoutMode == mode {
                            Label(mode.localizedTitle, systemImage: "checkmark")
                        } else {
                            Text(mode.localizedTitle)
                        }
                    }
                }
            } label: {
                self.layoutMenuLabel
            }
            .accessibilityLabel(L10n.tr("HUD Mode"))
            .accessibilityValue(self.hudController.layoutMode.localizedTitle)
        }
    }

    private var layoutMenuLabel: some View {
        HStack(spacing: 5) {
            Text(self.hudController.layoutMode.localizedTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.bold())
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.accentColor)
    }

    private var remoteMonitorCard: some View {
        let route = self.hudController.latestSnapshot.network.route
        let ipv4URL = route.localIPv4.map { "http://\($0):\(TelemetryWebServer.defaultPort)" }
        let ipv6URL = route.localIPv6.map { "http://[\($0)]:\(TelemetryWebServer.defaultPort)" }
        let primaryURL = ipv4URL ?? (self.hudController.allowIPv6WebServer ? ipv6URL : nil)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.tr("Live Web Dashboard"), systemImage: "desktopcomputer")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if let primaryURL {
                    Button {
                        UIPasteboard.general.string = primaryURL
                        self.copiedURLTrigger += 1
                    } label: {
                        Label(L10n.tr("Copy URL"), systemImage: "doc.on.doc")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .sensoryFeedback(.success, trigger: self.copiedURLTrigger)
                }
            }

            Text(primaryURL ?? L10n.fmt("Connect to Wi-Fi or USB Ethernet to view IP (or use USB tunnel on port %lld)", TelemetryWebServer.defaultPort))
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let iface = route.activeInterfaceName {
                HStack(spacing: 6) {
                    Image(systemName: route.interfaceKind == "Ethernet" ? "cable.connector" : "wifi")
                        .font(.caption)
                    Text(
                        route.interfaceKind == "Ethernet"
                            ? L10n.fmt("USB Ethernet active (%@)", iface)
                            : L10n.fmt("Interface: %@ (%@)", route.interfaceKind, iface)
                    )
                }
                .font(.caption)
                .foregroundStyle(route.interfaceKind == "Ethernet" ? .green : .secondary)
            }

            if !self.hudController.allowUSBEthernetNetwork, let usbIP = route.usbEthernetIPv4 {
                Text(L10n.fmt("USB Ethernet detected (%@) — disabled below", usbIP))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }

            Toggle(L10n.tr("Use USB Ethernet adapter (LAN)"), isOn: self.$hudController.allowUSBEthernetNetwork)
                .font(.footnote)

            Toggle(L10n.tr("Allow IPv6 on Web Dashboard"), isOn: self.$hudController.allowIPv6WebServer)
                .font(.footnote)

            if self.hudController.allowIPv6WebServer {
                Label(
                    L10n.tr("Warning: public IPv6 may expose :8787 outside your LAN depending on your router firewall."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)

                if let ipv6URL {
                    HStack(spacing: 8) {
                        Text(ipv6URL)
                            .font(.caption.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = ipv6URL
                            self.copiedURLTrigger += 1
                        } label: {
                            Label(L10n.tr("Copy IPv6"), systemImage: "doc.on.doc")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else {
                    Text(L10n.tr("No routable IPv6 address detected on the active network."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    L10n.tr("Safe default: IPv4 / local USB only (IPv6 port disabled)."),
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle(L10n.tr("Stealth PiP (hide at screen edge)"), isOn: self.$hudController.useStealthPiPForPC)
                .font(.footnote)

            Text(L10n.tr("If using in-game voice mic, open Stealth PiP and drag it off the side edge — the screen stays clean while the PC monitor remains active."))
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup(
                L10n.tr("Step-by-step: Developer Mode, mini HUD & opacity"),
                isExpanded: self.$showMetalHUDOpacityGuide
            ) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("1. Prerequisite: enable Settings -> Privacy & Security -> Developer Mode (required). Then open Settings -> Developer -> Metal HUD (keep Show Metal Performance HUD OFF)."))
                    Text(L10n.tr("2. Keep mini when switching apps: drag Scale to minimum, enable only FPS under Metrics, and turn ON Log Metal Performance."))
                    Text(L10n.tr("3. Opacity: keep 100% to see mini FPS on screen, or drag to 0% + choose Invisible (Web Only) on :8787 to hide on screen while FPS stays live on PC."))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .font(.caption.weight(.semibold))
            .tint(Color.accentColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1)
                )
        )
    }

    private var primaryPiPButton: some View {
        Button {
            if self.hudController.isPiPActive {
                self.hudController.stopPiP()
            } else {
                self.hudController.prepareAudioAndStartPiP()
            }
        } label: {
            Label(
                self.hudController.isPiPActive ? L10n.tr("Close Floating HUD") : L10n.tr("Overlay on Screen (PiP)"),
                systemImage: self.hudController.isPiPActive ? "pip.exit" : "pip.enter"
            )
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: TelemetryTheme.minTouchTarget - 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(self.hudController.isPiPActive ? .red : .accentColor)
        .disabled(!self.hudController.isSupported)
        .sensoryFeedback(.impact(weight: .medium), trigger: self.hudController.isPiPActive)
    }

    private var slideOverButton: some View {
        NavigationLink(value: NavigationDestination.slideOver) {
            Label(L10n.tr("Slide Over Mode"), systemImage: "sidebar.right")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: TelemetryTheme.minTouchTarget - 12)
        }
        .buttonStyle(.bordered)
    }
}
