import Foundation

/// Preferred probing transport for latency and packet loss diagnostics.
public enum NetworkProbeProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case simultaneous = "Multi"
    case auto = "Auto"
    case icmp = "ICMP"
    case udp = "UDP"
    case tcp = "TCP"

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .simultaneous: return "Simultâneo (ICMP + UDP + TCP)"
        case .auto: return "Auto (ICMP -> TCP)"
        case .icmp: return "ICMP (Ping)"
        case .udp: return "UDP (DNS 53)"
        case .tcp: return "TCP (Handshake)"
        }
    }
}

/// Actual transport mechanism used by the latest probe tick.
public enum NetworkProbeTransportUsed: String, Codable, Sendable, Equatable {
    case icmp = "ICMP"
    case udp = "UDP"
    case tcp = "TCP"
    case multi = "MULTI"
    case none = "--"
}

/// Target server definition for latency, jitter, and packet loss probing.
public struct NetworkProbeTarget: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(self.host):\(self.port)" }
    public let name: String
    public let host: String
    public let port: UInt16
    public let isCustom: Bool

    public init(name: String, host: String, port: UInt16 = 443, isCustom: Bool = false) {
        self.name = name
        self.host = host
        self.port = port
        self.isCustom = isCustom
    }

    public static func custom(name: String, host: String, port: UInt16 = 443) -> NetworkProbeTarget {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkProbeTarget(
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            port: port,
            isCustom: true
        )
    }

    public static let cloudflare = NetworkProbeTarget(name: "Cloudflare (1.1.1.1)", host: "1.1.1.1", port: 53)
    public static let google = NetworkProbeTarget(name: "Google (8.8.8.8)", host: "8.8.8.8", port: 53)
    public static let awsSaoPaulo = NetworkProbeTarget(
        name: "AWS São Paulo",
        host: "ec2.sa-east-1.amazonaws.com",
        port: 443
    )
    public static let steam = NetworkProbeTarget(name: "Valve Steam", host: "store.steampowered.com", port: 443)
    public static let riot = NetworkProbeTarget(name: "Riot Games", host: "auth.riotgames.com", port: 443)

    public static let defaultTargets: [NetworkProbeTarget] = [
        .cloudflare,
        .google,
        .awsSaoPaulo,
        .steam,
        .riot,
    ]
}

/// Active iPadOS route summary combining primary interface, VPN tunnel, and gateway IP.
public struct NetworkRouteInfo: Codable, Sendable, Equatable {
    public let interfaceKind: String
    public let isVPNActive: Bool
    public let vpnInterfaceName: String?
    public let localIPv4: String?
    public let detectedGatewayIP: String?

    public init(
        interfaceKind: String,
        isVPNActive: Bool,
        vpnInterfaceName: String? = nil,
        localIPv4: String? = nil,
        detectedGatewayIP: String? = nil
    ) {
        self.interfaceKind = interfaceKind
        self.isVPNActive = isVPNActive
        self.vpnInterfaceName = vpnInterfaceName
        self.localIPv4 = localIPv4
        self.detectedGatewayIP = detectedGatewayIP
    }

    public static let unknown = NetworkRouteInfo(
        interfaceKind: "Wi-Fi",
        isVPNActive: false,
        vpnInterfaceName: nil,
        localIPv4: nil,
        detectedGatewayIP: nil
    )

    public var summaryLabel: String {
        if self.isVPNActive {
            if let vpn = self.vpnInterfaceName {
                return "\(self.interfaceKind) + VPN (\(vpn))"
            }
            return "\(self.interfaceKind) + VPN"
        }
        return "\(self.interfaceKind) Direto"
    }
}

