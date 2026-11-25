import Foundation
import SQLite3

struct TelemetryLogBucket: Identifiable, Codable, Sendable {
    let id: Int64
    let timestamp: Date
    let maxCPUTemp: Double?
    let maxGPUTemp: Double?
    let avgWatts: Double?
    let avgRAMUsedGB: Double
    let avgCPUPercent: Double
    let maxPingMs: Double?
    let maxUDPMs: Double?
    let maxGatewayMs: Double?
    let dropCount: Int
    let udpDropCount: Int
    let sampleCount: Int
    let avgGameFPS: Double?
    let minGameFPS: Double?
    let avgGameVRAMMB: Double?
    let avgGameRAMMB: Double?
}

struct TelemetryLogStatus: Sendable {
    let isRecording: Bool
    let sampleCount: Int
    let pendingCount: Int
    let oldestTimestamp: Date?
    let newestTimestamp: Date?
    let diskSizeBytes: Int64
    let totalDrops: Int
    let maxCPUTemp: Double?
    let maxGPUTemp: Double?
    let maxWatts: Double?
    let databasePath: String

    static let empty = TelemetryLogStatus(
        isRecording: true,
        sampleCount: 0,
        pendingCount: 0,
        oldestTimestamp: nil,
        newestTimestamp: nil,
        diskSizeBytes: 0,
        totalDrops: 0,
        maxCPUTemp: nil,
        maxGPUTemp: nil,
        maxWatts: nil,
        databasePath: ""
    )
}

