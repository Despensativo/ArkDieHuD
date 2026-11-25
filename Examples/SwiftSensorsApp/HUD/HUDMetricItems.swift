import CoreGraphics
import Foundation
import UIKit

struct HUDInlineMetric {
    let label: String
    let value: String
    let color: UIColor
    let isNetwork: Bool
}

struct HUDCardMetric {
    let label: String
    let value: String
    let subtitle: String
    let accent: UIColor
    let progress: Double
}

struct HUDSystemRowMetric {
    let label: String
    let value: String
    let color: UIColor
}

/// Builds dynamic metric items and deterministic PiP canvas sizes from TelemetryVisibilityConfig
/// so toggling metrics removes blank spaces cleanly without jittering PiP dimensions per tick.
enum HUDMetricBuilder {
    static let pcStealthCanvasSize = CGSize(width: 268, height: 44)

    static func canvasSize(for mode: HUDLayoutMode, config: TelemetryVisibilityConfig) -> CGSize {
        switch mode {
        case .gamerBar:
            var widths: [CGFloat] = []
            if config.showCPUTemp { widths.append(80) }
            if config.showGPUTemp { widths.append(80) }
            if config.showCPULoad { widths.append(68) }
            if config.showRAM { widths.append(74) }
            if config.showPowerWatts { widths.append(74) }
            if config.showBattery { widths.append(68) }
            if config.showThermalState { widths.append(68) }
            if config.showPing { widths.append(68) }
            if config.showUDPPing { widths.append(74) }
            if config.showGatewayPing { widths.append(66) }
            if config.showJitter { widths.append(78) }
            if config.showPacketLoss { widths.append(102) }

            let totalItemsWidth = widths.isEmpty ? 120 : widths.reduce(0, +)
            let dividersWidth = CGFloat(max(0, widths.count - 1)) * 8
            let rawWidth = totalItemsWidth + dividersWidth + 28
            let clamped = min(860, max(180, rawWidth))
            let evenWidth = ceil(clamped / 2.0) * 2.0
            return CGSize(width: evenWidth, height: 32)

        case .gamerMini:
            let hwWidth: CGFloat =
                (config.showCPUTemp ? 80 : 0)
                + (config.showGPUTemp ? 80 : 0)
                + (config.showCPULoad ? 68 : 0)
                + (config.showRAM ? 74 : 0)
                + (config.showPowerWatts ? 74 : 0)
                + (config.showBattery ? 68 : 0)
                + (config.showThermalState ? 68 : 0)
            let netWidth: CGFloat =
                (config.showPing ? 68 : 0)
                + (config.showUDPPing ? 74 : 0)
                + (config.showGatewayPing ? 66 : 0)
                + (config.showJitter ? 78 : 0)
                + (config.showPacketLoss ? 102 : 0)

            let rawWidth: CGFloat
            if hwWidth > 0 && netWidth > 0 {
                rawWidth = max(hwWidth, netWidth) + 28
            } else {
                rawWidth = (max(hwWidth, netWidth) * 0.58) + 28
            }
            let clamped = min(540, max(200, rawWidth))
            let evenWidth = ceil(clamped / 2.0) * 2.0
            return CGSize(width: evenWidth, height: 56)

        case .compact:
            let count = max(1, config.enabledMetricCount)
            let rows = min(3, Int(ceil(Double(count) / 4.0)))
            return CGSize(width: 380, height: CGFloat(30 + rows * 58))

        case .detailed:
            return CGSize(width: 440, height: 210)
        }
    }

    static func inlineMetrics(from snapshot: TelemetrySnapshot, config: TelemetryVisibilityConfig) -> [HUDInlineMetric] {
        var items: [HUDInlineMetric] = []

        if config.showCPUTemp {
            let temp = snapshot.cpuTemperature ?? snapshot.peakTemperature
            let val = temp.map { String(format: "%.1f°C", $0) } ?? "--°C"
            items.append(HUDInlineMetric(label: "CPU", value: val, color: self.temperatureColor(temp), isNetwork: false))
        }

        if config.showGPUTemp, let gpuT = snapshot.gpuTemperature {
            items.append(HUDInlineMetric(
                label: "GPU",
                value: String(format: "%.1f°C", gpuT),
                color: self.temperatureColor(gpuT),
                isNetwork: false
            ))
        }

        if config.showCPULoad {
            items.append(HUDInlineMetric(
                label: "LOAD",
                value: String(format: "%.0f%%", snapshot.cpuTotalPercent),
                color: self.usageColor(snapshot.cpuTotalPercent),
                isNetwork: false
            ))
        }

        if config.showRAM {
            items.append(HUDInlineMetric(
                label: "RAM",
                value: String(format: "%.1fG", snapshot.memoryUsedGB),
                color: self.usageColor(snapshot.memoryUsedPercent),
                isNetwork: false
            ))
        }

        if config.showPowerWatts, let watts = snapshot.estimatedWatts {
            items.append(HUDInlineMetric(
                label: "PWR",
                value: String(format: "%.1fW", watts),
                color: UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1.0),
                isNetwork: false
            ))
        }