/// Individual 1Hz dual-probe sample (external target vs local gateway router).
public struct NetworkProbeSample: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sequence: Int
    public let timestamp: Date
    public let targetRTTMs: Double?
    public let isTargetLost: Bool
    public let gatewayRTTMs: Double?
    public let isGatewayLost: Bool
    public let transportUsed: NetworkProbeTransportUsed
    public let isVPNActive: Bool
    public let icmpRTTMs: Double?
    public let udpRTTMs: Double?
    public let tcpRTTMs: Double?
    public let isICMPLost: Bool
    public let isUDPLost: Bool
    public let isTCPLost: Bool

    public init(
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date,
        targetRTTMs: Double?,
        isTargetLost: Bool,
        gatewayRTTMs: Double?,
        isGatewayLost: Bool,
        transportUsed: NetworkProbeTransportUsed,
        isVPNActive: Bool,
        icmpRTTMs: Double? = nil,
        udpRTTMs: Double? = nil,
        tcpRTTMs: Double? = nil,
        isICMPLost: Bool = false,
        isUDPLost: Bool = false,
        isTCPLost: Bool = false
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.targetRTTMs = targetRTTMs
        self.isTargetLost = isTargetLost
        self.gatewayRTTMs = gatewayRTTMs
        self.isGatewayLost = isGatewayLost
        self.transportUsed = transportUsed
        self.isVPNActive = isVPNActive
        self.icmpRTTMs = icmpRTTMs
        self.udpRTTMs = udpRTTMs
        self.tcpRTTMs = tcpRTTMs
        self.isICMPLost = isICMPLost
        self.isUDPLost = isUDPLost
        self.isTCPLost = isTCPLost
    }
}

/// Categorized network incident recorded automatically for timeline diagnostics.
public enum NetworkIncidentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case ispDrop = "Queda Externa / ISP"
    case localDrop = "Queda Local / Wi-Fi"
    case protocolDrop = "Queda de Protocolo"
    case drop = "Pacote Perdido"
    case burst = "Rajada de Perda"
    case spike = "Pico de Latência"
    case routeChange = "Troca de Rota / VPN"

    public var id: String { self.rawValue }
}

/// Chronological log event emitted whenever a drop, burst, spike, or route switch occurs.
public struct NetworkIncidentEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let kind: NetworkIncidentKind
    public let sequence: Int
    public let deltaSincePreviousDropSeconds: Double?
    public let targetRTTMs: Double?
    public let gatewayRTTMs: Double?
    public let burstCount: Int?
    public let routeLabel: String
    public let details: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: NetworkIncidentKind,
        sequence: Int,
        deltaSincePreviousDropSeconds: Double? = nil,
        targetRTTMs: Double? = nil,
        gatewayRTTMs: Double? = nil,
        burstCount: Int? = nil,
        routeLabel: String,
        details: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.sequence = sequence
        self.deltaSincePreviousDropSeconds = deltaSincePreviousDropSeconds
        self.targetRTTMs = targetRTTMs
        self.gatewayRTTMs = gatewayRTTMs
        self.burstCount = burstCount
        self.routeLabel = routeLabel
        self.details = details
    }
}

/// Comprehensive real-time network telemetry snapshot combining dual-probe SLA, percentiles, and route state.
public struct NetworkQualityMetrics: Codable, Sendable, Equatable {
    public let target: NetworkProbeTarget
    public let pingMs: Double?
    public let jitterMs: Double
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let isLastProbeLost: Bool

    // Window metrics
    public let lostCount60s: Int
    public let lossPercent60s: Double
    public let lostCount120s: Int
    public let lossPercent120s: Double

    // Cumulative session totals
    public let totalProbes: Int
    public let totalLostCount: Int
    public let totalLossPercent: Double

    // Periodic / Cyclic pattern detection (e.g. 93s ISP micro-drop)
    public let secondsSinceLastLoss: Double?
    public let detectedCycleSeconds: Double?
    public let cycleDescription: String?

