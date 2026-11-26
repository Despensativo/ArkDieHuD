import Foundation
import Network
import SwiftSensors

private struct MetalHUDIngestPayload: Decodable {
    let fps: Double
    let frameTimeMs: Double?
    let vramMB: Double?
    let ramMB: Double?
    let gameName: String?
    let bundleId: String?
}

/// Lightweight local HTTP/1.1 telemetry server over LAN Wi-Fi or USB (`iproxy 8787 8787`),
/// letting users monitor live graphs and metrics on PC/Mac without showing the PiP overlay on the iPad.
actor TelemetryWebServer {
    static let shared = TelemetryWebServer()
    static let defaultPort: UInt16 = 8787
    static let defaultsKey = "SwiftSensors.remoteWebServerEnabled.v1"
    static let allowIPv6DefaultsKey = "SwiftSensors.webServerAllowIPv6.v1"
    static let allowUSBEthernetDefaultsKey = "SwiftSensors.webServerAllowUSBEthernet.v1"

    nonisolated static func loadAllowIPv6() -> Bool {
        UserDefaults.standard.bool(forKey: Self.allowIPv6DefaultsKey)
    }

    nonisolated static func loadAllowUSBEthernet() -> Bool {
        guard UserDefaults.standard.object(forKey: Self.allowUSBEthernetDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.allowUSBEthernetDefaultsKey)
    }

    private static let maxLiveRenderSamples = 900
    private let listenerQueue = DispatchQueue(label: "com.arkdiehud.telemetry.webserver", qos: .utility)
    private var listener: NWListener?
    private(set) var isListening: Bool = false
    private(set) var activePort: UInt16 = TelemetryWebServer.defaultPort
    private var latestSnapshot: TelemetrySnapshot = .placeholder
    private var liveRenderSamples: [ExternalMetalHUDMetrics] = []
    private var shouldBeRunning: Bool = false
    private var allowIPv6: Bool = TelemetryWebServer.loadAllowIPv6()
    private var allowUSBEthernet: Bool = TelemetryWebServer.loadAllowUSBEthernet()
    private var listenerGeneration: UInt64 = 0
    private var restartTask: Task<Void, Never>?

    private init() {}

    func updateSnapshot(_ snapshot: TelemetrySnapshot) {
        self.latestSnapshot = snapshot
    }

    func ensureRunningIfEnabled() {
        guard self.shouldBeRunning else { return }
        if !self.isListening || self.listener == nil {
            self.start(
                port: self.activePort,
                allowIPv6: self.allowIPv6,
                allowUSBEthernet: self.allowUSBEthernet
            )
        }
    }

    func reconfigure(allowIPv6: Bool, allowUSBEthernet: Bool) async {
        let changed = (self.allowIPv6 != allowIPv6) || (self.allowUSBEthernet != allowUSBEthernet)
        self.allowIPv6 = allowIPv6
        self.allowUSBEthernet = allowUSBEthernet
        guard changed, self.shouldBeRunning else { return }

        self.listenerGeneration &+= 1
        let gen = self.listenerGeneration
        self.restartTask?.cancel()
        self.restartTask = nil
        self.listener?.cancel()
        self.listener = nil
        self.isListening = false

        // Wait briefly for the previous NWListener socket to finish tearing down in the kernel.
        try? await Task.sleep(for: .milliseconds(120))
        guard gen == self.listenerGeneration, self.shouldBeRunning, self.listener == nil else { return }
        self.start(
            port: self.activePort,
            allowIPv6: self.allowIPv6,
            allowUSBEthernet: self.allowUSBEthernet
        )
    }

    func start(
        port: UInt16 = TelemetryWebServer.defaultPort,
        allowIPv6: Bool? = nil,
        allowUSBEthernet: Bool? = nil
    ) {
        self.shouldBeRunning = true
        self.allowIPv6 = allowIPv6 ?? Self.loadAllowIPv6()
        self.allowUSBEthernet = allowUSBEthernet ?? Self.loadAllowUSBEthernet()
        self.restartTask?.cancel()
        self.restartTask = nil
        guard self.listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        self.listenerGeneration &+= 1
        let generation = self.listenerGeneration

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if !self.allowIPv6,
               let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                // Safe default: bind strictly to IPv4 so global IPv6 cannot expose :8787 to WAN.
                ipOptions.version = .v4
            }
            if !self.allowUSBEthernet {
                params.prohibitedInterfaceTypes = [.wiredEthernet, .cellular]
            } else {
                params.prohibitedInterfaceTypes = [.cellular]
            }

            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { await self.markListening(true, port: port, generation: generation) }
                case .failed:
                    Task { await self.handleListenerFailure(port: port, generation: generation) }
                case .cancelled:
                    Task { await self.markListening(false, port: port, generation: generation) }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { connection in
                Self.acceptConnection(connection, queue: self.listenerQueue)
            }

            self.listener = newListener
            self.activePort = port
            newListener.start(queue: self.listenerQueue)
        } catch {
            self.isListening = false
            self.scheduleRestartIfNeeded(port: port)
        }
    }

    func stop() {
        self.listenerGeneration &+= 1
        self.shouldBeRunning = false
        self.restartTask?.cancel()
        self.restartTask = nil
        self.listener?.cancel()
        self.listener = nil
        self.isListening = false
    }

    private func markListening(_ active: Bool, port: UInt16, generation: UInt64) {
        guard generation == self.listenerGeneration else { return }
        self.isListening = active
        self.activePort = port
    }

    private func handleListenerFailure(port: UInt16, generation: UInt64) {
        guard generation == self.listenerGeneration else { return }
        self.listener?.cancel()
        self.listener = nil
        self.isListening = false
        self.scheduleRestartIfNeeded(port: port)
    }

    private func scheduleRestartIfNeeded(port: UInt16) {
        guard self.shouldBeRunning, self.restartTask == nil else { return }
        self.restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.performScheduledRestart(port: port)
        }
    }

    private func performScheduledRestart(port: UInt16) {
        self.restartTask = nil
        if self.shouldBeRunning && self.listener == nil {
            self.start(port: port)
        }
    }

    // MARK: - Connection & HTTP/1.1 Routing

    private nonisolated static func acceptConnection(_ connection: NWConnection, queue: DispatchQueue) {
        connection.start(queue: queue)
        Self.receiveFullHTTPRequest(connection, buffer: Data())
    }

    private nonisolated static func receiveFullHTTPRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            guard error == nil else {
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }
            guard !accumulated.isEmpty else {
                connection.cancel()
                return
            }

            if !isComplete, !Self.isHTTPRequestComplete(accumulated), accumulated.count < 65_536 {
                Self.receiveFullHTTPRequest(connection, buffer: accumulated)
                return
            }

            let parsed = Self.parseHTTPRequest(from: accumulated)
            Task {
                let responseBytes = await TelemetryWebServer.shared.buildHTTPResponse(
                    method: parsed.method,
                    forTarget: parsed.target,
                    hostHeader: parsed.hostHeader,
                    body: parsed.body
                )
                connection.send(content: responseBytes, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private nonisolated static func isHTTPRequestComplete(_ data: Data) -> Bool {
        let crlfSep = Data("\r\n\r\n".utf8)
        let lfSep = Data("\n\n".utf8)
        let sepRange = data.range(of: crlfSep) ?? data.range(of: lfSep)
        guard let sepRange else { return false }
        let headerData = data[..<sepRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return true }
        let contentLength = Self.extractContentLength(from: headerText)
        let bodyCount = data.count - sepRange.upperBound
        return bodyCount >= contentLength
    }

    private nonisolated static func extractContentLength(from headerText: String) -> Int {
        for rawLine in headerText.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst(15).trimmingCharacters(in: .whitespacesAndNewlines)
                return max(0, Int(value) ?? 0)
            }
        }
        return 0
    }

    private nonisolated static func parseHTTPRequest(
        from data: Data
    ) -> (method: String, target: String, hostHeader: String?, body: Data) {
        let crlfSep = Data("\r\n\r\n".utf8)
        let lfSep = Data("\n\n".utf8)
        let sepRange = data.range(of: crlfSep) ?? data.range(of: lfSep)
        let headerData = sepRange.map { Data(data[..<$0.lowerBound]) } ?? data
        let bodyData = sepRange.map { Data(data[$0.upperBound...]) } ?? Data()
        let headerText = String(data: headerData, encoding: .utf8) ?? ""

        let firstLine = headerText.split(separator: "\r\n", maxSplits: 1).first
            ?? headerText.split(separator: "\n", maxSplits: 1).first
            ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.first.map { String($0).uppercased() } ?? "GET"
        let target = parts.count >= 2 ? String(parts[1]) : "/"
        let hostHeader = Self.extractRequestHost(from: headerText)
        return (method, target, hostHeader, bodyData)
    }

    private nonisolated static func extractRequestHost(from request: String) -> String? {
        for rawLine in request.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("host:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func buildHTTPResponse(
        method: String,
        forTarget target: String,
        hostHeader: String?,
        body requestBody: Data
    ) async -> Data {
        if method == "OPTIONS" {
            return Self.httpResponse(
                status: "204 No Content",
                contentType: "text/plain; charset=utf-8",
                extraHeaders: [
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type"
                ],
                body: Data()
            )
        }

        let components = URLComponents(string: "http://localhost" + target)
        let path = components?.path ?? "/"
        let windowSeconds = components?.queryItems?
            .first(where: { $0.name == "window" })?
            .value
            .flatMap(Double.init) ?? 3600.0

        switch path {
        case "/api/metal-hud":
            guard method == "POST" else {
                return Self.httpResponse(
                    status: "405 Method Not Allowed",
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"error\":\"POST required\"}".utf8)
                )
            }
            guard let payload = try? JSONDecoder().decode(MetalHUDIngestPayload.self, from: requestBody),
                  payload.fps.isFinite, payload.fps >= 0, payload.fps <= 240 else {
                return Self.httpResponse(
                    status: "400 Bad Request",
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"error\":\"invalid payload\"}".utf8)
                )
            }
            let computedFrameMs = payload.frameTimeMs ?? (payload.fps > 0 ? (1000.0 / payload.fps) : 0.0)
            let metrics = ExternalMetalHUDMetrics(
                fps: payload.fps,
                frameTimeMs: computedFrameMs,
                vramMB: payload.vramMB,
                ramMB: payload.ramMB,
                gameName: payload.gameName,
                bundleId: payload.bundleId,
                updatedAt: Date()
            )
            await ExternalMetalHUDStore.shared.update(metrics)
            self.latestSnapshot = self.latestSnapshot.with(metalHUD: metrics)
            self.liveRenderSamples.append(metrics)
            if self.liveRenderSamples.count > Self.maxLiveRenderSamples {
                self.liveRenderSamples.removeFirst(self.liveRenderSamples.count - Self.maxLiveRenderSamples)
            }
            return Self.httpResponse(
                status: "200 OK",
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":true}".utf8)
            )
        case "/api/render-stream":
            let cutoff = Date().addingTimeInterval(-max(60.0, windowSeconds))
            let filtered = self.liveRenderSamples.filter { $0.updatedAt >= cutoff }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let body = (try? encoder.encode(filtered)) ?? Data("[]".utf8)
            return Self.httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)
        case "/", "/index.html":
            let body = Data(TelemetryWebDashboardHTML.indexHTML.utf8)
            return Self.httpResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: body)

        case "/api/snapshot":
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let body = (try? encoder.encode(self.latestSnapshot)) ?? Data("{}".utf8)
            return Self.httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)

        case "/api/history":
            var buckets = await TelemetryLogStore.shared.querySeries(windowSeconds: windowSeconds, maxPoints: 200)
            if buckets.isEmpty {
                let samples = await SwiftSensors.shared.getNetworkProbeHistory(limit: 180)
                buckets = samples.map { sample in
                    TelemetryLogBucket(
                        id: Int64(sample.sequence),
                        timestamp: sample.timestamp,
                        maxCPUTemp: nil,
                        maxGPUTemp: nil,
                        avgWatts: nil,
                        avgRAMUsedGB: self.latestSnapshot.memoryUsedGB,
                        avgCPUPercent: self.latestSnapshot.cpuTotalPercent,
                        maxPingMs: sample.targetRTTMs,
                        maxUDPMs: sample.udpRTTMs,
                        maxGatewayMs: sample.gatewayRTTMs,
                        dropCount: sample.isTargetLost ? 1 : 0,
                        udpDropCount: sample.isUDPLost ? 1 : 0,
                        sampleCount: 1,
                        avgGameFPS: self.latestSnapshot.gameFPS,
                        minGameFPS: self.latestSnapshot.gameFPS,
                        avgGameVRAMMB: self.latestSnapshot.gameVRAMMB,
                        avgGameRAMMB: self.latestSnapshot.gameRAMMB
                    )
                }
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let body = (try? encoder.encode(buckets)) ?? Data("[]".utf8)
            return Self.httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)

        case "/api/incidents":
            let events = Array(await SwiftSensors.shared.getNetworkIncidents().reversed().prefix(60))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let body = (try? encoder.encode(events)) ?? Data("[]".utf8)
            return Self.httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)

        case "/api/csv":
            if let fileURL = await TelemetryLogStore.shared.exportUnifiedCSVFile(windowSeconds: windowSeconds),
               let fileData = try? Data(contentsOf: fileURL),
               !fileData.isEmpty {
                return Self.httpResponse(
                    status: "200 OK",
                    contentType: "text/csv; charset=utf-8",
                    extraHeaders: ["Content-Disposition": "attachment; filename=\"ArkDieHuD_Telemetria.csv\""],
                    body: fileData
                )
            }
            let fallbackCSV = await SwiftSensors.shared.exportNetworkDiagnosticsCSV()
            return Self.httpResponse(
                status: "200 OK",
                contentType: "text/csv; charset=utf-8",
                extraHeaders: ["Content-Disposition": "attachment; filename=\"ArkDieHuD_Rede.csv\""],
                body: Data(fallbackCSV.utf8)
            )

        case "/download/metal-hud-mac.command":
            return Self.httpResponse(
                status: "200 OK",
                contentType: "text/plain; charset=utf-8",
                extraHeaders: ["Content-Disposition": "attachment; filename=\"ArkDieHuD_Metal_HUD_Mac.command\""],
                body: Data(MetalHUDLauncherPayloads.macCommandScript.utf8)
            )

        case "/download/metal-hud-windows.bat":
            let fallbackIPv6 = self.allowIPv6
                ? self.latestSnapshot.network.route.localIPv6.map { "[\($0)]:\(self.activePort)" }
                : nil
            let fallbackHost = self.latestSnapshot.network.route.localIPv4
                .map { "\($0):\(self.activePort)" }
                ?? fallbackIPv6
                ?? "127.0.0.1:\(self.activePort)"
            let effectiveHost = hostHeader ?? fallbackHost
            let elementsParam = components?.queryItems?.first(where: { $0.name == "elements" })?.value
            let alignParam = components?.queryItems?.first(where: { $0.name == "align" })?.value
            let scaleParam = components?.queryItems?.first(where: { $0.name == "scale" })?.value
            let opacityParam = components?.queryItems?.first(where: { $0.name == "opacity" })?.value
            let streamWebParam = components?.queryItems?.first(where: { $0.name == "streamWeb" })?.value
            let streamWebURL = (streamWebParam == "1" || streamWebParam == "true")
                ? "http://\(effectiveHost)"
                : nil
            let script = MetalHUDLauncherPayloads.windowsBatchScript(
                serverHost: effectiveHost,
                elements: elementsParam,
                align: alignParam,
                scale: scaleParam,
                streamWebURL: streamWebURL,
                opacity: opacityParam
            )
            return Self.httpResponse(
                status: "200 OK",
                contentType: "application/octet-stream",
                extraHeaders: ["Content-Disposition": "attachment; filename=\"ArkDieHuD_Metal_HUD_Windows.bat\""],
                body: Data(script.utf8)
            )

        case "/download/arkdiehud_metal_hud.py":
            return Self.httpResponse(
                status: "200 OK",
                contentType: "text/x-python; charset=utf-8",
                extraHeaders: ["Content-Disposition": "attachment; filename=\"arkdiehud_metal_hud.py\""],
                body: Data(MetalHUDLauncherPayloads.crossPlatformPythonScript.utf8)
            )

        default:
            return Self.httpResponse(
                status: "404 Not Found",
                contentType: "text/plain; charset=utf-8",
                body: Data("Not Found".utf8)
            )
        }
    }

    private nonisolated static func httpResponse(
        status: String,
        contentType: String,
        extraHeaders: [String: String] = [:],
        body: Data
    ) -> Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        for (key, value) in extraHeaders {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"

        var payload = Data(header.utf8)
        payload.append(body)
        return payload
    }
}
