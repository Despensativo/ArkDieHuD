import Foundation

/// Live frame-rate and GPU/process memory metrics bridged from Apple's Metal
/// Performance HUD (`MTL_HUD_LOG_ENABLED=1`) via the `:8787` web server.
struct ExternalMetalHUDMetrics: Codable, Sendable, Equatable {
    let fps: Double
    let frameTimeMs: Double
    let vramMB: Double?
    let ramMB: Double?
    let gameName: String?
    let bundleId: String?
    let updatedAt: Date
}

/// Actor holding the most recent active game FPS reading, automatically
/// expiring stale entries once a game closes.
actor ExternalMetalHUDStore {
    static let shared = ExternalMetalHUDStore()
    static let staleTimeoutSeconds: TimeInterval = 6.0

    private var latest: ExternalMetalHUDMetrics?

    private init() {}

    func update(_ metrics: ExternalMetalHUDMetrics) {
        self.latest = metrics
    }

    func current(now: Date = Date()) -> ExternalMetalHUDMetrics? {
        guard let latest else { return nil }
        guard now.timeIntervalSince(latest.updatedAt) <= Self.staleTimeoutSeconds else {
            self.latest = nil
            return nil
        }
        return latest
    }
}
