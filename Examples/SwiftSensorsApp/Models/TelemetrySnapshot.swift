import Darwin
import Foundation
import SwiftSensors
import UIKit

/// Summary of an individual thermal sensor for compact display in HUD and Widgets
struct ThermalSensorSummary: Codable, Sendable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let temperature: Double
}

/// Real hardware CPU topology & clock info from sysctl (no fabricated values)
struct HardwareTopology: Codable, Sendable, Equatable {
    let modelIdentifier: String
    let totalCores: Int
    let activeCores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    /// Real CPU frequency in MHz if exposed by OS; nil when iPadOS blocks DVFS frequency
    let frequencyMHz: Double?

    static let cached: HardwareTopology = HardwareTopology.current()

    static func current() -> HardwareTopology {
        let model = sysctlString("hw.machine") ?? "iPad"
        let total = ProcessInfo.processInfo.processorCount
        let active = ProcessInfo.processInfo.activeProcessorCount
        let pCores = Int(sysctlInt64("hw.perflevel0.physicalcpu") ?? 0)
        let eCores = Int(sysctlInt64("hw.perflevel1.physicalcpu") ?? 0)

        var freqMHz: Double? = nil
        if let hz = sysctlInt64("hw.cpufrequency"), hz > 0 {
            freqMHz = Double(hz) / 1_000_000.0
        } else if let maxHz = sysctlInt64("hw.cpufrequency_max"), maxHz > 0 {
            freqMHz = Double(maxHz) / 1_000_000.0
        }

        return HardwareTopology(
            modelIdentifier: model,
            totalCores: total,
            activeCores: active,
            performanceCores: pCores,
            efficiencyCores: eCores,
            frequencyMHz: freqMHz
        )
    }

    var coreDescription: String {
        if performanceCores > 0 && efficiencyCores > 0 {
            return "\(totalCores)c (\(performanceCores)P+\(efficiencyCores)E)"
        }
        return "\(activeCores)/\(totalCores) cores"
    }

    private static func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value
    }

    private static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}

/// Caches slow/diagnostic metrics (disk, uptime, VM regions, thread list) for 10 seconds
/// so 1Hz telemetry polling avoids redundant Mach IPC & file-system syscalls every second.
private actor SlowSnapshotMetricsCache {
    static let shared = SlowSnapshotMetricsCache()

    private struct CachedValues {
        let timestamp: Date
        let disk: DiskStats
        let uptime: String
        let vmMetrics: VMMemoryMetrics
        let threadSummary: ProcessThreadSummary
    }

    private var cached: CachedValues?
    private let ttlSeconds: TimeInterval = 10.0

    func get(using sensors: SwiftSensors) async -> (DiskStats, String, VMMemoryMetrics, ProcessThreadSummary) {
        let now = Date()
        if let existing = self.cached, now.timeIntervalSince(existing.timestamp) < self.ttlSeconds {
            return (existing.disk, existing.uptime, existing.vmMetrics, existing.threadSummary)
        }

        async let diskTask = sensors.getDiskStats()
        async let uptimeTask = sensors.getFormattedUptime()
        async let vmMetricsTask = sensors.getVMMemoryMetrics()
        async let threadSummaryTask = sensors.getThreadCPUSummary()

        let disk = await diskTask
        let uptime = await uptimeTask
        let vmMetrics = await vmMetricsTask
        let threadSummary = await threadSummaryTask

        self.cached = CachedValues(
            timestamp: now,
            disk: disk,
            uptime: uptime,
            vmMetrics: vmMetrics,
            threadSummary: threadSummary
        )
        return (disk, uptime, vmMetrics, threadSummary)
    }
}