    // Dual Probe (Local Gateway vs External Target), Transport, Percentiles & Route
    public let protocolPreference: NetworkProbeProtocol
    public let activeTransport: NetworkProbeTransportUsed
    public let gatewayHost: String?
    public let isGatewayCustom: Bool
    public let gatewayPingMs: Double?
    public let isGatewayLastProbeLost: Bool
    public let gatewayTotalLostCount: Int
    public let gatewayTotalLossPercent: Double
    public let ispOnlyDropCount: Int
    public let localAndExternalDropCount: Int
    public let p50Ms: Double?
    public let p95Ms: Double?
    public let p99Ms: Double?
    public let maxBurstLoss: Int
    public let currentBurstLoss: Int
    public let spikeCount: Int
    public let route: NetworkRouteInfo
    public let sessionStartedAt: Date

    // Per-protocol simultaneous diagnostics
    public let isMultiProtocolActive: Bool
    public let icmpPingMs: Double?
    public let isICMPLastLost: Bool
    public let icmpLostCount: Int
    public let icmpLossPercent: Double
    public let udpPingMs: Double?
    public let isUDPLastLost: Bool
    public let udpLostCount: Int
    public let udpLossPercent: Double
    public let udpProbeHost: String
    public let tcpPingMs: Double?
    public let isTCPLastLost: Bool
    public let tcpLostCount: Int
    public let tcpLossPercent: Double
    public let sessionDownloadBytes: UInt64
    public let sessionUploadBytes: UInt64

    public init(
        target: NetworkProbeTarget,
        pingMs: Double?,
        jitterMs: Double,
        downloadBytesPerSec: Double,
        uploadBytesPerSec: Double,
        isLastProbeLost: Bool,
        lostCount60s: Int,
        lossPercent60s: Double,
        lostCount120s: Int,
        lossPercent120s: Double,
        totalProbes: Int,
        totalLostCount: Int,
        totalLossPercent: Double,
        secondsSinceLastLoss: Double? = nil,
        detectedCycleSeconds: Double? = nil,
        cycleDescription: String? = nil,
        protocolPreference: NetworkProbeProtocol = .auto,
        activeTransport: NetworkProbeTransportUsed = .icmp,
        gatewayHost: String? = nil,
        isGatewayCustom: Bool = false,
        gatewayPingMs: Double? = nil,
        isGatewayLastProbeLost: Bool = false,
        gatewayTotalLostCount: Int = 0,
        gatewayTotalLossPercent: Double = 0.0,
        ispOnlyDropCount: Int = 0,
        localAndExternalDropCount: Int = 0,
        p50Ms: Double? = nil,
        p95Ms: Double? = nil,
        p99Ms: Double? = nil,
        maxBurstLoss: Int = 0,
        currentBurstLoss: Int = 0,
        spikeCount: Int = 0,
        route: NetworkRouteInfo = .unknown,
        sessionStartedAt: Date = Date(),
        isMultiProtocolActive: Bool = false,
        icmpPingMs: Double? = nil,
        isICMPLastLost: Bool = false,
        icmpLostCount: Int = 0,
        icmpLossPercent: Double = 0.0,
        udpPingMs: Double? = nil,
        isUDPLastLost: Bool = false,
        udpLostCount: Int = 0,
        udpLossPercent: Double = 0.0,
        udpProbeHost: String = "1.1.1.1",
        tcpPingMs: Double? = nil,
        isTCPLastLost: Bool = false,
        tcpLostCount: Int = 0,
        tcpLossPercent: Double = 0.0,
        sessionDownloadBytes: UInt64 = 0,
        sessionUploadBytes: UInt64 = 0
    ) {
        self.target = target
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.isLastProbeLost = isLastProbeLost
        self.lostCount60s = lostCount60s
        self.lossPercent60s = lossPercent60s
        self.lostCount120s = lostCount120s
        self.lossPercent120s = lossPercent120s
        self.totalProbes = totalProbes
        self.totalLostCount = totalLostCount
        self.totalLossPercent = totalLossPercent
        self.secondsSinceLastLoss = secondsSinceLastLoss
        self.detectedCycleSeconds = detectedCycleSeconds
        self.cycleDescription = cycleDescription
        self.protocolPreference = protocolPreference
        self.activeTransport = activeTransport
        self.gatewayHost = gatewayHost
        self.isGatewayCustom = isGatewayCustom
        self.gatewayPingMs = gatewayPingMs
        self.isGatewayLastProbeLost = isGatewayLastProbeLost
        self.gatewayTotalLostCount = gatewayTotalLostCount
        self.gatewayTotalLossPercent = gatewayTotalLossPercent
        self.ispOnlyDropCount = ispOnlyDropCount
        self.localAndExternalDropCount = localAndExternalDropCount
        self.p50Ms = p50Ms
        self.p95Ms = p95Ms
        self.p99Ms = p99Ms
        self.maxBurstLoss = maxBurstLoss
        self.currentBurstLoss = currentBurstLoss
        self.spikeCount = spikeCount
        self.route = route
        self.sessionStartedAt = sessionStartedAt
        self.isMultiProtocolActive = isMultiProtocolActive
        self.icmpPingMs = icmpPingMs
        self.isICMPLastLost = isICMPLastLost
        self.icmpLostCount = icmpLostCount
        self.icmpLossPercent = icmpLossPercent
        self.udpPingMs = udpPingMs
        self.isUDPLastLost = isUDPLastLost
        self.udpLostCount = udpLostCount
        self.udpLossPercent = udpLossPercent
        self.udpProbeHost = udpProbeHost
        self.tcpPingMs = tcpPingMs
        self.isTCPLastLost = isTCPLastLost
        self.tcpLostCount = tcpLostCount
        self.tcpLossPercent = tcpLossPercent
        self.sessionDownloadBytes = sessionDownloadBytes
        self.sessionUploadBytes = sessionUploadBytes
    }