/// Persistent SQLite WAL telemetry recorder keeping up to 24 hours of 1Hz hardware + network
/// snapshots with batched writes (every 15s) and automatic retention pruning.
actor TelemetryLogStore {
    static let shared = TelemetryLogStore()

    static let retentionSeconds: TimeInterval = 86_400
    static let flushBatchSize: Int = 15
    static let pruneIntervalSeconds: TimeInterval = 300
    static let defaultsKey = "SwiftSensors.telemetryLoggingEnabled.v1"

    private var db: OpaquePointer?
    private var pendingBuffer: [TelemetrySnapshot] = []
    private var isRecordingEnabled: Bool
    private var lastPruneDate: Date = .distantPast
    private let databaseURL: URL

    private init() {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.databaseURL = docsURL.appendingPathComponent("SwiftSensors_Telemetry_24h.sqlite")
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            self.isRecordingEnabled = true
        } else {
            self.isRecordingEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        }
    }

    func getRecordingEnabled() -> Bool {
        self.isRecordingEnabled
    }

    func setRecordingEnabled(_ enabled: Bool) {
        self.isRecordingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
        if !enabled {
            self.flushNow()
        }
    }

    func record(_ snapshot: TelemetrySnapshot) {
        guard self.isRecordingEnabled else { return }
        self.pendingBuffer.append(snapshot)
        if self.pendingBuffer.count >= Self.flushBatchSize {
            self.flushNow()
        }
    }

    func flushNow() {
        guard !self.pendingBuffer.isEmpty else { return }
        guard let db = self.openDatabaseIfNeeded() else { return }

        let batch = self.pendingBuffer
        self.pendingBuffer.removeAll(keepingCapacity: true)

        let insertSQL = """
            INSERT OR REPLACE INTO telemetry_samples (
                ts, cpu_temp, gpu_temp, peak_temp, cpu_pct, ram_used_gb, ram_pct,
                watts, battery_pct, is_charging, thermal_state,
                ping_ms, icmp_ms, udp_ms, tcp_ms, gateway_ms, jitter_ms,
                is_lost, is_udp_lost, is_gw_lost, is_vpn, dl_bps, ul_bps, target_host,
                game_fps, game_vram_mb, game_ram_mb, game_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        self.executePragmaOrSQL("BEGIN IMMEDIATE;", on: db)

        for snap in batch {
            sqlite3_bind_double(stmt, 1, snap.timestamp.timeIntervalSince1970)
            self.bindOptionalDouble(stmt, index: 2, value: snap.cpuTemperature)
            self.bindOptionalDouble(stmt, index: 3, value: snap.gpuTemperature)
            self.bindOptionalDouble(stmt, index: 4, value: snap.peakTemperature)
            sqlite3_bind_double(stmt, 5, snap.cpuTotalPercent)
            sqlite3_bind_double(stmt, 6, snap.memoryUsedGB)
            sqlite3_bind_double(stmt, 7, snap.memoryUsedPercent)
            self.bindOptionalDouble(stmt, index: 8, value: snap.estimatedWatts)
            if let bat = snap.batteryPercent {
                sqlite3_bind_int(stmt, 9, Int32(bat))
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_int(stmt, 10, snap.isCharging ? 1 : 0)

            self.bindOptionalDouble(stmt, index: 12, value: snap.network.pingMs)
            self.bindOptionalDouble(stmt, index: 13, value: snap.network.icmpPingMs)
            self.bindOptionalDouble(stmt, index: 14, value: snap.network.udpPingMs)
            self.bindOptionalDouble(stmt, index: 15, value: snap.network.tcpPingMs)
            self.bindOptionalDouble(stmt, index: 16, value: snap.network.gatewayPingMs)
            sqlite3_bind_double(stmt, 17, snap.network.jitterMs)
            sqlite3_bind_int(stmt, 18, snap.network.isLastProbeLost ? 1 : 0)
            sqlite3_bind_int(stmt, 19, snap.network.isUDPLastLost ? 1 : 0)
            sqlite3_bind_int(stmt, 20, snap.network.isGatewayLastProbeLost ? 1 : 0)
            sqlite3_bind_int(stmt, 21, snap.network.route.isVPNActive ? 1 : 0)
            sqlite3_bind_double(stmt, 22, snap.network.downloadBytesPerSec)
            sqlite3_bind_double(stmt, 23, snap.network.uploadBytesPerSec)
            self.bindOptionalDouble(stmt, index: 25, value: snap.gameFPS)
            self.bindOptionalDouble(stmt, index: 26, value: snap.gameVRAMMB)
            self.bindOptionalDouble(stmt, index: 27, value: snap.gameRAMMB)

            snap.thermalState.withCString { thermalPtr in
                snap.network.target.host.withCString { hostPtr in
                    sqlite3_bind_text(stmt, 11, thermalPtr, -1, nil)
                    sqlite3_bind_text(stmt, 24, hostPtr, -1, nil)
                    if let gameName = snap.gameName {
                        gameName.withCString { gamePtr in
                            sqlite3_bind_text(stmt, 28, gamePtr, -1, nil)
                            _ = sqlite3_step(stmt)
                        }
                    } else {
                        sqlite3_bind_null(stmt, 28)
                        _ = sqlite3_step(stmt)
                    }
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                }
            }
        }

        self.executePragmaOrSQL("COMMIT;", on: db)

        let now = Date()
        if now.timeIntervalSince(self.lastPruneDate) >= Self.pruneIntervalSeconds {
            self.pruneOlderThan24h(now: now, on: db)
        }
    }

    func getStatus() -> TelemetryLogStatus {
        self.flushNow()
        guard let db = self.openDatabaseIfNeeded() else {
            return TelemetryLogStatus.empty
        }

        let sql = """
            SELECT COUNT(*), MIN(ts), MAX(ts), COALESCE(SUM(is_lost), 0),
                   MAX(cpu_temp), MAX(gpu_temp), MAX(watts)
            FROM telemetry_samples;
            """
        var stmt: OpaquePointer?
        var count = 0
        var oldest: Date?
        var newest: Date?
        var totalDrops = 0
        var maxCPU: Double?
        var maxGPU: Double?
        var maxWatts: Double?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
                if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                    oldest = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                }
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                    newest = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                }
                totalDrops = Int(sqlite3_column_int64(stmt, 3))
                maxCPU = self.readOptionalDouble(stmt, col: 4)
                maxGPU = self.readOptionalDouble(stmt, col: 5)
                maxWatts = self.readOptionalDouble(stmt, col: 6)
            }
            sqlite3_finalize(stmt)
        }

        return TelemetryLogStatus(
            isRecording: self.isRecordingEnabled,
            sampleCount: count,
            pendingCount: self.pendingBuffer.count,
            oldestTimestamp: oldest,
            newestTimestamp: newest,
            diskSizeBytes: self.calculateDiskSizeBytes(),
            totalDrops: totalDrops,
            maxCPUTemp: maxCPU,
            maxGPUTemp: maxGPU,
            maxWatts: maxWatts,
            databasePath: self.databaseURL.path
        )
    }

    func querySeries(windowSeconds: TimeInterval, maxPoints: Int = 200) -> [TelemetryLogBucket] {
        self.flushNow()
        guard let db = self.openDatabaseIfNeeded() else { return [] }

        let clampedWindow = max(60, min(Self.retentionSeconds, windowSeconds))
        let cutoff = Date().timeIntervalSince1970 - clampedWindow
        let bucketSec = max(1, Int(ceil(clampedWindow / Double(max(1, maxPoints)))))

        let sql = """
            SELECT CAST(ts / ? AS INTEGER) AS bkt,
                   MAX(ts),
                   MAX(cpu_temp),
                   MAX(gpu_temp),
                   AVG(watts),
                   AVG(ram_used_gb),
                   AVG(cpu_pct),
                   MAX(ping_ms),
                   MAX(udp_ms),
                   MAX(gateway_ms),
                   COALESCE(SUM(is_lost), 0),
                   COALESCE(SUM(is_udp_lost), 0),
                   COUNT(*),
                   AVG(game_fps),
                   MIN(game_fps),
                   AVG(game_vram_mb),
                   AVG(game_ram_mb)
            FROM telemetry_samples
            WHERE ts >= ?
            GROUP BY bkt
            ORDER BY bkt ASC;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(bucketSec))
        sqlite3_bind_double(stmt, 2, cutoff)

        var result: [TelemetryLogBucket] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bktID = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            result.append(TelemetryLogBucket(
                id: bktID,
                timestamp: ts,
                maxCPUTemp: self.readOptionalDouble(stmt, col: 2),
                maxGPUTemp: self.readOptionalDouble(stmt, col: 3),
                avgWatts: self.readOptionalDouble(stmt, col: 4),
                avgRAMUsedGB: sqlite3_column_double(stmt, 5),
                avgCPUPercent: sqlite3_column_double(stmt, 6),
                maxPingMs: self.readOptionalDouble(stmt, col: 7),
                maxUDPMs: self.readOptionalDouble(stmt, col: 8),
                maxGatewayMs: self.readOptionalDouble(stmt, col: 9),
                dropCount: Int(sqlite3_column_int64(stmt, 10)),
                udpDropCount: Int(sqlite3_column_int64(stmt, 11)),
                sampleCount: Int(sqlite3_column_int64(stmt, 12)),
                avgGameFPS: self.readOptionalDouble(stmt, col: 13),
                minGameFPS: self.readOptionalDouble(stmt, col: 14),
                avgGameVRAMMB: self.readOptionalDouble(stmt, col: 15),
                avgGameRAMMB: self.readOptionalDouble(stmt, col: 16)
            ))
        }
        return result
    }

    func exportUnifiedCSVFile(windowSeconds: TimeInterval) -> URL? {
        self.flushNow()
        guard let db = self.openDatabaseIfNeeded() else { return nil }

        let clampedWindow = max(60, min(Self.retentionSeconds, windowSeconds))
        let cutoff = Date().timeIntervalSince1970 - clampedWindow
        let minutes = Int(clampedWindow / 60.0)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSensors_Telemetria_\(minutes)m.csv")

        let header = "timestamp,cpu_temp_c,gpu_temp_c,peak_temp_c,cpu_pct,ram_used_gb,ram_pct,watts,battery_pct,is_charging,thermal_state,ping_ms,icmp_ms,udp_ms,tcp_ms,gateway_ms,jitter_ms,is_lost,is_udp_lost,is_gw_lost,is_vpn,dl_bps,ul_bps,target_host,game_fps,game_vram_mb,game_ram_mb,game_name\n"
        do {
            try header.write(to: outURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        guard let fileHandle = try? FileHandle(forWritingTo: outURL) else { return outURL }
        defer { try? fileHandle.close() }
        _ = try? fileHandle.seekToEnd()

        let sql = """
            SELECT ts, cpu_temp, gpu_temp, peak_temp, cpu_pct, ram_used_gb, ram_pct,
                   watts, battery_pct, is_charging, thermal_state,
                   ping_ms, icmp_ms, udp_ms, tcp_ms, gateway_ms, jitter_ms,
                   is_lost, is_udp_lost, is_gw_lost, is_vpn, dl_bps, ul_bps, target_host,
                   game_fps, game_vram_mb, game_ram_mb, game_name
            FROM telemetry_samples
            WHERE ts >= ?
            ORDER BY ts ASC;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return outURL
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var chunk = ""
        chunk.reserveCapacity(32_768)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let tsStr = iso.string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)))
            let cpuT = self.formatOptionalDouble(stmt, col: 1, decimals: 1)
            let gpuT = self.formatOptionalDouble(stmt, col: 2, decimals: 1)
            let peakT = self.formatOptionalDouble(stmt, col: 3, decimals: 1)
            let cpuPct = String(format: "%.1f", sqlite3_column_double(stmt, 4))
            let ramGB = String(format: "%.2f", sqlite3_column_double(stmt, 5))
            let ramPct = String(format: "%.1f", sqlite3_column_double(stmt, 6))
            let watts = self.formatOptionalDouble(stmt, col: 7, decimals: 2)
            let bat = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? "" : "\(sqlite3_column_int(stmt, 8))"
            let chg = sqlite3_column_int(stmt, 9)
            let thermal = self.readText(stmt, col: 10)
            let ping = self.formatOptionalDouble(stmt, col: 11, decimals: 2)
            let icmp = self.formatOptionalDouble(stmt, col: 12, decimals: 2)
            let udp = self.formatOptionalDouble(stmt, col: 13, decimals: 2)
            let tcp = self.formatOptionalDouble(stmt, col: 14, decimals: 2)
            let gw = self.formatOptionalDouble(stmt, col: 15, decimals: 2)
            let jit = String(format: "%.2f", sqlite3_column_double(stmt, 16))
            let lost = sqlite3_column_int(stmt, 17)
            let udpLost = sqlite3_column_int(stmt, 18)
            let gwLost = sqlite3_column_int(stmt, 19)
            let vpn = sqlite3_column_int(stmt, 20)
            let dl = String(format: "%.0f", sqlite3_column_double(stmt, 21))
            let ul = String(format: "%.0f", sqlite3_column_double(stmt, 22))
            let host = self.readText(stmt, col: 23).replacingOccurrences(of: ",", with: "_")
            let gameFPS = self.formatOptionalDouble(stmt, col: 24, decimals: 1)
            let gameVRAM = self.formatOptionalDouble(stmt, col: 25, decimals: 1)
            let gameRAM = self.formatOptionalDouble(stmt, col: 26, decimals: 1)
            let gameName = self.readText(stmt, col: 27).replacingOccurrences(of: ",", with: "_")

            chunk.append("\(tsStr),\(cpuT),\(gpuT),\(peakT),\(cpuPct),\(ramGB),\(ramPct),\(watts),\(bat),\(chg),\(thermal),\(ping),\(icmp),\(udp),\(tcp),\(gw),\(jit),\(lost),\(udpLost),\(gwLost),\(vpn),\(dl),\(ul),\(host),\(gameFPS),\(gameVRAM),\(gameRAM),\(gameName)\n")

            if chunk.utf8.count >= 16_384 {
                if let data = chunk.data(using: .utf8) {
                    try? fileHandle.write(contentsOf: data)
                }
                chunk.removeAll(keepingCapacity: true)
            }
        }

        if !chunk.isEmpty, let data = chunk.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }

        return outURL
    }

    func clearAllLogs() {
        self.pendingBuffer.removeAll()
        guard let db = self.openDatabaseIfNeeded() else { return }
        self.executePragmaOrSQL("DELETE FROM telemetry_samples;", on: db)
        self.executePragmaOrSQL("PRAGMA wal_checkpoint(TRUNCATE);", on: db)
        self.executePragmaOrSQL("VACUUM;", on: db)
        self.lastPruneDate = Date()
    }

    nonisolated static func fallbackEmptyCSVURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftSensors_Telemetria_vazia.csv")
        try? "timestamp\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - SQLite Internals

    private func openDatabaseIfNeeded() -> OpaquePointer? {
        if let db { return db }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(self.databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }

        self.executePragmaOrSQL("PRAGMA journal_mode=WAL;", on: handle)
        self.executePragmaOrSQL("PRAGMA synchronous=NORMAL;", on: handle)
        self.executePragmaOrSQL("PRAGMA auto_vacuum=INCREMENTAL;", on: handle)
        self.executePragmaOrSQL("PRAGMA busy_timeout=2000;", on: handle)

        let schemaSQL = """
            CREATE TABLE IF NOT EXISTS telemetry_samples (
                ts REAL PRIMARY KEY,
                cpu_temp REAL,
                gpu_temp REAL,
                peak_temp REAL,
                cpu_pct REAL NOT NULL,
                ram_used_gb REAL NOT NULL,
                ram_pct REAL NOT NULL,
                watts REAL,
                battery_pct INTEGER,
                is_charging INTEGER NOT NULL,
                thermal_state TEXT NOT NULL,
                ping_ms REAL,
                icmp_ms REAL,
                udp_ms REAL,
                tcp_ms REAL,
                gateway_ms REAL,
                jitter_ms REAL NOT NULL,
                is_lost INTEGER NOT NULL,
                is_udp_lost INTEGER NOT NULL,
                is_gw_lost INTEGER NOT NULL,
                is_vpn INTEGER NOT NULL,
                dl_bps REAL NOT NULL,
                ul_bps REAL NOT NULL,
                target_host TEXT NOT NULL,
                game_fps REAL,
                game_vram_mb REAL,
                game_ram_mb REAL,
                game_name TEXT
            );
            """
        self.executePragmaOrSQL(schemaSQL, on: handle)
        self.executePragmaOrSQL("ALTER TABLE telemetry_samples ADD COLUMN game_fps REAL;", on: handle)
        self.executePragmaOrSQL("ALTER TABLE telemetry_samples ADD COLUMN game_vram_mb REAL;", on: handle)
        self.executePragmaOrSQL("ALTER TABLE telemetry_samples ADD COLUMN game_ram_mb REAL;", on: handle)
        self.executePragmaOrSQL("ALTER TABLE telemetry_samples ADD COLUMN game_name TEXT;", on: handle)
        self.db = handle
        return handle
    }

    private func pruneOlderThan24h(now: Date, on db: OpaquePointer) {
        let cutoff = now.timeIntervalSince1970 - Self.retentionSeconds
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM telemetry_samples WHERE ts < ?;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            sqlite3_bind_double(stmt, 1, cutoff)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        self.executePragmaOrSQL("PRAGMA incremental_vacuum(64);", on: db)
        self.executePragmaOrSQL("PRAGMA wal_checkpoint(PASSIVE);", on: db)
        self.lastPruneDate = now
    }

    private func executePragmaOrSQL(_ sql: String, on db: OpaquePointer) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readOptionalDouble(_ stmt: OpaquePointer, col: Int32) -> Double? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, col)
    }

    private func formatOptionalDouble(_ stmt: OpaquePointer, col: Int32, decimals: Int) -> String {
        guard let value = self.readOptionalDouble(stmt, col: col) else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    private func readText(_ stmt: OpaquePointer, col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }

    private func calculateDiskSizeBytes() -> Int64 {
        let paths = [
            self.databaseURL.path,
            self.databaseURL.path + "-wal",
            self.databaseURL.path + "-shm",
        ]
        var total: Int64 = 0
        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }
}
