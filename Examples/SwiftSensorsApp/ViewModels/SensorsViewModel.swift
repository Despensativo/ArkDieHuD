import Foundation
import SwiftSensors
import SwiftUI

/// Environment key for the SensorsViewModel
struct SensorsViewModelKey: EnvironmentKey {
    static var defaultValue: SensorsViewModel {
        MainActor.assumeIsolated {
            SensorsViewModel()
        }
    }
}

/// Environment extension for accessing the SensorsViewModel
extension EnvironmentValues {
    var sensorsViewModel: SensorsViewModel {
        get { self[SensorsViewModelKey.self] }
        set { self[SensorsViewModelKey.self] = newValue }
    }
}

/// View model for sensor data management across dashboard, section details, and charts.
@MainActor
@Observable
final class SensorsViewModel {
    // Sensor readings
    var thermalSensorReadings: [ThermalSensorReading] = []
    var voltageSensorReadings: [VoltageSensorReading] = []
    var currentSensorReadings: [CurrentSensorReading] = []
    var memoryStats: MemoryStats?
    var cpuStats: CPUStats?
    var diskStats: DiskStats?
    var thermalState: ThermalState = .unknown
    var uptimeText: String = L10n.tr("Loading...")

    // Low-Level Kernel Metrics
    var vmMetrics: VMMemoryMetrics?
    var threadSummary: ProcessThreadSummary?
    var largeVMRegions: [VMRegionInfo] = []
    var isScanningVM: Bool = false
    var lastPurgeTime: Date?

    // Formatted display values (index-aligned with source arrays and metric enums)
    var formattedTemperatures: [String] = []
    var formattedVoltages: [String] = []
    var formattedCurrents: [String] = []
    var formattedMemoryValues: [String] = []
    var formattedCPUValues: [String] = []
    var formattedDiskValues: [String] = []

    // Selected readings for charts
    var selectedThermalReadings: Set<String> = []
    var selectedVoltageReadings: Set<String> = []
    var selectedCurrentReadings: Set<String> = []
    var selectedMemoryItems: Set<Int> = []
    var selectedCPUItems: Set<Int> = []
    var selectedDiskItems: Set<Int> = []

    // Historical reading data for charts
    var thermalReadingData: [SensorData] = []
    var voltageReadingData: [SensorData] = []
    var currentReadingData: [SensorData] = []
    var memoryMetricData: [SensorData] = []
    var cpuMetricData: [SensorData] = []
    var diskMetricData: [SensorData] = []

    // Cache & update throttling
    private var lastUpdateTime = Date.distantPast
    private let updateInterval: TimeInterval = 1.0
    private var isUpdating: Bool = false

    let formatter = SensorFormatter.shared

    init() {
        Task {
            await VMMemoryMonitor.shared.registerPurgeHandler {
                DispatchQueue.main.async {
                    URLCache.shared.removeAllCachedResponses()
                }
            }
        }
        self.updateSensorData()
    }

