import Foundation

/// Persistent user preferences controlling which telemetry metrics and dashboard/Slide Over
/// sections are rendered across the main dashboard, Slide Over drawer, and floating PiP HUD.
struct TelemetryVisibilityConfig: Codable, Sendable, Equatable {
    private static let defaultsKey = "SwiftSensors.telemetryVisibility.v1"

    // MARK: - Hardware & Energy Metrics
    var showCPUTemp: Bool = true
    var showGPUTemp: Bool = true
    var showCPULoad: Bool = false
    var showRAM: Bool = true
    var showPowerWatts: Bool = true
    var showBattery: Bool = false
    var showThermalState: Bool = false

    // MARK: - Network Metrics
    var showPing: Bool = true
    var showUDPPing: Bool = false
    var showGatewayPing: Bool = false
    var showJitter: Bool = false
    var showPacketLoss: Bool = true

    // MARK: - Dashboard Sections (ContentView)
    var showDashboardLiveStrip: Bool = true
    var showDashboardPiPCard: Bool = true
    var showDashboardSensorsGrid: Bool = true
    var hiddenDashboardSections: Set<String> = []

    // MARK: - Slide Over Sections (SlideOverHUDView)
    var showSlideOverHeroSLA: Bool = true
    var showSlideOverThermals: Bool = true
    var showSlideOverNetworkCard: Bool = true
    var showSlideOverSystemCard: Bool = true
    var showSlideOverGestureHint: Bool = true

    var enabledMetricCount: Int {
        let flags = [
            self.showCPUTemp,
            self.showGPUTemp,
            self.showCPULoad,
            self.showRAM,
            self.showPowerWatts,
            self.showBattery,
            self.showThermalState,
            self.showPing,
            self.showUDPPing,
            self.showGatewayPing,
            self.showJitter,
            self.showPacketLoss,
        ]
        return flags.count(where: { $0 })
    }

    var hasAnyMetricEnabled: Bool {
        self.enabledMetricCount > 0
    }

    var hasAnyHardwareMetric: Bool {
        self.showCPUTemp
            || self.showGPUTemp
            || self.showCPULoad
            || self.showRAM
            || self.showPowerWatts
            || self.showBattery
            || self.showThermalState
    }

    var hasAnyNetworkMetric: Bool {
        self.showPing
            || self.showUDPPing
            || self.showGatewayPing
            || self.showJitter
            || self.showPacketLoss
    }

    func isDashboardSectionVisible(_ section: SensorSection) -> Bool {
        !self.hiddenDashboardSections.contains(section.rawValue)
    }

    mutating func setDashboardSection(_ section: SensorSection, visible: Bool) {
        if visible {
            self.hiddenDashboardSections.remove(section.rawValue)
        } else {
            self.hiddenDashboardSections.insert(section.rawValue)
        }
    }

    // MARK: - Presets

    static let gamerDefault = TelemetryVisibilityConfig()

    static let networkCompetitive = TelemetryVisibilityConfig(
        showCPUTemp: true,
        showGPUTemp: false,
        showCPULoad: false,
        showRAM: false,
        showPowerWatts: false,
        showBattery: false,
        showThermalState: false,
        showPing: true,
        showUDPPing: true,
        showGatewayPing: true,
        showJitter: true,
        showPacketLoss: true
    )

    static let ultraMinimal = TelemetryVisibilityConfig(
        showCPUTemp: true,
        showGPUTemp: false,
        showCPULoad: false,
        showRAM: false,
        showPowerWatts: false,
        showBattery: false,
        showThermalState: false,
        showPing: true,
        showUDPPing: false,
        showGatewayPing: false,
        showJitter: false,
        showPacketLoss: true
    )

    static let allMetrics = TelemetryVisibilityConfig(
        showCPUTemp: true,
        showGPUTemp: true,
        showCPULoad: true,
        showRAM: true,
        showPowerWatts: true,
        showBattery: true,
        showThermalState: true,
        showPing: true,
        showUDPPing: true,
        showGatewayPing: true,
        showJitter: true,
        showPacketLoss: true
    )

    // MARK: - Persistence

    static func load() -> TelemetryVisibilityConfig {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(TelemetryVisibilityConfig.self, from: data) else {
            return .gamerDefault
        }
        return decoded
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        }
    }
}
