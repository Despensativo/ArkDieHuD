import Foundation
import Network
import os

/// Thread-safe wrapper around NWPathMonitor forwarding interface transitions into NetworkQualityMonitor.
private final class NetworkPathObserver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.swiftsensors.network.path", qos: .utility)

    func start(onUpdate: @escaping @Sendable (String, Set<String>, Set<String>) -> Void) {
        self.monitor.pathUpdateHandler = { path in
            let kind: String
            if path.status != .satisfied {
                kind = "Desconectado"
            } else if path.usesInterfaceType(.wiredEthernet) {
                kind = "Ethernet"
            } else if path.usesInterfaceType(.wifi) {
                kind = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                kind = "Celular"
            } else {
                kind = "Outra Rede"
            }
            let wiredNames = Set(
                path.availableInterfaces
                    .filter { $0.type == .wiredEthernet }
                    .map(\.name)
            )
            let wifiNames = Set(
                path.availableInterfaces
                    .filter { $0.type == .wifi }
                    .map(\.name)
            )
            onUpdate(kind, wiredNames, wifiNames)
        }
        self.monitor.start(queue: self.queue)
    }

    func stop() {
        self.monitor.cancel()
    }
}

/// Actor monitoring real-time network latency, jitter, packet loss (dual probe: local gateway vs target),
/// simultaneous multi-protocol probing (ICMP + UDP + TCP), percentiles (P50/P95/P99), active VPN/route state,
/// and 1-hour chronological incident logging.
public actor NetworkQualityMonitor {
    public static let shared = NetworkQualityMonitor()

    private static let maxHistorySeconds: TimeInterval = 3600
    private static let maxHistorySamples: Int = 3600
    private static let maxIncidents: Int = 1000

    private enum DefaultsKey {
        static let targetJSON = "SwiftSensors.net.target.json"
        static let customGateway = "SwiftSensors.net.customGateway"
        static let probeProtocol = "SwiftSensors.net.protocol"
        static let useUSBEthernet = "SwiftSensors.net.useUSBEthernet.v1"
        static let useIPv6Probes = "SwiftSensors.net.useIPv6Probes.v1"
    }

    private struct ProtocolTrackState {
        var totalProbes: Int = 0
        var totalLost: Int = 0
        var hasSucceededOnce: Bool = false
        var consecutiveLosses: Int = 0

        var lossPercent: Double {
            self.totalProbes > 0 ? (Double(self.totalLost) / Double(self.totalProbes)) * 100.0 : 0.0
        }

        mutating func reset() {
            self = ProtocolTrackState()
        }
    }

    private struct ExternalProbeOutcome {
        let primaryRTTMs: Double?
        let isPrimaryLost: Bool
        let transportUsed: NetworkProbeTransportUsed
        let icmpRTTMs: Double?
        let udpRTTMs: Double?
        let tcpRTTMs: Double?
        let probedICMP: Bool
        let probedUDP: Bool
        let probedTCP: Bool
    }

    private var currentTarget: NetworkProbeTarget
    private var customGatewayHost: String?
    private var protocolPreference: NetworkProbeProtocol
    private var useUSBEthernet: Bool
    private var useIPv6Probes: Bool
    private var activeTransport: NetworkProbeTransportUsed = .multi

    private var isRunning: Bool = false
    private var probeTask: Task<Void, Never>?
    private let pathObserver = NetworkPathObserver()

    // Fallback tracking for .auto protocol (switches to TCP only after repeated ICMP block)
    private var consecutiveICMPFailures: Int = 0
    private var autoFallbackToTCP: Bool = false
    private var gatewayICMPFailures: Int = 0
    private var gatewayUseTCPFallback: Bool = false

    // Rolling histories (1 hour of 1Hz dual-probe samples, up to 1000 incidents)
    private var historySamples: [NetworkProbeSample] = []
    private var incidents: [NetworkIncidentEvent] = []
    private var sequenceNumber: Int = 0
    private var sessionStartedAt: Date = Date()

    // Session cumulative counters (external target & local gateway)
    private var sessionTotalProbes: Int = 0
    private var sessionTotalLost: Int = 0
    private var gatewayTotalProbes: Int = 0
    private var gatewayTotalLost: Int = 0
    private var ispOnlyDropCount: Int = 0
    private var localAndExternalDropCount: Int = 0

    // Per-protocol trackers (ICMP, UDP DNS, TCP)
    private var icmpTrack = ProtocolTrackState()
    private var udpTrack = ProtocolTrackState()
    private var tcpTrack = ProtocolTrackState()
    private var cachedP50Ms: Double?
    private var cachedP95Ms: Double?
    private var cachedP99Ms: Double?

    // Burst, Spike & Jitter state
    private var currentBurstLoss: Int = 0
    private var maxBurstLoss: Int = 0
    private var spikeCount: Int = 0
    private var lastSpikeDate: Date = .distantPast
    private var currentJitterMs: Double = 0.0
    private var lastValidRTT: Double?

    // Cyclic loss tracking (e.g. recurring ~93s ISP drops)
    private var lossTimestamps: [Date] = []
    private var lastLossDate: Date?
    private var detectedCycleInterval: Double?

    // Route & VPN state
    private var pathInterfaceKind: String = "Wi-Fi"
    private var wiredInterfaceNames: Set<String> = []
    private var wifiInterfaceNames: Set<String> = []
    private var lastRouteInfo: NetworkRouteInfo = .unknown
    private var hasInitializedRoute: Bool = false

    // Interface throughput tracking (bytes from getifaddrs)
    private var lastThroughputTimestamp: Date?
    private var lastTotalInBytes: UInt64 = 0
    private var lastTotalOutBytes: UInt64 = 0
    private var sessionDownloadBytes: UInt64 = 0
    private var sessionUploadBytes: UInt64 = 0
    private var currentDownloadBps: Double = 0.0
    private var currentUploadBps: Double = 0.0

    private init() {
        self.currentTarget = Self.loadSavedTarget() ?? .cloudflare
        self.customGatewayHost = Self.loadSavedCustomGateway()
        self.protocolPreference = Self.loadSavedProtocol()
        self.useUSBEthernet = Self.loadSavedBool(DefaultsKey.useUSBEthernet, defaultValue: true)
        self.useIPv6Probes = Self.loadSavedBool(DefaultsKey.useIPv6Probes, defaultValue: false)

        Task { [self] in
            await self.start()
        }
    }

    // MARK: - Public Configuration & Query API

    public func setTarget(_ target: NetworkProbeTarget) {
        self.currentTarget = target
        Self.saveTarget(target)
        ICMPProber.clearDNSCache()
        self.resetTargetProbeState()
    }

    public func getTarget() -> NetworkProbeTarget {
        self.currentTarget
    }

    public func setCustomGatewayHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        self.customGatewayHost = normalized
        Self.saveCustomGateway(normalized)
        self.gatewayICMPFailures = 0
        self.gatewayUseTCPFallback = false
    }

    public func setProtocolPreference(_ proto: NetworkProbeProtocol) {
        self.protocolPreference = proto
        Self.saveProtocol(proto)
        self.consecutiveICMPFailures = 0
        self.autoFallbackToTCP = false
        self.gatewayICMPFailures = 0
        self.gatewayUseTCPFallback = false
        self.icmpTrack.consecutiveLosses = 0
        self.udpTrack.consecutiveLosses = 0
        self.tcpTrack.consecutiveLosses = 0
    }

    /// Ensures UDP probing is active when UDP metrics are enabled in the UI.
    public func ensureUDPProbingEnabled() {
        if self.protocolPreference != .simultaneous && self.protocolPreference != .udp {
            self.setProtocolPreference(.simultaneous)
        }
    }

    public func setUseUSBEthernet(_ enabled: Bool) {
        self.useUSBEthernet = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.useUSBEthernet)
    }

    public func getUseUSBEthernet() -> Bool {
        self.useUSBEthernet
    }

    public func setUseIPv6Probes(_ enabled: Bool) {
        self.useIPv6Probes = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.useIPv6Probes)
        ICMPProber.clearDNSCache()
        self.resetTargetProbeState()
    }

    public func getUseIPv6Probes() -> Bool {
        self.useIPv6Probes
    }

    public func start() {
        guard !self.isRunning else { return }
        self.isRunning = true

        let (initialIn, initialOut) = ICMPProber.readInterfaceBytes()
        self.lastTotalInBytes = initialIn
        self.lastTotalOutBytes = initialOut
        self.lastThroughputTimestamp = Date()

        self.pathObserver.start { [weak self] kind, wiredNames, wifiNames in
            Task { [weak self] in
                await self?.updatePathState(kind: kind, wiredInterfaces: wiredNames, wifiInterfaces: wifiNames)
            }
        }

        self.probeTask = Task { [weak self] in
            while !Task.isCancelled {
                let tickStartNs = DispatchTime.now().uptimeNanoseconds
                guard let self else { break }
                await self.tick()
                let elapsedNs = DispatchTime.now().uptimeNanoseconds &- tickStartNs
                let remainingNs = elapsedNs >= 1_000_000_000 ? 100_000_000 : (1_000_000_000 - elapsedNs)
                try? await Task.sleep(nanoseconds: max(100_000_000, remainingNs))
            }
        }
    }

    public func stop() {
        self.isRunning = false
        self.pathObserver.stop()
        self.probeTask?.cancel()
        self.probeTask = nil
    }

    public func resetStats() {
        self.historySamples.removeAll()
        self.incidents.removeAll()
        self.sequenceNumber = 0
        self.sessionStartedAt = Date()
        self.sessionTotalProbes = 0
        self.sessionTotalLost = 0
        self.gatewayTotalProbes = 0
        self.gatewayTotalLost = 0
        self.ispOnlyDropCount = 0
        self.localAndExternalDropCount = 0
        self.icmpTrack.reset()
        self.udpTrack.reset()
        self.tcpTrack.reset()
        self.cachedP50Ms = nil
        self.cachedP95Ms = nil
        self.cachedP99Ms = nil
        self.currentBurstLoss = 0
        self.maxBurstLoss = 0
        self.spikeCount = 0
        self.lastSpikeDate = .distantPast
        self.lossTimestamps.removeAll()
        self.lastLossDate = nil
        self.detectedCycleInterval = nil
        self.currentJitterMs = 0.0
        self.lastValidRTT = nil
        self.consecutiveICMPFailures = 0
        self.autoFallbackToTCP = false
        self.gatewayICMPFailures = 0
        self.gatewayUseTCPFallback = false
        self.sessionDownloadBytes = 0
        self.sessionUploadBytes = 0
        ICMPProber.clearDNSCache()
    }

    public func getHistorySamples(limit: Int = 3600) -> [NetworkProbeSample] {
        guard limit > 0, self.historySamples.count > limit else {
            return self.historySamples
        }
        return Array(self.historySamples.suffix(limit))
    }

    public func getIncidents() -> [NetworkIncidentEvent] {
        self.incidents
    }

    public func getCurrentMetrics() -> NetworkQualityMetrics {
        let now = Date()
        let cutoff60 = now.addingTimeInterval(-60)
        let cutoff120 = now.addingTimeInterval(-120)

        let recentSlice = self.historySamples.suffix(180)
        let valid60 = recentSlice.filter { $0.timestamp >= cutoff60 }
        let valid120 = recentSlice.filter { $0.timestamp >= cutoff120 }

        let lost60 = valid60.filter(\.isTargetLost).count
        let lossPct60 = valid60.isEmpty ? 0.0 : (Double(lost60) / Double(valid60.count)) * 100.0

        let lost120 = valid120.filter(\.isTargetLost).count
        let lossPct120 = valid120.isEmpty ? 0.0 : (Double(lost120) / Double(valid120.count)) * 100.0

        let totalLossPct = self.sessionTotalProbes > 0
            ? (Double(self.sessionTotalLost) / Double(self.sessionTotalProbes)) * 100.0
            : 0.0

        let gatewayLossPct = self.gatewayTotalProbes > 0
            ? (Double(self.gatewayTotalLost) / Double(self.gatewayTotalProbes)) * 100.0
            : 0.0

        let lastSample = self.historySamples.last
        let secSinceLoss = self.lastLossDate.map { max(0, now.timeIntervalSince($0)) }
        let cycleDesc = self.detectedCycleInterval.map { String(format: "Ciclo: ~%.0fs", $0) }
        let activeGateway = self.customGatewayHost ?? self.lastRouteInfo.detectedGatewayIP

        return NetworkQualityMetrics(
            target: self.currentTarget,
            pingMs: lastSample?.targetRTTMs,
            jitterMs: self.currentJitterMs,
            downloadBytesPerSec: self.currentDownloadBps,
            uploadBytesPerSec: self.currentUploadBps,
            isLastProbeLost: lastSample?.isTargetLost ?? false,
            lostCount60s: lost60,
            lossPercent60s: lossPct60,
            lostCount120s: lost120,
            lossPercent120s: lossPct120,
            totalProbes: self.sessionTotalProbes,
            totalLostCount: self.sessionTotalLost,
            totalLossPercent: totalLossPct,
            secondsSinceLastLoss: secSinceLoss,
            detectedCycleSeconds: self.detectedCycleInterval,
            cycleDescription: cycleDesc,
            protocolPreference: self.protocolPreference,
            activeTransport: self.activeTransport,
            gatewayHost: activeGateway,
            isGatewayCustom: self.customGatewayHost != nil,
            gatewayPingMs: lastSample?.gatewayRTTMs,
            isGatewayLastProbeLost: lastSample?.isGatewayLost ?? false,
            gatewayTotalLostCount: self.gatewayTotalLost,
            gatewayTotalLossPercent: gatewayLossPct,
            ispOnlyDropCount: self.ispOnlyDropCount,
            localAndExternalDropCount: self.localAndExternalDropCount,
            p50Ms: self.cachedP50Ms,
            p95Ms: self.cachedP95Ms,
            p99Ms: self.cachedP99Ms,
            maxBurstLoss: self.maxBurstLoss,
            currentBurstLoss: self.currentBurstLoss,
            spikeCount: self.spikeCount,
            route: self.lastRouteInfo,
            sessionStartedAt: self.sessionStartedAt,
            isMultiProtocolActive: self.protocolPreference == .simultaneous,
            icmpPingMs: lastSample?.icmpRTTMs,
            isICMPLastLost: lastSample?.isICMPLost ?? false,
            icmpLostCount: self.icmpTrack.totalLost,
            icmpLossPercent: self.icmpTrack.lossPercent,
            udpPingMs: lastSample?.udpRTTMs,
            isUDPLastLost: lastSample?.isUDPLost ?? false,
            udpLostCount: self.udpTrack.totalLost,
            udpLossPercent: self.udpTrack.lossPercent,
            udpProbeHost: self.resolvedUDPTargetHost(),
            tcpPingMs: lastSample?.tcpRTTMs,
            isTCPLastLost: lastSample?.isTCPLost ?? false,
            tcpLostCount: self.tcpTrack.totalLost,
            tcpLossPercent: self.tcpTrack.lossPercent,
            sessionDownloadBytes: self.sessionDownloadBytes,
            sessionUploadBytes: self.sessionUploadBytes
        )
    }

    public func exportDiagnosticsCSV() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metrics = self.getCurrentMetrics()
        let fmtRTT: (Double?, Bool) -> String = { rtt, lost in
            if let rtt { return String(format: "%.2f", rtt) }
            return lost ? "LOST" : ""
        }

        var lines: [String] = []
        lines.append("# SwiftSensors Network Diagnostics Report")
        lines.append("# GeneratedAt,\(iso.string(from: Date()))")
        lines.append("# Target,\(metrics.target.name) (\(metrics.target.host):\(metrics.target.port))")
        lines.append("# ProtocolMode,\(metrics.protocolPreference.rawValue)")
        lines.append("# UDPProbeHost,\(metrics.udpProbeHost):53")
        lines.append("# Gateway,\(metrics.gatewayHost ?? "N/A")")
        lines.append("# Route,\(metrics.route.summaryLabel)")
        lines.append("# TotalProbes,\(metrics.totalProbes),TargetLost,\(metrics.totalLostCount),TargetLossPct,\(String(format: "%.2f", metrics.totalLossPercent))")
        lines.append("# ICMPLost,\(metrics.icmpLostCount),ICMPPct,\(String(format: "%.2f", metrics.icmpLossPercent))")
        lines.append("# UDPLost,\(metrics.udpLostCount),UDPPct,\(String(format: "%.2f", metrics.udpLossPercent))")
        lines.append("# TCPLost,\(metrics.tcpLostCount),TCPPct,\(String(format: "%.2f", metrics.tcpLossPercent))")
        lines.append("# ISPOnlyDrops,\(metrics.ispOnlyDropCount),LocalAndExternalDrops,\(metrics.localAndExternalDropCount)")
        lines.append("# P50Ms,\(metrics.p50Ms.map { String(format: "%.2f", $0) } ?? "--"),P95Ms,\(metrics.p95Ms.map { String(format: "%.2f", $0) } ?? "--"),P99Ms,\(metrics.p99Ms.map { String(format: "%.2f", $0) } ?? "--")")
        lines.append("")
        lines.append("record_type,timestamp,sequence,kind,delta_sec,target_rtt_ms,gateway_rtt_ms,icmp_rtt_ms,udp_rtt_ms,tcp_rtt_ms,transport,route,details")

        for event in self.incidents.reversed() {
            let delta = event.deltaSincePreviousDropSeconds.map { String(format: "%.1f", $0) } ?? ""
            let tRTT = event.targetRTTMs.map { String(format: "%.2f", $0) } ?? ""
            let gRTT = event.gatewayRTTMs.map { String(format: "%.2f", $0) } ?? ""
            let safeDetails = event.details.replacingOccurrences(of: "\"", with: "'")
            lines.append("INCIDENT,\(iso.string(from: event.timestamp)),\(event.sequence),\(event.kind.rawValue),\(delta),\(tRTT),\(gRTT),,,,\(metrics.activeTransport.rawValue),\(event.routeLabel),\"\(safeDetails)\"")
        }

        for sample in self.historySamples {
            let tRTT = fmtRTT(sample.targetRTTMs, sample.isTargetLost)
            let gRTT = fmtRTT(sample.gatewayRTTMs, sample.isGatewayLost)
            let iRTT = fmtRTT(sample.icmpRTTMs, sample.isICMPLost)
            let uRTT = fmtRTT(sample.udpRTTMs, sample.isUDPLost)
            let cRTT = fmtRTT(sample.tcpRTTMs, sample.isTCPLost)
            let vpn = sample.isVPNActive ? "VPN" : "DIRECT"
            lines.append("SAMPLE,\(iso.string(from: sample.timestamp)),\(sample.sequence),probe,,\(tRTT),\(gRTT),\(iRTT),\(uRTT),\(cRTT),\(sample.transportUsed.rawValue),\(vpn),")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Core 1Hz Dual-Probe Engine

    private func tick() async {
        let now = Date()
        self.sequenceNumber += 1
        let seq16 = UInt16(truncatingIfNeeded: self.sequenceNumber)

        // 1. Update throughput & interface/VPN topology
        let (curIn, curOut) = ICMPProber.readInterfaceBytes()
        if let lastTime = self.lastThroughputTimestamp {
            let dt = max(0.1, now.timeIntervalSince(lastTime))
            let deltaIn = curIn >= self.lastTotalInBytes ? curIn - self.lastTotalInBytes : 0
            let deltaOut = curOut >= self.lastTotalOutBytes ? curOut - self.lastTotalOutBytes : 0
            self.sessionDownloadBytes &+= deltaIn
            self.sessionUploadBytes &+= deltaOut
            self.currentDownloadBps = Double(deltaIn) / dt
            self.currentUploadBps = Double(deltaOut) / dt
        }
        self.lastTotalInBytes = curIn
        self.lastTotalOutBytes = curOut
        self.lastThroughputTimestamp = now

        let netIf = ICMPProber.inspectLocalInterfaces(
            wiredInterfaceNames: self.wiredInterfaceNames,
            wifiInterfaceNames: self.wifiInterfaceNames,
            isWiredPath: self.pathInterfaceKind == "Ethernet",
            preferUSBEthernet: self.useUSBEthernet
        )
        let effectiveInterfaceKind: String
        if !self.useUSBEthernet,
           self.pathInterfaceKind == "Ethernet",
           let iface = netIf.activeInterfaceName,
           !self.wiredInterfaceNames.contains(iface) {
            effectiveInterfaceKind = "Wi-Fi"
        } else if self.useUSBEthernet,
                  netIf.usbEthernetIPv4 != nil,
                  netIf.activeInterfaceName != nil {
            effectiveInterfaceKind = "Ethernet"
        } else {
            effectiveInterfaceKind = self.pathInterfaceKind
        }
        let updatedRoute = NetworkRouteInfo(
            interfaceKind: effectiveInterfaceKind,
            isVPNActive: netIf.vpnInterface != nil,
            vpnInterfaceName: netIf.vpnInterface,
            localIPv4: netIf.localIPv4,
            detectedGatewayIP: netIf.detectedGatewayIP,
            activeInterfaceName: netIf.activeInterfaceName,
            usbEthernetIPv4: netIf.usbEthernetIPv4,
            localIPv6: netIf.localIPv6
        )
        self.recordRouteTransitionIfNeeded(updatedRoute, at: now)
        self.lastRouteInfo = updatedRoute

        let activeGateway = self.customGatewayHost ?? updatedRoute.detectedGatewayIP

        // 2. Simultaneous Probe: External Protocol(s) + Local Gateway Router
        async let targetProbeOutcome = self.probeExternalProtocols(sequence: seq16)
        async let gatewayProbeResult = self.probeGateway(host: activeGateway, sequence: seq16 &+ 0x4000)

        let outcome = await targetProbeOutcome
        let (gatewayRTT, didProbeGateway) = await gatewayProbeResult

        self.activeTransport = outcome.transportUsed
        let targetRTT = outcome.primaryRTTMs
        let isTargetLost = outcome.isPrimaryLost
        let isGatewayLost = didProbeGateway && (gatewayRTT == nil)
        let isICMPLost = outcome.probedICMP && outcome.icmpRTTMs == nil
        let isUDPLost = outcome.probedUDP && outcome.udpRTTMs == nil
        let isTCPLost = outcome.probedTCP && outcome.tcpRTTMs == nil

        self.sessionTotalProbes += 1
        if didProbeGateway {
            self.gatewayTotalProbes += 1
            if isGatewayLost {
                self.gatewayTotalLost += 1
            }
        }

        if isTargetLost {
            self.sessionTotalLost += 1
            self.currentBurstLoss += 1
            if self.currentBurstLoss > self.maxBurstLoss {
                self.maxBurstLoss = self.currentBurstLoss
            }

            let deltaPrev = self.lastLossDate.map { max(0, now.timeIntervalSince($0)) }
            self.recordLossEvent(at: now)

            let kind: NetworkIncidentKind
            let details: String
            if didProbeGateway {
                if isGatewayLost {
                    self.localAndExternalDropCount += 1
                    kind = .localDrop
                    details = self.protocolPreference == .simultaneous
                        ? "Roteador local (\(activeGateway ?? "")) e todos os protocolos sem resposta"
                        : "Roteador local (\(activeGateway ?? "")) e alvo externo sem resposta"
                } else {
                    self.ispOnlyDropCount += 1
                    kind = .ispDrop
                    let gwStr = gatewayRTT.map { String(format: "%.1f ms", $0) } ?? "OK"
                    details = self.protocolPreference == .simultaneous
                        ? "ICMP, UDP e TCP sem resposta (Roteador OK: \(gwStr))"
                        : "Roteador OK (\(gwStr)); falha na rota externa (\(self.currentTarget.host))"
                }
            } else {
                kind = .drop
                details = "Sem resposta de \(self.currentTarget.host)"
            }

            self.appendIncident(NetworkIncidentEvent(
                timestamp: now,
                kind: kind,
                sequence: self.sequenceNumber,
                deltaSincePreviousDropSeconds: deltaPrev,
                targetRTTMs: nil,
                gatewayRTTMs: gatewayRTT,
                routeLabel: updatedRoute.summaryLabel,
                details: details
            ))
        } else if let validMs = targetRTT {
            if self.currentBurstLoss >= 2 {
                self.appendIncident(NetworkIncidentEvent(
                    timestamp: now,
                    kind: .burst,
                    sequence: self.sequenceNumber,
                    targetRTTMs: validMs,
                    gatewayRTTMs: gatewayRTT,
                    burstCount: self.currentBurstLoss,
                    routeLabel: updatedRoute.summaryLabel,
                    details: "Rajada encerrada: \(self.currentBurstLoss) pacotes seguidos perdidos"
                ))
            }
            self.currentBurstLoss = 0

            // RFC 3550 jitter smoothing
            if let prev = self.lastValidRTT {
                let diff = abs(validMs - prev)
                self.currentJitterMs = self.currentJitterMs + (diff - self.currentJitterMs) / 16.0
            }
            self.lastValidRTT = validMs

            // Detect significant latency spikes relative to trailing 5-minute median
            let recentRTTs = self.historySamples.suffix(300).compactMap(\.targetRTTMs)
            if recentRTTs.count >= 10 {
                let p50 = Self.percentile(0.50, inSorted: recentRTTs.sorted())
                if validMs > max(55.0, p50 * 2.5) && (validMs - p50) > 25.0,
                   now.timeIntervalSince(self.lastSpikeDate) >= 5.0 {
                    self.lastSpikeDate = now
                    self.spikeCount += 1
                    self.appendIncident(NetworkIncidentEvent(
                        timestamp: now,
                        kind: .spike,
                        sequence: self.sequenceNumber,
                        targetRTTMs: validMs,
                        gatewayRTTMs: gatewayRTT,
                        routeLabel: updatedRoute.summaryLabel,
                        details: String(format: "Pico %.0f ms (P50 %.0f ms)", validMs, p50)
                    ))
                }
            }
        }

        // Track per-protocol reliability and emit anti-flood isolated protocol drop events
        let emitIsolatedDrop = (!isTargetLost && self.protocolPreference == .simultaneous)
        if outcome.probedICMP {
            self.updateProtocolTrack(
                &self.icmpTrack,
                label: "ICMP",
                host: self.currentTarget.host,
                isLost: isICMPLost,
                emitProtocolDrop: emitIsolatedDrop,
                now: now,
                gatewayRTT: gatewayRTT,
                routeLabel: updatedRoute.summaryLabel
            )
        }
        if outcome.probedUDP {
            self.updateProtocolTrack(
                &self.udpTrack,
                label: "UDP",
                host: self.resolvedUDPTargetHost(),
                isLost: isUDPLost,
                emitProtocolDrop: emitIsolatedDrop,
                now: now,
                gatewayRTT: gatewayRTT,
                routeLabel: updatedRoute.summaryLabel
            )
        }
        if outcome.probedTCP {
            self.updateProtocolTrack(
                &self.tcpTrack,
                label: "TCP",
                host: "\(self.currentTarget.host):\(self.currentTarget.port)",
                isLost: isTCPLost,
                emitProtocolDrop: emitIsolatedDrop,
                now: now,
                gatewayRTT: gatewayRTT,
                routeLabel: updatedRoute.summaryLabel
            )
        }

        let sample = NetworkProbeSample(
            sequence: self.sequenceNumber,
            timestamp: now,
            targetRTTMs: targetRTT,
            isTargetLost: isTargetLost,
            gatewayRTTMs: gatewayRTT,
            isGatewayLost: isGatewayLost,
            transportUsed: outcome.transportUsed,
            isVPNActive: updatedRoute.isVPNActive,
            icmpRTTMs: outcome.icmpRTTMs,
            udpRTTMs: outcome.udpRTTMs,
            tcpRTTMs: outcome.tcpRTTMs,
            isICMPLost: isICMPLost,
            isUDPLost: isUDPLost,
            isTCPLost: isTCPLost
        )
        self.historySamples.append(sample)

        // Retain 1 hour (up to 3600 samples)
        let oldestAllowed = now.addingTimeInterval(-Self.maxHistorySeconds)
        if self.historySamples.count > Self.maxHistorySamples
            || (self.historySamples.first?.timestamp ?? now) < oldestAllowed {
            self.historySamples.removeAll { $0.timestamp < oldestAllowed }
            if self.historySamples.count > Self.maxHistorySamples {
                self.historySamples.removeFirst(self.historySamples.count - Self.maxHistorySamples)
            }
        }

        let (p50, p95, p99) = self.computePercentiles()
        self.cachedP50Ms = p50
        self.cachedP95Ms = p95
        self.cachedP99Ms = p99
    }

    private func resolvedUDPTargetHost() -> String {
        if self.currentTarget.port == 53 {
            return self.currentTarget.host
        }
        if self.useIPv6Probes && self.currentTarget.host.contains(":") {
            return NetworkProbeTarget.cloudflareIPv6.host
        }
        return "1.1.1.1"
    }

    private func probeExternalProtocols(sequence: UInt16) async -> ExternalProbeOutcome {
        let udpHost = self.resolvedUDPTargetHost()
        let allowIPv6 = self.useIPv6Probes

        switch self.protocolPreference {
        case .simultaneous:
            async let icmpProbe = ICMPProber.pingICMP(
                host: self.currentTarget.host,
                sequence: sequence,
                timeout: 0.9,
                allowIPv6: allowIPv6
            )
            async let udpProbe = ICMPProber.pingUDPDNS(
                host: udpHost,
                port: 53,
                transactionID: sequence,
                timeout: 0.9,
                allowIPv6: allowIPv6
            )
            async let tcpProbe = ICMPProber.pingTCP(
                host: self.currentTarget.host,
                port: self.currentTarget.port,
                timeout: 0.9,
                allowIPv6: allowIPv6
            )

            let icmpRTT = await icmpProbe
            let udpRTT = await udpProbe
            let tcpRTT = await tcpProbe
            let primary = icmpRTT ?? udpRTT ?? tcpRTT

            return ExternalProbeOutcome(
                primaryRTTMs: primary,
                isPrimaryLost: primary == nil,
                transportUsed: .multi,
                icmpRTTMs: icmpRTT,
                udpRTTMs: udpRTT,
                tcpRTTMs: tcpRTT,
                probedICMP: true,
                probedUDP: true,
                probedTCP: true
            )

        case .icmp:
            let rtt = await ICMPProber.pingICMP(
                host: self.currentTarget.host,
                sequence: sequence,
                timeout: 1.0,
                allowIPv6: allowIPv6
            )
            return ExternalProbeOutcome(
                primaryRTTMs: rtt,
                isPrimaryLost: rtt == nil,
                transportUsed: .icmp,
                icmpRTTMs: rtt,
                udpRTTMs: nil,
                tcpRTTMs: nil,
                probedICMP: true,
                probedUDP: false,
                probedTCP: false
            )

        case .udp:
            let rtt = await ICMPProber.pingUDPDNS(
                host: udpHost,
                port: 53,
                transactionID: sequence,
                timeout: 1.0,
                allowIPv6: allowIPv6
            )
            return ExternalProbeOutcome(
                primaryRTTMs: rtt,
                isPrimaryLost: rtt == nil,
                transportUsed: .udp,
                icmpRTTMs: nil,
                udpRTTMs: rtt,
                tcpRTTMs: nil,
                probedICMP: false,
                probedUDP: true,
                probedTCP: false
            )

        case .tcp:
            let rtt = await ICMPProber.pingTCP(
                host: self.currentTarget.host,
                port: self.currentTarget.port,
                timeout: 1.0,
                allowIPv6: allowIPv6
            )
            return ExternalProbeOutcome(
                primaryRTTMs: rtt,
                isPrimaryLost: rtt == nil,
                transportUsed: .tcp,
                icmpRTTMs: nil,
                udpRTTMs: nil,
                tcpRTTMs: rtt,
                probedICMP: false,
                probedUDP: false,
                probedTCP: true
            )

        case .auto:
            if self.autoFallbackToTCP {
                let rtt = await ICMPProber.pingTCP(
                    host: self.currentTarget.host,
                    port: self.currentTarget.port,
                    timeout: 1.0,
                    allowIPv6: allowIPv6
                )
                return ExternalProbeOutcome(
                    primaryRTTMs: rtt,
                    isPrimaryLost: rtt == nil,
                    transportUsed: .tcp,
                    icmpRTTMs: nil,
                    udpRTTMs: nil,
                    tcpRTTMs: rtt,
                    probedICMP: false,
                    probedUDP: false,
                    probedTCP: true
                )
            }

            if let icmpRTT = await ICMPProber.pingICMP(
                host: self.currentTarget.host,
                sequence: sequence,
                timeout: 1.0,
                allowIPv6: allowIPv6
            ) {
                self.consecutiveICMPFailures = 0
                return ExternalProbeOutcome(
                    primaryRTTMs: icmpRTT,
                    isPrimaryLost: false,
                    transportUsed: .icmp,
                    icmpRTTMs: icmpRTT,
                    udpRTTMs: nil,
                    tcpRTTMs: nil,
                    probedICMP: true,
                    probedUDP: false,
                    probedTCP: false
                )
            }

            self.consecutiveICMPFailures += 1
            if self.consecutiveICMPFailures >= 3 {
                if let tcpRTT = await ICMPProber.pingTCP(
                    host: self.currentTarget.host,
                    port: self.currentTarget.port,
                    timeout: 0.9,
                    allowIPv6: allowIPv6
                ) {
                    self.autoFallbackToTCP = true
                    return ExternalProbeOutcome(
                        primaryRTTMs: tcpRTT,
                        isPrimaryLost: false,
                        transportUsed: .tcp,
                        icmpRTTMs: nil,
                        udpRTTMs: nil,
                        tcpRTTMs: tcpRTT,
                        probedICMP: false,
                        probedUDP: false,
                        probedTCP: true
                    )
                }
            }
            return ExternalProbeOutcome(
                primaryRTTMs: nil,
                isPrimaryLost: true,
                transportUsed: .icmp,
                icmpRTTMs: nil,
                udpRTTMs: nil,
                tcpRTTMs: nil,
                probedICMP: true,
                probedUDP: false,
                probedTCP: false
            )
        }
    }

    private func updateProtocolTrack(
        _ track: inout ProtocolTrackState,
        label: String,
        host: String,
        isLost: Bool,
        emitProtocolDrop: Bool,
        now: Date,
        gatewayRTT: Double?,
        routeLabel: String
    ) {
        track.totalProbes += 1
        if isLost {
            track.totalLost += 1
            track.consecutiveLosses += 1
            guard emitProtocolDrop else { return }

            let isBlockedNotice = (track.consecutiveLosses == 5)
            let shouldEmit = isBlockedNotice || ((track.hasSucceededOnce || track.consecutiveLosses <= 2) && track.consecutiveLosses <= 3)
            guard shouldEmit else { return }

            let details = isBlockedNotice
                ? "\(label) aparentemente bloqueado continuamente por \(host) (silenciado até recuperar)"
                : "\(label) perdeu resposta em \(host) enquanto outro protocolo seguiu ativo"

            self.appendIncident(NetworkIncidentEvent(
                timestamp: now,
                kind: .protocolDrop,
                sequence: self.sequenceNumber,
                targetRTTMs: nil,
                gatewayRTTMs: gatewayRTT,
                routeLabel: routeLabel,
                details: details
            ))
        } else {
            track.hasSucceededOnce = true
            track.consecutiveLosses = 0
        }
    }

    private func probeGateway(host: String?, sequence: UInt16) async -> (Double?, Bool) {
        guard let host, !host.isEmpty else {
            return (nil, false)
        }
        let allowIPv6 = self.useIPv6Probes

        if self.gatewayUseTCPFallback {
            let tcp = await ICMPProber.pingTCP(host: host, port: 80, timeout: 0.85, allowIPv6: allowIPv6)
            if tcp != nil {
                return (tcp, true)
            }
            let dnsFallback = await ICMPProber.pingTCP(host: host, port: 53, timeout: 0.5, allowIPv6: allowIPv6)
            return (dnsFallback, true)
        }

        if let icmp = await ICMPProber.pingICMP(host: host, sequence: sequence, timeout: 0.85, allowIPv6: allowIPv6) {
            self.gatewayICMPFailures = 0
            return (icmp, true)
        }

        self.gatewayICMPFailures += 1
        if self.gatewayICMPFailures >= 3 {
            if let tcp = await ICMPProber.pingTCP(host: host, port: 80, timeout: 0.5, allowIPv6: allowIPv6) {
                self.gatewayUseTCPFallback = true
                return (tcp, true)
            }
        }
        return (nil, true)
    }

    // MARK: - Helpers (Cycle Detection, Incidents, Percentiles, Route, Persistence)

    private func resetTargetProbeState() {
        self.historySamples.removeAll()
        self.lastValidRTT = nil
        self.currentJitterMs = 0.0
        self.consecutiveICMPFailures = 0
        self.autoFallbackToTCP = false
        self.currentBurstLoss = 0
        self.icmpTrack.reset()
        self.udpTrack.reset()
        self.tcpTrack.reset()
        self.cachedP50Ms = nil
        self.cachedP95Ms = nil
        self.cachedP99Ms = nil
    }

    private func updatePathState(kind: String, wiredInterfaces: Set<String>, wifiInterfaces: Set<String>) {
        self.pathInterfaceKind = kind
        self.wiredInterfaceNames = wiredInterfaces
        self.wifiInterfaceNames = wifiInterfaces
    }

    private func recordRouteTransitionIfNeeded(_ route: NetworkRouteInfo, at date: Date) {
        guard self.hasInitializedRoute else {
            self.hasInitializedRoute = true
            return
        }
        if route.interfaceKind != self.lastRouteInfo.interfaceKind || route.isVPNActive != self.lastRouteInfo.isVPNActive {
            self.appendIncident(NetworkIncidentEvent(
                timestamp: date,
                kind: .routeChange,
                sequence: self.sequenceNumber,
                routeLabel: route.summaryLabel,
                details: "Rota alterada: \(self.lastRouteInfo.summaryLabel) -> \(route.summaryLabel)"
            ))
        }
    }

    private func appendIncident(_ event: NetworkIncidentEvent) {
        self.incidents.append(event)
        if self.incidents.count > Self.maxIncidents {
            self.incidents.removeFirst(self.incidents.count - Self.maxIncidents)
        }
    }

    private func recordLossEvent(at date: Date) {
        self.lastLossDate = date
        if let lastRecorded = self.lossTimestamps.last, date.timeIntervalSince(lastRecorded) < 3.0 {
            return
        }
        self.lossTimestamps.append(date)
        if self.lossTimestamps.count > 10 {
            self.lossTimestamps.removeFirst()
        }

        if self.lossTimestamps.count >= 3 {
            var deltas: [Double] = []
            for i in 1..<self.lossTimestamps.count {
                let delta = self.lossTimestamps[i].timeIntervalSince(self.lossTimestamps[i - 1])
                if delta >= 15.0 && delta <= 300.0 {
                    deltas.append(delta)
                }
            }

            if deltas.count >= 2 {
                let avg = deltas.reduce(0.0, +) / Double(deltas.count)
                if deltas.allSatisfy({ abs($0 - avg) / avg < 0.20 }) {
                    self.detectedCycleInterval = avg
                }
            }
        }
    }

    private func computePercentiles() -> (Double?, Double?, Double?) {
        let validRTTs = self.historySamples.compactMap(\.targetRTTMs).sorted()
        guard !validRTTs.isEmpty else { return (nil, nil, nil) }
        return (
            Self.percentile(0.50, inSorted: validRTTs),
            Self.percentile(0.95, inSorted: validRTTs),
            Self.percentile(0.99, inSorted: validRTTs)
        )
    }

    private static func percentile(_ p: Double, inSorted sorted: [Double]) -> Double {
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }

    private static func saveTarget(_ target: NetworkProbeTarget) {
        if let data = try? JSONEncoder().encode(target) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.targetJSON)
        }
    }

    private static func loadSavedTarget() -> NetworkProbeTarget? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.targetJSON) else { return nil }
        return try? JSONDecoder().decode(NetworkProbeTarget.self, from: data)
    }

    private static func saveCustomGateway(_ host: String?) {
        if let host {
            UserDefaults.standard.set(host, forKey: DefaultsKey.customGateway)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.customGateway)
        }
    }

    private static func loadSavedCustomGateway() -> String? {
        UserDefaults.standard.string(forKey: DefaultsKey.customGateway)
    }

    private static func saveProtocol(_ proto: NetworkProbeProtocol) {
        UserDefaults.standard.set(proto.rawValue, forKey: DefaultsKey.probeProtocol)
    }

    private static func loadSavedProtocol() -> NetworkProbeProtocol {
        guard let raw = UserDefaults.standard.string(forKey: DefaultsKey.probeProtocol),
              let parsed = NetworkProbeProtocol(rawValue: raw) else {
            return .simultaneous
        }
        return parsed
    }

    private static func loadSavedBool(_ key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