        if config.showBattery, let bat = snapshot.batteryPercent {
            let batVal = snapshot.isCharging ? "\(bat)%+" : "\(bat)%"
            let batColor: UIColor = bat <= 20
                ? UIColor(red: 1.0, green: 0.32, blue: 0.32, alpha: 1.0)
                : UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            items.append(HUDInlineMetric(label: "BAT", value: batVal, color: batColor, isNetwork: false))
        }

        if config.showThermalState {
            items.append(HUDInlineMetric(
                label: "THM",
                value: snapshot.thermalStateLocalized,
                color: self.thermalStateColor(snapshot.thermalState),
                isNetwork: false
            ))
        }

        if config.showPing {
            let pingText: String
            if snapshot.network.isLastProbeLost {
                pingText = "LOST"
            } else if let p = snapshot.network.pingMs {
                pingText = String(format: "%.0fms", p)
            } else {
                pingText = "--ms"
            }
            items.append(HUDInlineMetric(
                label: "MS",
                value: pingText,
                color: self.pingColor(snapshot.network.pingMs, isLost: snapshot.network.isLastProbeLost),
                isNetwork: true
            ))
        }

        if config.showUDPPing {
            let udpVal: String
            if snapshot.network.isUDPLastLost {
                udpVal = "DROP"
            } else if let udp = snapshot.network.udpPingMs {
                udpVal = String(format: "%.0fms", udp)
            } else {
                udpVal = "--ms"
            }
            items.append(HUDInlineMetric(
                label: "UDP",
                value: udpVal,
                color: self.pingColor(snapshot.network.udpPingMs, isLost: snapshot.network.isUDPLastLost),
                isNetwork: true
            ))
        }

        if config.showGatewayPing {
            let gwVal: String
            if snapshot.network.isGatewayLastProbeLost {
                gwVal = "DROP"
            } else if let gw = snapshot.network.gatewayPingMs {
                gwVal = String(format: "%.0fms", gw)
            } else {
                gwVal = "--"
            }
            items.append(HUDInlineMetric(
                label: "GW",
                value: gwVal,
                color: self.pingColor(snapshot.network.gatewayPingMs, isLost: snapshot.network.isGatewayLastProbeLost),
                isNetwork: true
            ))
        }

