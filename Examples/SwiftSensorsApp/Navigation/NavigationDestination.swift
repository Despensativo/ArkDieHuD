import Foundation

/// Defines all possible navigation destinations in the app
enum NavigationDestination: Hashable {
    /// Detail view for a specific sensor
    case sensorDetail(sensorName: String)

    /// Specific section detail+chart view
    case sectionDetail(section: SensorSection)

    /// Full-featured Slide Over HUD view
    case slideOver

    /// Dedicated dual-probe network diagnostics, latency chart, and packet loss log
    case networkDiagnostics

    /// Persistent 24-hour SQLite WAL telemetry history & unified CSV export
    case telemetryLogs
}

/// Represents different sensor sections in the app
enum SensorSection: String, Hashable, CaseIterable {
    case network = "Rede e Log de Pacotes"
    case telemetryLogs = "Logs e Telemetria 24h"
    case performance = "Performance & Kernel SLA"
    case thermal = "Thermal Sensors"
    case voltage = "Voltage Sensors"
    case current = "Current Sensors"
    case memory = "Memory"
    case cpu = "CPU"
    case disk = "Disk"
    case system = "System"
}
