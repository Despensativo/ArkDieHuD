import AVFoundation
import AVKit
import Foundation
import Observation
import OSLog
import SwiftSensors
import UIKit

/// Controls the floating Picture-in-Picture (PiP) telemetry HUD so real-time sensor
/// metrics can float over any app or game on iPadOS.
@MainActor
@Observable
final class PiPHUDController: NSObject {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.cristianark.SwiftSensorsApp", category: "PiPHUD")
    #endif

    private(set) var displayLayer: AVSampleBufferDisplayLayer?

    var layoutMode: HUDLayoutMode = .gamerBar {
        didSet {
            guard oldValue != layoutMode else { return }
            displayLayer?.flush()
            renderCurrentSnapshot()
            pipController?.invalidatePlaybackState()
        }
    }

    var autoStartOnBackground: Bool = true {
        didSet {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = autoStartOnBackground
        }
    }

    var isRecordingLogs: Bool = UserDefaults.standard.object(forKey: TelemetryLogStore.defaultsKey) as? Bool ?? true {
        didSet {
            guard oldValue != self.isRecordingLogs else { return }
            let enabled = self.isRecordingLogs
            Task {
                await TelemetryLogStore.shared.setRecordingEnabled(enabled)
            }
        }
    }

    var isRemoteWebServerEnabled: Bool = UserDefaults.standard.bool(forKey: TelemetryWebServer.defaultsKey) {
        didSet {
            guard oldValue != self.isRemoteWebServerEnabled else { return }
            let enabled = self.isRemoteWebServerEnabled
            UserDefaults.standard.set(enabled, forKey: TelemetryWebServer.defaultsKey)
            Task {
                if enabled {
                    await TelemetryWebServer.shared.start(port: TelemetryWebServer.defaultPort)
                } else {
                    await TelemetryWebServer.shared.stop()
                }
            }
            self.updateBackgroundKeepAlive()
            self.displayLayer?.flush()
            self.renderCurrentSnapshot()
            self.pipController?.invalidatePlaybackState()
            if !self.isPiPActive {
                self.statusText = enabled
                    ? L10n.tr("PC/Mac server active without PiP")
                    : L10n.tr("Ready to overlay on screen")
            }
        }
    }

    var useStealthPiPForPC: Bool = UserDefaults.standard.object(forKey: "SwiftSensors.pcStealthPiP.v1") as? Bool ?? true {
        didSet {
            guard oldValue != self.useStealthPiPForPC else { return }
            UserDefaults.standard.set(self.useStealthPiPForPC, forKey: "SwiftSensors.pcStealthPiP.v1")
            self.displayLayer?.flush()
            self.renderCurrentSnapshot()
            self.pipController?.invalidatePlaybackState()
        }
    }

    var isPCStealthPiPActive: Bool {
        self.isRemoteWebServerEnabled && self.useStealthPiPForPC
    }

    var visibilityConfig: TelemetryVisibilityConfig = TelemetryVisibilityConfig.load() {
        didSet {
            guard oldValue != self.visibilityConfig else { return }
            self.visibilityConfig.save()
            if self.visibilityConfig.showUDPPing && !oldValue.showUDPPing {
                Task {
                    await SwiftSensors.shared.ensureNetworkUDPProbingEnabled()
                }
            }
            self.displayLayer?.flush()
            self.renderCurrentSnapshot()
            self.pipController?.invalidatePlaybackState()
        }
    }

    var currentCanvasSize: CGSize {
        if self.isPCStealthPiPActive {
            return HUDMetricBuilder.pcStealthCanvasSize
        }
        return HUDMetricBuilder.canvasSize(for: self.layoutMode, config: self.visibilityConfig)
    }

    var currentCanvasAspectRatio: CGFloat {
        let size = self.currentCanvasSize
        return size.width / max(1, size.height)
    }

