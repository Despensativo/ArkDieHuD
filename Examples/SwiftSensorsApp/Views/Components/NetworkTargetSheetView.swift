import SwiftSensors
import SwiftUI

/// Configuration sheet for selecting reference or custom external targets,
/// customizing local gateway router IP, and choosing ICMP/TCP probe mode.
struct NetworkTargetSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let currentTarget: NetworkProbeTarget
    let detectedGatewayIP: String?
    let initialCustomGateway: String?
    let isGatewayCustomInitial: Bool
    let currentProtocol: NetworkProbeProtocol
    let onApplied: () -> Void

    @State private var useCustomTarget: Bool = false
    @State private var selectedPreset: NetworkProbeTarget = .cloudflare
    @State private var customName: String = ""
    @State private var customHost: String = ""
    @State private var customPortText: String = "443"

    @State private var autoDetectGateway: Bool = true
    @State private var customGatewayText: String = ""
    @State private var selectedProtocol: NetworkProbeProtocol = .auto
    @State private var useIPv6Probes: Bool = false
    @State private var saveTrigger: Int = 0

    private var availablePresets: [NetworkProbeTarget] {
        self.useIPv6Probes ? NetworkProbeTarget.ipv6AwareTargets : NetworkProbeTarget.defaultTargets
    }

    private var parsedCustomPort: UInt16? {
        guard let value = UInt16(self.customPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 1 else {
            return nil
        }
        return value
    }

    private var isFormValid: Bool {
        if self.useCustomTarget {
            let trimmedHost = self.customHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHost.isEmpty || self.parsedCustomPort == nil {
                return false
            }
        }
        if !self.autoDetectGateway {
            if self.customGatewayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L10n.tr("Reference External Server"))) {
                    Toggle(L10n.tr("Use custom server"), isOn: self.$useCustomTarget)

                    if !self.useCustomTarget {
                        ForEach(self.availablePresets) { preset in
                            Button {
                                self.selectedPreset = preset
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                            .foregroundStyle(.primary)
                                        Text("\(preset.host):\(preset.port)")
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if self.selectedPreset.id == preset.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    } else {
                        LabeledContent(L10n.tr("Name")) {
                            TextField(L10n.tr("e.g., Game Server"), text: self.$customName)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }

                        LabeledContent(L10n.tr("IP or Hostname")) {
                            TextField(L10n.tr("e.g., 1.1.1.1 or game.server.com"), text: self.$customHost)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }

                        LabeledContent(L10n.tr("TCP / DNS Port")) {
                            TextField("443", text: self.$customPortText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .monospacedDigit()
                        }
                    }
                }

                Section(
                    header: Text(L10n.tr("Local Router (Dual Probe)")),
                    footer: Text(L10n.tr("Simultaneous probe to isolate Wi-Fi/router drops from external ISP drops."))
                ) {
                    Toggle(L10n.tr("Auto-detect router"), isOn: self.$autoDetectGateway)

                    if self.autoDetectGateway {
                        LabeledContent(L10n.tr("Detected Gateway")) {
                            Text(self.detectedGatewayIP ?? L10n.tr("Unavailable"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent(L10n.tr("Router IP")) {
                            TextField(L10n.tr("e.g., 192.168.1.1"), text: self.$customGatewayText)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                                .monospacedDigit()
                        }
                    }
                }

                Section(
                    header: Text(L10n.tr("IP Protocol Version")),
                    footer: Text(L10n.tr("Disabled by default for security and local IPv4 consistency. Turn on to allow IPv6 DNS resolution and ICMPv6/UDP/TCP probes."))
                ) {
                    Toggle(L10n.tr("Use IPv6 in Network Probes"), isOn: self.$useIPv6Probes)
                        .onChange(of: self.useIPv6Probes) { _, enabled in
                            if !enabled && self.selectedPreset.host.contains(":") {
                                self.selectedPreset = .cloudflare
                            }
                        }
                }

                Section(
                    header: Text(L10n.tr("Probe Protocol")),
                    footer: Text(L10n.tr("Simultaneous tests ICMP, UDP (DNS 53), and TCP alongside the router (~0.6 KB/s). If a custom target does not use port 53, the UDP probe falls back to 1.1.1.1:53."))
                ) {
                    Picker(L10n.tr("Probe Mode"), selection: self.$selectedProtocol) {
                        ForEach(NetworkProbeProtocol.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(L10n.tr("Configure Network"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel")) {
                        self.dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Apply")) {
                        self.applyConfiguration()
                    }
                    .disabled(!self.isFormValid)
                    .sensoryFeedback(.success, trigger: self.saveTrigger)
                }
            }
            .onAppear {
                self.loadInitialState()
            }
            .task {
                self.useIPv6Probes = await SwiftSensors.shared.getNetworkUseIPv6Probes()
            }
        }
    }

    private func loadInitialState() {
        self.selectedProtocol = self.currentProtocol
        if self.currentTarget.isCustom {
            self.useCustomTarget = true
            self.customName = self.currentTarget.name
            self.customHost = self.currentTarget.host
            self.customPortText = "\(self.currentTarget.port)"
        } else {
            self.useCustomTarget = false
            self.selectedPreset = self.currentTarget
        }

        self.autoDetectGateway = !self.isGatewayCustomInitial
        self.customGatewayText = self.initialCustomGateway ?? self.detectedGatewayIP ?? ""
    }

    private func applyConfiguration() {
        let finalTarget: NetworkProbeTarget
        if self.useCustomTarget {
            finalTarget = NetworkProbeTarget.custom(
                name: self.customName,
                host: self.customHost,
                port: self.parsedCustomPort ?? 443
            )
        } else {
            finalTarget = self.selectedPreset
        }

        let gatewayOverride: String? = self.autoDetectGateway
            ? nil
            : self.customGatewayText.trimmingCharacters(in: .whitespacesAndNewlines)

        let proto = self.selectedProtocol
        let allowIPv6 = self.useIPv6Probes
        self.saveTrigger += 1

        Task {
            await SwiftSensors.shared.setNetworkUseIPv6Probes(allowIPv6)
            await SwiftSensors.shared.setNetworkProbeProtocol(proto)
            await SwiftSensors.shared.setNetworkGatewayHost(gatewayOverride)
            await SwiftSensors.shared.setNetworkProbeTarget(finalTarget)
            await MainActor.run {
                self.onApplied()
                self.dismiss()
            }
        }
    }
}