/// Complete real-time telemetry snapshot shared between the main app, PiP HUD, and Home Screen Widgets
struct TelemetrySnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let peakTemperature: Double?
    let peakSensorName: String?
    let cpuTemperature: Double?
    let cpuSensorName: String?
    let averageTemperature: Double?
    let batteryTemperature: Double?
    let gpuTemperature: Double?
    let gpuSensorName: String?
    let topThermalSensors: [ThermalSensorSummary]
    let thermalState: String

    let cpuTotalPercent: Double
    let cpuUserPercent: Double
    let cpuSystemPercent: Double
    let topology: HardwareTopology

    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let memoryFreeBytes: UInt64
    let memoryActiveBytes: UInt64
    let memoryWiredBytes: UInt64
    let memoryCompressedBytes: UInt64
    let memoryAppAvailableBytes: UInt64

    let diskUsedBytes: UInt64
    let diskTotalBytes: UInt64
    let diskFreeBytes: UInt64

    let batteryPercent: Int?
    let isCharging: Bool

    let peakVoltage: Double?
    let totalCurrent: Double?
    let estimatedWatts: Double?

    let uptimeText: String

    // MARK: - Low-Level Kernel SLA Metrics
    let dirtyRatio: Double
    let jetsamLimitRemainingMB: Double?
    let activeThreadsCount: Int
    let isJetsamRisk: Bool

    // MARK: - Real-Time Network Quality & Packet Loss SLA
    let network: NetworkQualityMetrics

    var memoryUsedPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(100, max(0, (Double(memoryUsedBytes) / Double(memoryTotalBytes)) * 100.0))
    }

    var memoryUsedGB: Double {
        Double(memoryUsedBytes) / 1_073_741_824.0
    }

    var memoryTotalGB: Double {
        Double(memoryTotalBytes) / 1_073_741_824.0
    }

    var memoryFreeGB: Double {
        Double(memoryFreeBytes) / 1_073_741_824.0
    }

    var diskFreeGB: Double {
        Double(diskFreeBytes) / 1_073_741_824.0
    }

    var diskTotalGB: Double {
        Double(diskTotalBytes) / 1_073_741_824.0
    }

    var thermalStateLocalized: String {
        TelemetryTheme.localizedThermalState(thermalState)
    }

    /// Captures a live telemetry snapshot directly from SwiftSensors + system APIs
    static func captureLive() async -> TelemetrySnapshot {
        let sensors = SwiftSensors.shared
        async let thermalTask = sensors.getThermalSensorReadings()
        async let voltageTask = sensors.getVoltageSensorReadings()
        async let currentTask = sensors.getCurrentSensorReadings()
        async let memoryTask = sensors.getMemoryStats()
        async let cpuTask = sensors.getCPUStats()
        async let thermalStateTask = sensors.getThermalState()
        async let slowTask = SlowSnapshotMetricsCache.shared.get(using: sensors)
        async let networkTask = sensors.getNetworkQualityMetrics()

        let thermals = await thermalTask
        let voltages = await voltageTask
        let currents = await currentTask
        let memory = await memoryTask
        let cpu = await cpuTask
        let thermalState = await thermalStateTask
        let (disk, uptime, vmMetrics, threadSummary) = await slowTask
        let network = await networkTask

        let (batteryPercent, isCharging) = await MainActor.run { () -> (Int?, Bool) in
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let percent = level >= 0 ? Int((level * 100.0).rounded()) : nil
            let state = UIDevice.current.batteryState
            let charging = (state == .charging || state == .full)
            return (percent, charging)
        }

        return build(
            thermals: thermals,
            voltages: voltages,
            currents: currents,
            memory: memory,
            cpu: cpu,
            disk: disk,
            thermalState: thermalState,
            uptime: uptime,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            vmMetrics: vmMetrics,
            threadSummary: threadSummary,
            network: network
        )
    }

    static func build(
        thermals: [ThermalSensorReading],
        voltages: [VoltageSensorReading],
        currents: [CurrentSensorReading],
        memory: MemoryStats,
        cpu: CPUStats,
        disk: DiskStats,
        thermalState: ThermalState,
        uptime: String,
        batteryPercent: Int?,
        isCharging: Bool,
        vmMetrics: VMMemoryMetrics = VMMemoryMetrics(
            physicalFootprintBytes: 0,
            residentSizeBytes: 0,
            internalDirtyBytes: 0,
            compressedDirtyBytes: 0,
            jetsamLimitBytesRemaining: nil,
            mappedRegionsCount: 0,
            dirtyRatio: 0
        ),
        threadSummary: ProcessThreadSummary = ProcessThreadSummary(
            totalThreads: 0,
            runningThreads: 0,
            waitingThreads: 0,
            globalCPUPercent: 0,
            topThreads: [],
            totalWaitStateTime: 0,
            isMainThreadStarved: false
        ),
        network: NetworkQualityMetrics = .placeholder
    ) -> TelemetrySnapshot {
        // Filter sane physical sensor readings (°C)
        let validThermals = thermals
            .filter { $0.temperature.isFinite && $0.temperature > -10.0 && $0.temperature < 140.0 }
            .sorted { $0.temperature > $1.temperature }

        let peak = validThermals.first
        let avg: Double? = validThermals.isEmpty
            ? nil
            : validThermals.reduce(0.0) { $0 + $1.temperature } / Double(validThermals.count)

        let batterySensor = validThermals.first {
            let lower = $0.name.lowercased()
            return lower.contains("gas gauge") || lower.contains("battery") || lower.contains("batt")
        }

        // 1. Dedicated CPU Die Sensor (Apple Silicon Core Clusters: PMU tdie1..14 or TC0*)
        let cpuDieSensors = validThermals.filter { s in
            let lower = s.name.lowercased()
            if lower.contains("pmu2") || lower.contains("tcal") { return false }
            return lower.contains("pmu tdie") || lower.contains("cpu") || lower.hasPrefix("tc0") || lower.contains("soc mtr")
        }.sorted { $0.temperature > $1.temperature }
        let cpuSensor = cpuDieSensors.first ?? peak

        // 2. Dedicated GPU Die Sensor (Apple Silicon GPU Clusters: PMU2 tdie1..10 or TG0*)
        let gpuDieSensors = validThermals.filter { s in
            let lower = s.name.lowercased()
            if lower.contains("tcal") { return false }
            return lower.contains("pmu2 tdie") || lower.contains("gpu") || lower.contains("gfx") || lower.hasPrefix("tg")
        }.sorted { $0.temperature > $1.temperature }
        let gpuSensor = gpuDieSensors.first

        let topThermals = validThermals.prefix(6).map {
            ThermalSensorSummary(name: $0.name, temperature: $0.temperature)
        }

        // Power estimation from real voltage/current sensors when available
        let validVoltages = voltages.filter { $0.voltage.isFinite && $0.voltage > 0.1 && $0.voltage < 30.0 }
        let validCurrents = currents.filter { $0.current.isFinite && abs($0.current) > 0.001 && abs($0.current) < 20.0 }

        let battVoltage = validVoltages.first {
            let n = $0.name.lowercased()
            return n.contains("batt") || n.contains("vbus") || n.contains("sys")
        }?.voltage ?? validVoltages.map(\.voltage).max()

        let battCurrent = validCurrents.first {
            let n = $0.name.lowercased()
            return n.contains("batt") || n.contains("ibus") || n.contains("sys")
        }?.current ?? validCurrents.map { abs($0.current) }.max()

        let watts: Double? = {
            if let v = battVoltage, let i = battCurrent {
                return abs(v * i)
            }
            return nil
        }()

        return TelemetrySnapshot(
            timestamp: Date(),
            peakTemperature: peak?.temperature,
            peakSensorName: peak?.name,
            cpuTemperature: cpuSensor?.temperature,
            cpuSensorName: cpuSensor?.name,
            averageTemperature: avg,
            batteryTemperature: batterySensor?.temperature,
            gpuTemperature: gpuSensor?.temperature,
            gpuSensorName: gpuSensor?.name,
            topThermalSensors: topThermals,
            thermalState: thermalState.rawValue,
            cpuTotalPercent: cpu.totalUsage,
            cpuUserPercent: cpu.userUsage,
            cpuSystemPercent: cpu.systemUsage,
            topology: HardwareTopology.cached,
            memoryUsedBytes: memory.totalUsedMemory,
            memoryTotalBytes: memory.totalMemory,
            memoryFreeBytes: memory.freeMemory,
            memoryActiveBytes: memory.activeMemory,
            memoryWiredBytes: memory.wiredMemory,
            memoryCompressedBytes: memory.compressedMemory,
            memoryAppAvailableBytes: memory.appAvailableMemory,
            diskUsedBytes: disk.usedSpace,
            diskTotalBytes: disk.totalSpace,
            diskFreeBytes: disk.freeSpace,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            peakVoltage: battVoltage,
            totalCurrent: battCurrent.map { abs($0) },
            estimatedWatts: watts,
            uptimeText: uptime,
            dirtyRatio: vmMetrics.dirtyRatio,
            jetsamLimitRemainingMB: vmMetrics.jetsamLimitRemainingMB,
            activeThreadsCount: threadSummary.totalThreads,
            isJetsamRisk: vmMetrics.isJetsamRisk,
            network: network
        )
    }

    static let placeholder = TelemetrySnapshot(
        timestamp: Date(),
        peakTemperature: 38.4,
        peakSensorName: "PMU tdie",
        cpuTemperature: 38.4,
        cpuSensorName: "PMU tdie6",
        averageTemperature: 34.2,
        batteryTemperature: 31.8,
        gpuTemperature: 35.1,
        gpuSensorName: "PMU2 tdie1",
        topThermalSensors: [
            ThermalSensorSummary(name: "PMU tdie", temperature: 38.4),
            ThermalSensorSummary(name: "SOC MTR", temperature: 36.9),
            ThermalSensorSummary(name: "GPU die", temperature: 35.1),
            ThermalSensorSummary(name: "Gas Gauge", temperature: 31.8)
        ],
        thermalState: "Nominal",
        cpuTotalPercent: 24.5,
        cpuUserPercent: 18.2,
        cpuSystemPercent: 6.3,
        topology: HardwareTopology(
            modelIdentifier: "iPad",
            totalCores: 10,
            activeCores: 10,
            performanceCores: 4,
            efficiencyCores: 6,
            frequencyMHz: nil
        ),
        memoryUsedBytes: 5_368_709_120,
        memoryTotalBytes: 8_589_934_592,
        memoryFreeBytes: 3_221_225_472,
        memoryActiveBytes: 2_684_354_560,
        memoryWiredBytes: 1_610_612_736,
        memoryCompressedBytes: 1_073_741_824,
        memoryAppAvailableBytes: 4_294_967_296,
        diskUsedBytes: 128_000_000_000,
        diskTotalBytes: 256_000_000_000,
        diskFreeBytes: 128_000_000_000,
        batteryPercent: 84,
        isCharging: false,
        peakVoltage: 4.12,
        totalCurrent: 0.95,
        estimatedWatts: 3.91,
        uptimeText: "2d 4h",
        dirtyRatio: 0.28,
        jetsamLimitRemainingMB: 850.0,
        activeThreadsCount: 8,
        isJetsamRisk: false,
        network: .placeholder
    )
}