    public static let placeholder = NetworkQualityMetrics(
        target: .cloudflare,
        pingMs: 14.2,
        jitterMs: 1.1,
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
        isLastProbeLost: false,
        lostCount60s: 0,
        lossPercent60s: 0.0,
        lostCount120s: 0,
        lossPercent120s: 0.0,
        totalProbes: 60,
        totalLostCount: 0,
        totalLossPercent: 0.0,
        secondsSinceLastLoss: nil,
        detectedCycleSeconds: nil,
        cycleDescription: nil,
        protocolPreference: .auto,
        activeTransport: .icmp,
        gatewayHost: "192.168.1.1",
        isGatewayCustom: false,
        gatewayPingMs: 2.1,
        isGatewayLastProbeLost: false,
        gatewayTotalLostCount: 0,
        gatewayTotalLossPercent: 0.0,
        ispOnlyDropCount: 0,
        localAndExternalDropCount: 0,
        p50Ms: 14.0,
        p95Ms: 18.5,
        p99Ms: 22.0,
        maxBurstLoss: 0,
        currentBurstLoss: 0,
        spikeCount: 0,
        route: NetworkRouteInfo(
            interfaceKind: "Wi-Fi",
            isVPNActive: false,
            vpnInterfaceName: nil,
            localIPv4: nil,
            detectedGatewayIP: "192.168.1.1"
        ),
        sessionStartedAt: Date()
    )

    public var downloadFormatted: String {
        Self.formatSpeed(self.downloadBytesPerSec)
    }

    public var uploadFormatted: String {
        Self.formatSpeed(self.uploadBytesPerSec)
    }

    public var sessionTotalBytes: UInt64 {
        self.sessionDownloadBytes &+ self.sessionUploadBytes
    }

    public var sessionDownloadFormatted: String {
        Self.formatBytes(self.sessionDownloadBytes)
    }

    public var sessionUploadFormatted: String {
        Self.formatBytes(self.sessionUploadBytes)
    }

    public var sessionTotalFormatted: String {
        Self.formatBytes(self.sessionTotalBytes)
    }

    private static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024.0 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_073_741_824.0 {
            return String(format: "%.2f GB", value / 1_073_741_824.0)
        } else if value >= 1_048_576.0 {
            return String(format: "%.1f MB", value / 1_048_576.0)
        } else if value >= 1024.0 {
            return String(format: "%.0f KB", value / 1024.0)
        } else {
            return "\(bytes) B"
        }
    }
}
