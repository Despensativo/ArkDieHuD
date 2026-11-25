import Foundation
import Network
import SwiftSensors

/// Lightweight local HTTP/1.1 telemetry server over LAN Wi-Fi or USB (`iproxy 8787 8787`),
/// letting users monitor live graphs and metrics on PC/Mac without showing the PiP overlay on the iPad.
actor TelemetryWebServer {
    static let shared = TelemetryWebServer()
    static let defaultPort: UInt16 = 8787
    static let defaultsKey = "SwiftSensors.remoteWebServerEnabled.v1"

    private let listenerQueue = DispatchQueue(label: "com.arkdiehud.telemetry.webserver", qos: .utility)
    private var listener: NWListener?
    private(set) var isListening: Bool = false
    private(set) var activePort: UInt16 = TelemetryWebServer.defaultPort
    private var latestSnapshot: TelemetrySnapshot = .placeholder
    private var shouldBeRunning: Bool = false
    private var restartTask: Task<Void, Never>?

    private init() {}

    func updateSnapshot(_ snapshot: TelemetrySnapshot) {
        self.latestSnapshot = snapshot
    }

    func ensureRunningIfEnabled() {
        guard self.shouldBeRunning else { return }
        if !self.isListening || self.listener == nil {
            self.start(port: self.activePort)
        }
    }

    func start(port: UInt16 = TelemetryWebServer.defaultPort) {
        self.shouldBeRunning = true
        self.restartTask?.cancel()
        self.restartTask = nil
        guard self.listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { await self.markListening(true, port: port) }
                case .failed:
                    Task { await self.handleListenerFailure(port: port) }
                case .cancelled:
                    Task { await self.markListening(false, port: port) }
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
        self.shouldBeRunning = false
        self.restartTask?.cancel()
        self.restartTask = nil
        self.listener?.cancel()
        self.listener = nil
        self.isListening = false
    }

    private func markListening(_ active: Bool, port: UInt16) {
        self.isListening = active
        self.activePort = port
    }

    private func handleListenerFailure(port: UInt16) {
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            guard error == nil, let data, let requestText = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let targetPath = Self.extractRequestTarget(from: requestText)
            let requestHost = Self.extractRequestHost(from: requestText)
            Task {
                let responseBytes = await TelemetryWebServer.shared.buildHTTPResponse(
                    forTarget: targetPath,
                    hostHeader: requestHost
                )
                connection.send(content: responseBytes, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private nonisolated static func extractRequestTarget(from request: String) -> String {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first
            ?? request.split(separator: "\n", maxSplits: 1).first else {
            return "/"
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
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

    private func buildHTTPResponse(forTarget target: String, hostHeader: String?) async -> Data {
        let components = URLComponents(string: "http://localhost" + target)
        let path = components?.path ?? "/"
        let windowSeconds = components?.queryItems?
            .first(where: { $0.name == "window" })?
            .value
            .flatMap(Double.init) ?? 3600.0

        switch path {
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
                        sampleCount: 1
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
            let fallbackHost = self.latestSnapshot.network.route.localIPv4
                .map { "\($0):\(self.activePort)" } ?? "127.0.0.1:\(self.activePort)"
            let effectiveHost = hostHeader ?? fallbackHost
            let script = MetalHUDLauncherPayloads.windowsBatchScript(serverHost: effectiveHost)
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