        if config.showJitter {
            let jitVal = String(format: "±%.1fms", snapshot.network.jitterMs)
            let jitColor = snapshot.network.jitterMs > 15
                ? UIColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 1.0)
                : UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            items.append(HUDInlineMetric(label: "JIT", value: jitVal, color: jitColor, isNetwork: true))
        }

        if config.showPacketLoss {
            let totalLost = snapshot.network.totalLostCount
            let lossPct = snapshot.network.totalLossPercent
            let lossText: String
            if snapshot.network.isLastProbeLost {
                lossText = totalLost > 0 ? String(format: "DROP! %.1f%%", lossPct) : "DROP!"
            } else if totalLost > 0 {
                lossText = String(format: "%.1f%% (%dp)", lossPct, totalLost)
            } else {
                lossText = "0.0%"
            }
            items.append(HUDInlineMetric(
                label: "LOSS",
                value: lossText,
                color: self.lossColor(isLostNow: snapshot.network.isLastProbeLost, lossPct: lossPct),
                isNetwork: true
            ))
        }

        if items.isEmpty {
            items.append(HUDInlineMetric(
                label: "HUD",
                value: L10n.tr("Enable metrics"),
                color: UIColor(white: 0.78, alpha: 1.0),
                isNetwork: false
            ))
        }

        return items
    }

    static func cardMetrics(from snapshot: TelemetrySnapshot, config: TelemetryVisibilityConfig) -> [HUDCardMetric] {
        var cards: [HUDCardMetric] = []

        if config.showPing {
            let pingVal: String
            if snapshot.network.isLastProbeLost {
                pingVal = "LOST"
            } else if let p = snapshot.network.pingMs {
                pingVal = String(format: "%.0fms", p)
            } else {
                pingVal = "--ms"
            }
            let totalLost = snapshot.network.totalLostCount
            let lossPct = snapshot.network.totalLossPercent
            let sub = config.showPacketLoss
                ? snapshot.network.target.host
                : (snapshot.network.isLastProbeLost
                    ? (totalLost > 0 ? String(format: "DROP! %.1f%%", lossPct) : "DROP!")
                    : L10n.fmt("Loss: %.1f%% (%lldp)", lossPct, totalLost))
            cards.append(HUDCardMetric(
                label: L10n.tr("NET SLA"),
                value: pingVal,
                subtitle: sub,
                accent: self.pingColor(snapshot.network.pingMs, isLost: snapshot.network.isLastProbeLost),
                progress: min(1.0, max(0.05, 1.0 - (lossPct / 100.0)))
            ))
        }

        if config.showCPUTemp {
            let cpuT = snapshot.cpuTemperature ?? snapshot.peakTemperature
            let tempText = cpuT.map { String(format: "%.1f°C", $0) } ?? "--°C"
            let sub: String
            if let gpu = snapshot.gpuTemperature {
                sub = String(format: "GPU %.1f°C", gpu)
            } else {
                sub = snapshot.thermalStateLocalized
            }
            cards.append(HUDCardMetric(
                label: L10n.tr("CPU TEMP"),
                value: tempText,
                subtitle: sub,
                accent: self.temperatureColor(cpuT),
                progress: self.normalizedTempProgress(cpuT)
            ))
        }

        if config.showGPUTemp {
            let gpuT = snapshot.gpuTemperature
            cards.append(HUDCardMetric(
                label: L10n.tr("GPU TEMP"),
                value: gpuT.map { String(format: "%.1f°C", $0) } ?? "--°C",
                subtitle: snapshot.gpuSensorName ?? L10n.tr("GPU Silicon"),
                accent: self.temperatureColor(gpuT),
                progress: self.normalizedTempProgress(gpuT)
            ))
        }

        if config.showCPULoad {
            cards.append(HUDCardMetric(
                label: L10n.tr("CPU LOAD"),
                value: String(format: "%.0f%%", snapshot.cpuTotalPercent),
                subtitle: snapshot.topology.localizedCoreDescription,
                accent: self.usageColor(snapshot.cpuTotalPercent),
                progress: min(1.0, max(0.05, snapshot.cpuTotalPercent / 100.0))
            ))
        }

        if config.showRAM {
            cards.append(HUDCardMetric(
                label: "RAM",
                value: String(format: "%.1fG", snapshot.memoryUsedGB),
                subtitle: L10n.fmt("%.0f%% of %.0fG", snapshot.memoryUsedPercent, snapshot.memoryTotalGB),
                accent: self.usageColor(snapshot.memoryUsedPercent),
                progress: min(1.0, max(0.05, snapshot.memoryUsedPercent / 100.0))
            ))
        }

        if config.showPowerWatts {
            let powerValue = snapshot.estimatedWatts.map { String(format: "%.1fW", $0) } ?? "--W"
            let powerProgress = snapshot.estimatedWatts.map { min(1.0, $0 / 35.0) } ?? 0.15
            cards.append(HUDCardMetric(
                label: L10n.tr("POWER"),
                value: powerValue,
                subtitle: snapshot.thermalStateLocalized,
                accent: UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1.0),
                progress: powerProgress
            ))
        }

        if config.showBattery {
            let batPct = snapshot.batteryPercent ?? 0
            let batVal = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
            let batColor: UIColor = batPct <= 20
                ? UIColor(red: 1.0, green: 0.32, blue: 0.32, alpha: 1.0)
                : UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            cards.append(HUDCardMetric(
                label: L10n.tr("BATTERY"),
                value: batVal,
                subtitle: snapshot.isCharging ? L10n.tr("Charging") : L10n.tr("On Battery"),
                accent: batColor,
                progress: min(1.0, max(0.05, Double(batPct) / 100.0))
            ))
        }

        if config.showThermalState {
            cards.append(HUDCardMetric(
                label: L10n.tr("THERMAL"),
                value: snapshot.thermalStateLocalized,
                subtitle: L10n.tr("iPadOS State"),
                accent: self.thermalStateColor(snapshot.thermalState),
                progress: self.thermalProgress(snapshot.thermalState)
            ))
        }

        if config.showUDPPing {
            let val = snapshot.network.isUDPLastLost
                ? "DROP"
                : (snapshot.network.udpPingMs.map { String(format: "%.0fms", $0) } ?? "--ms")
            cards.append(HUDCardMetric(
                label: "UDP 53",
                value: val,
                subtitle: L10n.fmt("Loss %.1f%%", snapshot.network.udpLossPercent),
                accent: self.pingColor(snapshot.network.udpPingMs, isLost: snapshot.network.isUDPLastLost),
                progress: min(1.0, max(0.05, 1.0 - (snapshot.network.udpLossPercent / 100.0)))
            ))
        }

        if config.showGatewayPing {
            let val = snapshot.network.isGatewayLastProbeLost
                ? "DROP"
                : (snapshot.network.gatewayPingMs.map { String(format: "%.1fms", $0) } ?? "--ms")
            cards.append(HUDCardMetric(
                label: L10n.tr("ROUTER"),
                value: val,
                subtitle: snapshot.network.gatewayHost ?? "Gateway",
                accent: self.pingColor(snapshot.network.gatewayPingMs, isLost: snapshot.network.isGatewayLastProbeLost),
                progress: min(1.0, max(0.05, 1.0 - (snapshot.network.gatewayTotalLossPercent / 100.0)))
            ))
        }

        if config.showJitter {
            let jitColor = snapshot.network.jitterMs > 15
                ? UIColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 1.0)
                : UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            cards.append(HUDCardMetric(
                label: "JITTER",
                value: String(format: "±%.1fms", snapshot.network.jitterMs),
                subtitle: "RFC 3550",
                accent: jitColor,
                progress: min(1.0, max(0.05, snapshot.network.jitterMs / 40.0))
            ))
        }

        if config.showPacketLoss {
            let lossPct = snapshot.network.totalLossPercent
            let val = snapshot.network.isLastProbeLost ? "DROP!" : String(format: "%.1f%%", lossPct)
            cards.append(HUDCardMetric(
                label: L10n.tr("LOSS"),
                value: val,
                subtitle: "\(snapshot.network.totalLostCount) pkts",
                accent: self.lossColor(isLostNow: snapshot.network.isLastProbeLost, lossPct: lossPct),
                progress: min(1.0, max(0.05, 1.0 - (lossPct / 100.0)))
            ))
        }

        if cards.isEmpty {
            cards.append(HUDCardMetric(
                label: "HUD",
                value: L10n.tr("Customize"),
                subtitle: L10n.tr("Enable at least 1 metric"),
                accent: UIColor(white: 0.78, alpha: 1.0),
                progress: 0.2
            ))
        }

        return cards
    }

    static func detailRows(from snapshot: TelemetrySnapshot, config: TelemetryVisibilityConfig) -> [HUDSystemRowMetric] {
        var rows: [HUDSystemRowMetric] = []

        if config.showJitter {
            rows.append(HUDSystemRowMetric(
                label: "Jitter RFC",
                value: String(format: "±%.1f ms", snapshot.network.jitterMs),
                color: snapshot.network.jitterMs > 15
                    ? UIColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 1.0)
                    : UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            ))
        }

        if config.showPacketLoss {
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("Total Loss"),
                value: String(format: "%.1f%% (%dp)", snapshot.network.totalLossPercent, snapshot.network.totalLostCount),
                color: self.lossColor(isLostNow: snapshot.network.isLastProbeLost, lossPct: snapshot.network.totalLossPercent)
            ))
        }

        if config.showUDPPing {
            let val = snapshot.network.isUDPLastLost
                ? "DROP"
                : (snapshot.network.udpPingMs.map { String(format: "%.0f ms", $0) } ?? "-- ms")
            rows.append(HUDSystemRowMetric(
                label: "UDP DNS 53",
                value: val,
                color: self.pingColor(snapshot.network.udpPingMs, isLost: snapshot.network.isUDPLastLost)
            ))
        }

        if config.showGatewayPing {
            let val = snapshot.network.isGatewayLastProbeLost
                ? "DROP"
                : (snapshot.network.gatewayPingMs.map { String(format: "%.1f ms", $0) } ?? "-- ms")
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("Router"),
                value: val,
                color: self.pingColor(snapshot.network.gatewayPingMs, isLost: snapshot.network.isGatewayLastProbeLost)
            ))
        }

        if config.showPowerWatts, let w = snapshot.estimatedWatts {
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("Power"),
                value: String(format: "%.1f W", w),
                color: UIColor(red: 1.0, green: 0.65, blue: 0.28, alpha: 1.0)
            ))
        }

        if config.showBattery, let bat = snapshot.batteryPercent {
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("Battery"),
                value: snapshot.isCharging ? "\(bat)% +" : "\(bat)%",
                color: UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
            ))
        }

        if config.showRAM {
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("RAM Used"),
                value: String(format: "%.1f GB", snapshot.memoryUsedGB),
                color: self.usageColor(snapshot.memoryUsedPercent)
            ))
        }

        if config.showThermalState {
            rows.append(HUDSystemRowMetric(
                label: L10n.tr("Thermal"),
                value: snapshot.thermalStateLocalized,
                color: self.thermalStateColor(snapshot.thermalState)
            ))
        }

        return rows
    }

    // MARK: - Shared Semantic Colors

    static func pingColor(_ ping: Double?, isLost: Bool) -> UIColor {
        if isLost { return UIColor(red: 1.0, green: 0.28, blue: 0.28, alpha: 1.0) }
        guard let p = ping else { return UIColor(white: 0.70, alpha: 1.0) }
        if p <= 30 { return UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0) }
        if p <= 65 { return UIColor(red: 0.30, green: 0.85, blue: 0.98, alpha: 1.0) }
        if p <= 110 { return UIColor(red: 0.98, green: 0.84, blue: 0.28, alpha: 1.0) }
        return UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
    }

    static func lossColor(isLostNow: Bool, lossPct: Double) -> UIColor {
        if isLostNow { return UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0) }
        if lossPct > 5.0 { return UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0) }
        if lossPct > 0.0 { return UIColor(red: 1.0, green: 0.75, blue: 0.25, alpha: 1.0) }
        return UIColor(white: 0.85, alpha: 1.0)
    }

    static func temperatureColor(_ temp: Double?) -> UIColor {
        guard let temp else { return UIColor(white: 0.75, alpha: 1.0) }
        if temp >= 55 { return UIColor(red: 1.0, green: 0.32, blue: 0.32, alpha: 1.0) }
        if temp >= 45 { return UIColor(red: 1.0, green: 0.65, blue: 0.22, alpha: 1.0) }
        if temp >= 38 { return UIColor(red: 0.98, green: 0.84, blue: 0.28, alpha: 1.0) }
        return UIColor(red: 0.28, green: 0.92, blue: 0.56, alpha: 1.0)
    }

    static func usageColor(_ percent: Double) -> UIColor {
        if percent >= 85 { return UIColor(red: 1.0, green: 0.32, blue: 0.32, alpha: 1.0) }
        if percent >= 65 { return UIColor(red: 1.0, green: 0.68, blue: 0.24, alpha: 1.0) }
        return UIColor(red: 0.30, green: 0.85, blue: 0.98, alpha: 1.0)
    }

    static func thermalStateColor(_ state: String) -> UIColor {
        switch state {
        case "Nominal": return UIColor(red: 0.28, green: 0.90, blue: 0.56, alpha: 1.0)
        case "Fair": return UIColor(red: 0.98, green: 0.84, blue: 0.28, alpha: 1.0)
        case "Serious": return UIColor(red: 1.0, green: 0.58, blue: 0.20, alpha: 1.0)
        case "Critical": return UIColor(red: 1.0, green: 0.28, blue: 0.28, alpha: 1.0)
        default: return UIColor(white: 0.70, alpha: 1.0)
        }
    }

    static func normalizedTempProgress(_ temp: Double?) -> Double {
        guard let temp else { return 0.1 }
        return min(1.0, max(0.05, (temp - 20.0) / 55.0))
    }

    static func thermalProgress(_ state: String) -> Double {
        switch state {
        case "Nominal": return 0.25
        case "Fair": return 0.50
        case "Serious": return 0.78
        case "Critical": return 1.0
        default: return 0.15
        }
    }
}