    /// Updates sensor data if the cache has expired
    func updateIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(self.lastUpdateTime) > self.updateInterval {
            self.updateSensorData()
        }
    }

    /// Get filtered thermal reading data for specified time window
    func filteredThermalData(timeWindow: TimeInterval) -> [SensorData] {
        self.filteredNamedData(self.thermalReadingData, selectedNames: self.selectedThermalReadings, timeWindow: timeWindow)
    }

    /// Get filtered voltage reading data for specified time window
    func filteredVoltageData(timeWindow: TimeInterval) -> [SensorData] {
        self.filteredNamedData(self.voltageReadingData, selectedNames: self.selectedVoltageReadings, timeWindow: timeWindow)
    }

    /// Get filtered current reading data for specified time window
    func filteredCurrentData(timeWindow: TimeInterval) -> [SensorData] {
        self.filteredNamedData(self.currentReadingData, selectedNames: self.selectedCurrentReadings, timeWindow: timeWindow)
    }

    /// Get filtered memory metric data for specified time window
    func filteredMemoryData(timeWindow: TimeInterval) -> [SensorData] {
        let names = Set(self.selectedMemoryItems.compactMap { MemoryMetricType(rawValue: $0)?.name })
        return self.filteredNamedData(self.memoryMetricData, selectedNames: names, timeWindow: timeWindow)
    }

    /// Get filtered CPU metric data for specified time window
    func filteredCPUData(timeWindow: TimeInterval) -> [SensorData] {
        let names = Set(self.selectedCPUItems.compactMap { CPUMetricType(rawValue: $0)?.name })
        return self.filteredNamedData(self.cpuMetricData, selectedNames: names, timeWindow: timeWindow)
    }

    /// Get filtered disk metric data for specified time window
    func filteredDiskData(timeWindow: TimeInterval) -> [SensorData] {
        let names = Set(self.selectedDiskItems.compactMap { DiskMetricType(rawValue: $0)?.name })
        return self.filteredNamedData(self.diskMetricData, selectedNames: names, timeWindow: timeWindow)
    }

    private func filteredNamedData(
        _ source: [SensorData],
        selectedNames: Set<String>,
        timeWindow: TimeInterval
    ) -> [SensorData] {
        let cutoffDate = Date().addingTimeInterval(-timeWindow)
        return source.filter { $0.timestamp > cutoffDate && selectedNames.contains($0.sensorName) }
    }

    /// Fetches fresh sensor data from all sources on background tasks
    func updateSensorData() {
        guard !self.isUpdating else { return }
        self.isUpdating = true

        Task {
            defer { self.isUpdating = false }
            let snapshot = await Self.fetchAllMetrics(using: self.formatter)

            self.thermalSensorReadings = snapshot.thermals
            self.voltageSensorReadings = snapshot.voltages
            self.currentSensorReadings = snapshot.currents
            self.memoryStats = snapshot.memory
            self.cpuStats = snapshot.cpu
            self.diskStats = snapshot.disk
            self.thermalState = snapshot.thermalState
            self.uptimeText = snapshot.uptimeText
            self.vmMetrics = snapshot.vmMetrics
            self.threadSummary = snapshot.threadSummary

            self.formattedTemperatures = snapshot.formattedTemperatures
            self.formattedVoltages = snapshot.formattedVoltages
            self.formattedCurrents = snapshot.formattedCurrents
            self.formattedMemoryValues = snapshot.formattedMemoryValues
            self.formattedCPUValues = snapshot.formattedCPUValues
            self.formattedDiskValues = snapshot.formattedDiskValues

            let maxDataPoints = 3 * 60 * 60
            self.appendHistory(&self.thermalReadingData, with: snapshot.thermalData, limit: maxDataPoints)
            self.appendHistory(&self.voltageReadingData, with: snapshot.voltageData, limit: maxDataPoints)
            self.appendHistory(&self.currentReadingData, with: snapshot.currentData, limit: maxDataPoints)
            self.appendHistory(&self.memoryMetricData, with: snapshot.memoryData, limit: maxDataPoints)
            self.appendHistory(&self.cpuMetricData, with: snapshot.cpuData, limit: maxDataPoints)
            self.appendHistory(&self.diskMetricData, with: snapshot.diskData, limit: maxDataPoints)

            self.lastUpdateTime = snapshot.timestamp
        }
    }

    /// Triggers immediate memory cleanup across caches and trims chart history buffers
    func triggerEmergencyPurge() {
        Task {
            await SwiftSensors.shared.triggerEmergencyPurge()
            URLCache.shared.removeAllCachedResponses()

            let compactLimit = 60
            self.thermalReadingData = Array(self.thermalReadingData.suffix(compactLimit))
            self.voltageReadingData = Array(self.voltageReadingData.suffix(compactLimit))
            self.currentReadingData = Array(self.currentReadingData.suffix(compactLimit))
            self.memoryMetricData = Array(self.memoryMetricData.suffix(compactLimit))
            self.cpuMetricData = Array(self.cpuMetricData.suffix(compactLimit))
            self.diskMetricData = Array(self.diskMetricData.suffix(compactLimit))

            self.lastPurgeTime = Date()
            self.updateSensorData()
        }
    }

    /// Performs deep scan of the Mach Virtual Address Space to find large allocations (>1MB)
    func scanLargeVMRegions() {
        guard !self.isScanningVM else { return }
        self.isScanningVM = true
        Task {
            let regions = await SwiftSensors.shared.scanLargeVMRegions(minSizeBytes: 1_048_576)
            self.largeVMRegions = regions
            self.isScanningVM = false
        }
    }

    private func appendHistory(_ target: inout [SensorData], with newItems: [SensorData], limit: Int) {
        target.append(contentsOf: newItems)
        if target.count > limit {
            target = Array(target.suffix(limit))
        }
    }

    // MARK: - Concurrent Ordered Fetch Helper

    private struct FetchedMetricsSnapshot: Sendable {
        let timestamp: Date
        let thermals: [ThermalSensorReading]
        let voltages: [VoltageSensorReading]
        let currents: [CurrentSensorReading]
        let memory: MemoryStats
        let cpu: CPUStats
        let disk: DiskStats
        let thermalState: ThermalState
        let uptimeText: String
        let vmMetrics: VMMemoryMetrics
        let threadSummary: ProcessThreadSummary

        let formattedTemperatures: [String]
        let thermalData: [SensorData]
        let formattedVoltages: [String]
        let voltageData: [SensorData]
        let formattedCurrents: [String]
        let currentData: [SensorData]
        let formattedMemoryValues: [String]
        let memoryData: [SensorData]
        let formattedCPUValues: [String]
        let cpuData: [SensorData]
        let formattedDiskValues: [String]
        let diskData: [SensorData]
    }

    private nonisolated static func fetchAllMetrics(using formatter: SensorFormatter) async -> FetchedMetricsSnapshot {
        let sensors = SwiftSensors.shared
        let now = Date()

        async let thermalsTask = sensors.getThermalSensorReadings()
        async let voltagesTask = sensors.getVoltageSensorReadings()
        async let currentsTask = sensors.getCurrentSensorReadings()
        async let memoryTask = sensors.getMemoryStats()
        async let cpuTask = sensors.getCPUStats()
        async let diskTask = sensors.getDiskStats()
        async let thermalStateTask = sensors.getThermalState()
        async let uptimeTask = sensors.getFormattedUptime()
        async let vmMetricsTask = sensors.getVMMemoryMetrics()
        async let threadSummaryTask = sensors.getThreadCPUSummary()

        let thermals = await thermalsTask
        let voltages = await voltagesTask
        let currents = await currentsTask
        let memory = await memoryTask
        let cpu = await cpuTask
        let disk = await diskTask
        let thermalState = await thermalStateTask
        let uptimeText = await uptimeTask
        let vmMetrics = await vmMetricsTask
        let threadSummary = await threadSummaryTask

        async let formattedThermalsTask = formatIndexedItems(count: thermals.count) { index in
            let sensor = thermals[index]
            let text = await formatter.formatTemperature(sensor.temperature)
            return (text, SensorData(timestamp: now, sensorName: sensor.name, value: sensor.temperature, category: "Temperature"))
        }

        async let formattedVoltagesTask = formatIndexedItems(count: voltages.count) { index in
            let sensor = voltages[index]
            let text = await formatter.formatVoltage(sensor.voltage)
            return (text, SensorData(timestamp: now, sensorName: sensor.name, value: sensor.voltage, category: "Voltage"))
        }

        async let formattedCurrentsTask = formatIndexedItems(count: currents.count) { index in
            let sensor = currents[index]
            let text = await formatter.formatCurrent(sensor.current)
            return (text, SensorData(timestamp: now, sensorName: sensor.name, value: sensor.current, category: "Current"))
        }

        async let formattedMemoryTask = formatIndexedItems(count: MemoryMetricType.allCases.count) { index in
            guard let type = MemoryMetricType(rawValue: index) else {
                return ("", SensorData(timestamp: now, sensorName: "Unknown", value: 0, category: "Memory"))
            }
            let value = Self.memoryValue(for: type, stats: memory)
            let text = await formatter.formatBytes(UInt64(max(0, value)))
            return (text, SensorData(timestamp: now, sensorName: type.name, value: value, category: "Memory"))
        }

        async let formattedCPUTask = formatIndexedItems(count: CPUMetricType.allCases.count) { index in
            guard let type = CPUMetricType(rawValue: index) else {
                return ("", SensorData(timestamp: now, sensorName: "Unknown", value: 0, category: "CPU"))
            }
            let value: Double = switch type {
            case .total: cpu.totalUsage
            case .user: cpu.userUsage
            case .system: cpu.systemUsage
            }
            let text = await formatter.formatPercentage(value)
            return (text, SensorData(timestamp: now, sensorName: type.name, value: value, category: "CPU"))
        }

        async let formattedDiskTask = formatIndexedItems(count: DiskMetricType.allCases.count) { index in
            guard let type = DiskMetricType(rawValue: index) else {
                return ("", SensorData(timestamp: now, sensorName: "Unknown", value: 0, category: "Disk"))
            }
            let bytes: UInt64 = switch type {
            case .total: disk.totalSpace
            case .used: disk.usedSpace
            case .free: disk.freeSpace
            }
            let text = await formatter.formatBytes(bytes)
            return (text, SensorData(timestamp: now, sensorName: type.name, value: Double(bytes), category: "Disk"))
        }

        let (formattedTemperatures, thermalData) = await formattedThermalsTask
        let (formattedVoltages, voltageData) = await formattedVoltagesTask
        let (formattedCurrents, currentData) = await formattedCurrentsTask
        let (formattedMemoryValues, memoryData) = await formattedMemoryTask
        let (formattedCPUValues, cpuData) = await formattedCPUTask
        let (formattedDiskValues, diskData) = await formattedDiskTask

        return FetchedMetricsSnapshot(
            timestamp: now,
            thermals: thermals,
            voltages: voltages,
            currents: currents,
            memory: memory,
            cpu: cpu,
            disk: disk,
            thermalState: thermalState,
            uptimeText: uptimeText,
            vmMetrics: vmMetrics,
            threadSummary: threadSummary,
            formattedTemperatures: formattedTemperatures,
            thermalData: thermalData,
            formattedVoltages: formattedVoltages,
            voltageData: voltageData,
            formattedCurrents: formattedCurrents,
            currentData: currentData,
            formattedMemoryValues: formattedMemoryValues,
            memoryData: memoryData,
            formattedCPUValues: formattedCPUValues,
            cpuData: cpuData,
            formattedDiskValues: formattedDiskValues,
            diskData: diskData
        )
    }

    private nonisolated static func memoryValue(for type: MemoryMetricType, stats: MemoryStats) -> Double {
        switch type {
        case .total: Double(stats.totalMemory)
        case .free: Double(stats.freeMemory)
        case .active: Double(stats.activeMemory)
        case .inactive: Double(stats.inactiveMemory)
        case .wired: Double(stats.wiredMemory)
        case .compressed: Double(stats.compressedMemory)
        case .sum: Double(stats.totalUsedMemory)
        case .appAvailable: Double(stats.appAvailableMemory)
        case .appUnavailable:
            Double(stats.totalMemory >= stats.appAvailableMemory ? stats.totalMemory - stats.appAvailableMemory : 0)
        }
    }

    private nonisolated static func formatIndexedItems(
        count: Int,
        builder: @escaping @Sendable (Int) async -> (String, SensorData)
    ) async -> ([String], [SensorData]) {
        guard count > 0 else { return ([], []) }
        return await withTaskGroup(of: (Int, String, SensorData).self) { group in
            for index in 0..<count {
                group.addTask {
                    let (formatted, data) = await builder(index)
                    return (index, formatted, data)
                }
            }

            var strings = Array(repeating: "", count: count)
            var records: [SensorData?] = Array(repeating: nil, count: count)
            for await (index, formatted, data) in group {
                strings[index] = formatted
                records[index] = data
            }
            return (strings, records.compactMap { $0 })
        }
    }
}
