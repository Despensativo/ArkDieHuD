import Foundation
import SwiftSensors

/// Native localization helper resolved automatically against iPadOS / iOS preferred languages
/// (`en`, `pt-BR`, `pt`, `es`) via `Localizable.xcstrings`.
enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .main, comment: "")
        return String(format: format, locale: .current, arguments: args)
    }
}

extension HUDLayoutMode {
    var localizedTitle: String {
        switch self {
        case .gamerBar:
            return L10n.tr("Gamer Bar (1 Transparent Line)")
        case .gamerMini:
            return L10n.tr("Gamer Overlay (2 Lines)")
        case .compact:
            return L10n.tr("Compact Grid")
        case .detailed:
            return L10n.tr("Detailed")
        }
    }
}

extension SensorSection {
    var localizedTitle: String {
        switch self {
        case .network:
            return L10n.tr("Network & Packet Log")
        case .telemetryLogs:
            return L10n.tr("24h Telemetry & Logs")
        case .performance:
            return L10n.tr("Performance & Kernel SLA")
        case .thermal:
            return L10n.tr("Thermal Sensors")
        case .voltage:
            return L10n.tr("Voltage Sensors")
        case .current:
            return L10n.tr("Current Sensors")
        case .memory:
            return L10n.tr("Memory")
        case .cpu:
            return L10n.tr("CPU")
        case .disk:
            return L10n.tr("Disk")
        case .system:
            return L10n.tr("System")
        }
    }
}

extension NetworkProbeProtocol {
    var localizedTitle: String {
        switch self {
        case .simultaneous:
            return L10n.tr("Simultaneous (ICMP + UDP + TCP)")
        case .auto:
            return L10n.tr("Auto (ICMP -> TCP)")
        case .icmp:
            return L10n.tr("ICMP (Ping)")
        case .udp:
            return L10n.tr("UDP (DNS 53)")
        case .tcp:
            return L10n.tr("TCP (Handshake)")
        }
    }
}

extension NetworkIncidentKind {
    var localizedTitle: String {
        switch self {
        case .ispDrop:
            return L10n.tr("External Drop / ISP")
        case .localDrop:
            return L10n.tr("Local Drop / Wi-Fi")
        case .protocolDrop:
            return L10n.tr("Protocol Drop")
        case .drop:
            return L10n.tr("Lost Packet")
        case .burst:
            return L10n.tr("Loss Burst")
        case .spike:
            return L10n.tr("Latency Spike")
        case .routeChange:
            return L10n.tr("Route / VPN Switch")
        }
    }
}

extension NetworkRouteInfo {
    var localizedSummary: String {
        if self.isVPNActive {
            if let vpn = self.vpnInterfaceName {
                return "\(self.interfaceKind) + VPN (\(vpn))"
            }
            return "\(self.interfaceKind) + VPN"
        }
        return L10n.fmt("%@ Direct", self.interfaceKind)
    }
}

extension MemoryMetricType {
    var localizedName: String {
        L10n.tr(self.name)
    }
}

extension CPUMetricType {
    var localizedName: String {
        L10n.tr(self.name)
    }
}

extension DiskMetricType {
    var localizedName: String {
        L10n.tr(self.name)
    }
}

extension HardwareTopology {
    var localizedCoreDescription: String {
        if self.performanceCores > 0 && self.efficiencyCores > 0 {
            return "\(self.totalCores)c (\(self.performanceCores)P+\(self.efficiencyCores)E)"
        }
        return L10n.fmt("%lld/%lld cores", self.activeCores, self.totalCores)
    }
}