    private(set) var isPiPActive: Bool = false
    private(set) var isPiPPossible: Bool = false
    private(set) var isSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var latestSnapshot: TelemetrySnapshot = .placeholder
    private(set) var statusText: String = L10n.tr("Ready to overlay on screen")

    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var activeObservation: NSKeyValueObservation?
    private var silentPlayer: AVAudioPlayer?
    private var backgroundPollTask: Task<Void, Never>?
    private var pulseOn: Bool = true
    private var timebase: CMTimebase?
    private weak var hostView: SampleBufferHostView?
    private var isAppInBackground: Bool = false
    private var audioInterruptionTaskID: UIBackgroundTaskIdentifier = .invalid
    private var notificationObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        configureAudioSession()
        setupTimebase()
        setupLifecycleAndAudioObservers()
        if self.visibilityConfig.showUDPPing {
            Task {
                await SwiftSensors.shared.ensureNetworkUDPProbingEnabled()
            }
        }
        if self.isRemoteWebServerEnabled {
            Task {
                await TelemetryWebServer.shared.start(port: TelemetryWebServer.defaultPort)
            }
            self.startSilentKeepAlive()
            self.statusText = L10n.tr("PC/Mac server active without PiP")
        }
        startPollingLoop()
    }

    private static func logDebug(_ message: String) {
        #if DEBUG
        Self.logger.debug("\(message, privacy: .public)")
        #endif
    }

    /// Attaches the backing AVSampleBufferDisplayLayer from SampleBufferHostView (UIView subclass)
    /// This gives AVKit the direct link to the window hierarchy needed for isPictureInPicturePossible.
    func attachHostView(_ view: SampleBufferHostView) {
        self.hostView = view
        let layer = view.sampleBufferDisplayLayer
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor

        if let tb = timebase {
            layer.controlTimebase = tb
        }

        self.displayLayer = layer
        setupPiPController(for: layer)
        renderCurrentSnapshot()
    }

    /// Sets up a running CMTimebase synchronized to host clock.
    private func setupTimebase() {
        var tb: CMTimebase?
        let clock = CMClockGetHostTimeClock()
        let status = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: clock,
            timebaseOut: &tb
        )
        guard status == noErr, let tb = tb else {
            Self.logDebug("Failed to create CMTimebase: \(status)")
            return
        }

        let now = CMClockGetTime(clock)
        CMTimebaseSetTime(tb, time: now)
        CMTimebaseSetRate(tb, rate: 1.0)
        self.timebase = tb
        Self.logDebug("CMTimebase configured (rate=1.0)")
    }

    func prepareAudioAndStartPiP() {
        configureAudioSession()
        startSilentKeepAlive()

        // Keep timebase active & advance time if needed
        if let tb = timebase {
            let clock = CMClockGetHostTimeClock()
            CMTimebaseSetRate(tb, rate: 1.0)
            let now = CMClockGetTime(clock)
            let tbTime = CMTimebaseGetTime(tb)
            if abs(CMTimeGetSeconds(CMTimeSubtract(now, tbTime))) > 2.0 {
                CMTimebaseSetTime(tb, time: now)
            }
        }

        renderCurrentSnapshot()

        guard let pip = pipController else {
            statusText = L10n.tr("PiP not supported on this device")
            Self.logDebug("pipController is nil")
            return
        }

        Self.logDebug("prepareAudioAndStartPiP isPossible=\(pip.isPictureInPicturePossible) isActive=\(pip.isPictureInPictureActive)")

        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
            return
        }

        pip.invalidatePlaybackState()

        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            statusText = L10n.tr("Floating HUD active over other apps")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let pip = self.pipController else { return }
            Self.logDebug("after 150ms delay isPossible=\(pip.isPictureInPicturePossible) isActive=\(pip.isPictureInPictureActive)")
            if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
                self.statusText = L10n.tr("Floating HUD active over other apps")
            } else {
                pip.startPictureInPicture()
                self.statusText = L10n.tr("HUD started")
            }
        }
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
        self.updateBackgroundKeepAlive()
    }

    private func updateBackgroundKeepAlive() {
        if self.isPiPActive || self.isRemoteWebServerEnabled {
            self.startSilentKeepAlive()
        } else {
            self.stopSilentKeepAlive()
        }
    }

    private func setupPiPController(for layer: AVSampleBufferDisplayLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isSupported = false
            statusText = L10n.tr("Picture-in-Picture unavailable on this device")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Configure as linear live stream so iOS treats it as live broadcast
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = autoStartOnBackground

        // Note: controlsStyle=2 disables touch interaction and breaks window dragging on iPadOS.
        // We use controlsStyle=1 to hide skip/scrub controls while preserving full drag & snap gestures.
        controller.setValue(1, forKey: "controlsStyle")

        self.pipController = controller

        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                let possible = ctrl.isPictureInPicturePossible
                self?.isPiPPossible = possible
                Self.logDebug("isPictureInPicturePossible changed to: \(possible)")
            }
        }

        activeObservation = controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] ctrl, _ in
            Task { @MainActor in
                let active = ctrl.isPictureInPictureActive
                self?.isPiPActive = active
                Self.logDebug("isPictureInPictureActive changed to: \(active)")
                if active {
                    self?.updateBackgroundKeepAlive()
                    self?.statusText = L10n.tr("Floating HUD active — you can switch apps")
                } else {
                    self?.updateBackgroundKeepAlive()
                    self?.statusText = (self?.isRemoteWebServerEnabled == true)
                        ? L10n.tr("PC/Mac server active without PiP")
                        : L10n.tr("Ready to overlay on screen")
                }
            }
        }
    }

    private func startPollingLoop() {
        backgroundPollTask?.cancel()
        backgroundPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await TelemetrySnapshot.captureLive()
                await TelemetryLogStore.shared.record(snapshot)
                await TelemetryWebServer.shared.updateSnapshot(snapshot)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.latestSnapshot = snapshot
                    self.pulseOn.toggle()
                    self.renderCurrentSnapshot()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func renderCurrentSnapshot() {
        // Zero-Render in background when PiP is closed to save RAM/CPU and reduce Jetsam pressure
        if self.isAppInBackground && !self.isPiPActive {
            return
        }
        guard let layer = displayLayer else { return }
        if layer.status == .failed {
            Self.logDebug("displayLayer failed: \(String(describing: layer.error)), flushing")
            layer.flush()
        }
        guard let sampleBuffer = HUDFrameRenderer.makeSampleBuffer(
            snapshot: latestSnapshot,
            mode: layoutMode,
            config: visibilityConfig,
            pulseOn: pulseOn,
            pcStealthMode: self.isPCStealthPiPActive
        ) else {
            return
        }
        layer.enqueue(sampleBuffer)
    }

    // MARK: - Auto-Heal Observers (Audio Interruption, Media Reset, Background Zero-Render)

    private func setupLifecycleAndAudioObservers() {
        let center = NotificationCenter.default

        let interruptionObs = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleAudioInterruption(rawType: rawType)
            }
        }

        let mediaResetObs = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.silentPlayer = nil
                self?.updateBackgroundKeepAlive()
            }
        }

        let didBgObs = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAppInBackground = true
            }
        }

        let willFgObs = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAppInBackground = false
                self?.updateBackgroundKeepAlive()
                self?.renderCurrentSnapshot()
                await TelemetryWebServer.shared.ensureRunningIfEnabled()
            }
        }

        self.notificationObservers = [interruptionObs, mediaResetObs, didBgObs, willFgObs]
    }

    private func handleAudioInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if (self.isPiPActive || self.isRemoteWebServerEnabled) && self.audioInterruptionTaskID == .invalid {
                self.audioInterruptionTaskID = UIApplication.shared.beginBackgroundTask(withName: "ArkDieKeepAliveHeal") { [weak self] in
                    Task { @MainActor in
                        self?.endAudioInterruptionBackgroundTask()
                    }
                }
            }
        case .ended:
            self.updateBackgroundKeepAlive()
            self.endAudioInterruptionBackgroundTask()
        @unknown default:
            break
        }
    }

    private func endAudioInterruptionBackgroundTask() {
        if self.audioInterruptionTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(self.audioInterruptionTaskID)
            self.audioInterruptionTaskID = .invalid
        }
    }

    // MARK: - Background Keep-Alive (Silent Audio, Mixes with Games/Music)

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Self.logDebug("AVAudioSession error: \(error.localizedDescription)")
        }
    }

    private func startSilentKeepAlive() {
        configureAudioSession()
        if let player = silentPlayer {
            if !player.isPlaying {
                player.play()
            }
            return
        }
        guard let wavData = Self.makeSilentWAVData(durationSeconds: 1.0, sampleRate: 8000) else {
            return
        }
        do {
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            player.play()
            self.silentPlayer = player
        } catch {
            // Ignore audio init errors
        }
    }

    private func stopSilentKeepAlive() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    /// Builds a minimal valid 1-second silent PCM WAV buffer in memory (16 KB)
    private static func makeSilentWAVData(durationSeconds: Double, sampleRate: UInt32) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = UInt32(Double(sampleRate) * durationSeconds)
        let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: chunkSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1)) // PCM
        data.append(littleEndian: numChannels)
        data.append(littleEndian: sampleRate)
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPHUDController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.startSilentKeepAlive()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPiPActive = true
            self.statusText = L10n.tr("Floating HUD active — you can switch apps")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isPiPActive = false
            self.updateBackgroundKeepAlive()
            self.statusText = L10n.fmt("Failed to start PiP: %@", error.localizedDescription)
            Self.logDebug("failedToStartPictureInPictureWithError: \(error.localizedDescription)")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPiPActive = false
            self.updateBackgroundKeepAlive()
            self.statusText = self.isRemoteWebServerEnabled
                ? L10n.tr("PC/Mac server active without PiP")
                : L10n.tr("Ready to overlay on screen")
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPHUDController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // Live telemetry stream stays active
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Positive infinity tells iOS this is an open-ended live broadcast
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        Task { @MainActor in
            self.renderCurrentSnapshot()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
