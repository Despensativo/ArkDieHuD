import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Transferable wrapper generating a unified hardware + network CSV file from SQLite on demand.
struct UnifiedTelemetryCSVFile: Transferable {
    let windowSeconds: TimeInterval

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let url = await TelemetryLogStore.shared.exportUnifiedCSVFile(windowSeconds: item.windowSeconds)
                ?? TelemetryLogStore.fallbackEmptyCSVURL()
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }
    }
}

/// Persistent 24-hour SQLite WAL telemetry logs, storage metrics, interactive downsampled charts,
/// and unified CSV export view.
struct TelemetryLogsView: View {
    enum LogWindow: Double, CaseIterable, Identifiable {
        case fifteenMinutes = 900
        case oneHour = 3600
        case sixHours = 21_600
        case twentyFourHours = 86_400

        var id: Double { self.rawValue }

        var title: String {
            switch self {
            case .fifteenMinutes: return "15m"
            case .oneHour: return "1h"
            case .sixHours: return "6h"
            case .twentyFourHours: return "24h"
            }
        }

        var showsSeconds: Bool {
            self == .fifteenMinutes
        }
    }

    enum ChartCategory: String, CaseIterable, Identifiable {
        case thermal = "Thermal"
        case energyRAM = "Power & RAM"
        case network = "Network"

        var id: String { self.rawValue }

        var localizedTitle: String {
            L10n.tr(self.rawValue)
        }
    }

    @Bindable var hudController: PiPHUDController

    @State private var status: TelemetryLogStatus = .empty
    @State private var series: [TelemetryLogBucket] = []
    @State private var selectedWindow: LogWindow = .oneHour
    @State private var selectedCategory: ChartCategory = .thermal
    @State private var showClearAlert: Bool = false
    @State private var clearTrigger: Int = 0

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TelemetryTheme.sectionSpacing) {
                self.recordingCard
                self.chartCard
            }
            .padding()
        }
        .background(TelemetryTheme.groupedBackground)
        .navigationTitle(L10n.tr("24h Telemetry & Logs"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(
                    item: UnifiedTelemetryCSVFile(windowSeconds: self.selectedWindow.rawValue),
                    preview: SharePreview(
                        "ArkDieHuD_Telemetry_\(self.selectedWindow.title).csv",
                        image: Image(systemName: "doc.text")
                    )
                ) {
                    Label(L10n.tr("Export CSV"), systemImage: "square.and.arrow.up")
                }

                Button(L10n.tr("Delete Logs"), systemImage: "trash", role: .destructive) {
                    self.showClearAlert = true
                }
                .tint(.red)
                .sensoryFeedback(.warning, trigger: self.clearTrigger)
            }
        }
        .alert(L10n.tr("Delete 24h logs?"), isPresented: self.$showClearAlert) {
            Button(L10n.tr("Delete All"), role: .destructive) {
                self.clearTrigger += 1
                Task {
                    await TelemetryLogStore.shared.clearAllLogs()
                    await self.refreshLogs()
                }
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("This will permanently remove all hardware and network samples saved in the SQLite database."))
        }
        .task(id: self.selectedWindow) {
            while !Task.isCancelled {
                await self.refreshLogs()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Card 1: Recording Control & Storage Summary

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(isOn: self.$hudController.isRecordingLogs) {
                    Label(L10n.tr("Record Logs to Disk (24h)"), systemImage: "externaldrive.badge.timemachine")
                        .font(.headline)
                }
                .onChange(of: self.hudController.isRecordingLogs) { _, _ in
                    Task {
                        await self.refreshLogs()
                    }
                }
            }

            HStack(spacing: 8) {
                Label(
                    self.hudController.isRecordingLogs ? L10n.tr("Recording") : L10n.tr("Paused"),
                    systemImage: self.hudController.isRecordingLogs ? "record.circle" : "pause.circle"
                )
                .font(.caption.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    (self.hudController.isRecordingLogs ? Color.green : Color.secondary).opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(self.hudController.isRecordingLogs ? .green : .secondary)

                Spacer()

                if self.status.pendingCount > 0 {
                    Text(L10n.fmt("Buffered: %llds", self.status.pendingCount))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                spacing: 10
            ) {
                self.infoTile(
                    label: L10n.tr("Disk Size"),
                    value: Self.byteFormatter.string(fromByteCount: self.status.diskSizeBytes)
                )
                self.infoTile(
                    label: L10n.tr("Saved Samples"),
                    value: "\(self.status.sampleCount)"
                )
                self.infoTile(
                    label: L10n.tr("Coverage"),
                    value: self.coverageText
                )
                self.infoTile(
                    label: L10n.tr("Drops (24h)"),
                    value: "\(self.status.totalDrops)"
                )
            }

            Text(L10n.tr("Native SQLite WAL with 15s batched writes and automatic pruning of entries older than 24 hours."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(TelemetryTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Card 2: Interactive Aggregated 24h Charts

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label(L10n.tr("Persistent History"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Spacer()
                    self.windowPicker
                        .frame(maxWidth: 260)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.tr("Persistent History"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    self.windowPicker
                }
            }

            Picker(L10n.tr("Category"), selection: self.$selectedCategory) {
                ForEach(ChartCategory.allCases) { cat in
                    Text(cat.localizedTitle).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            if self.series.count < 2 {
                ContentUnavailableView(
                    L10n.tr("Waiting for first batch write"),
                    systemImage: "waveform.path.ecg",
                    description: Text(L10n.tr("The database writes every 15 seconds and retains up to 24 hours of unified metrics."))
                )
                .frame(height: 220)
            } else {
                self.aggregatedChart
                    .frame(height: 220)

                self.windowSummaryBar
            }
        }
        .padding(TelemetryTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.cornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }

    private var windowPicker: some View {
        Picker(L10n.tr("Window"), selection: self.$selectedWindow) {
            ForEach(LogWindow.allCases) { window in
                Text(window.title).tag(window)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var aggregatedChart: some View {
        Chart {
            switch self.selectedCategory {
            case .thermal:
                ForEach(self.series) { bkt in
                    if let cpu = bkt.maxCPUTemp {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value("°C", cpu),
                            series: .value("Sensor", "CPU °C")
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(self.series) { bkt in
                    if let gpu = bkt.maxGPUTemp {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value("°C", gpu),
                            series: .value("Sensor", "GPU °C")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }

            case .energyRAM:
                ForEach(self.series) { bkt in
                    if let watts = bkt.avgWatts {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value(L10n.tr("Value"), watts),
                            series: .value(L10n.tr("Metric"), L10n.tr("Power (W)"))
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(self.series) { bkt in
                    LineMark(
                        x: .value(L10n.tr("Time"), bkt.timestamp),
                        y: .value(L10n.tr("Value"), bkt.avgRAMUsedGB),
                        series: .value(L10n.tr("Metric"), "RAM (GB)")
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

            case .network:
                ForEach(self.series) { bkt in
                    if let ping = bkt.maxPingMs {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value("ms", ping),
                            series: .value(L10n.tr("Probe"), L10n.tr("Target (ms)"))
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(self.series) { bkt in
                    if let udp = bkt.maxUDPMs {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value("ms", udp),
                            series: .value(L10n.tr("Probe"), "UDP (ms)")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(self.series) { bkt in
                    if let gw = bkt.maxGatewayMs {
                        LineMark(
                            x: .value(L10n.tr("Time"), bkt.timestamp),
                            y: .value("ms", gw),
                            series: .value(L10n.tr("Probe"), L10n.tr("Router (ms)"))
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                ForEach(self.series.filter { $0.dropCount > 0 }) { dropBucket in
                    RuleMark(x: .value("Drop", dropBucket.timestamp))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                if self.selectedWindow.showsSeconds {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(self.formatYAxisValue(val))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var windowSummaryBar: some View {
        let peakCPU = self.series.compactMap(\.maxCPUTemp).max()
        let peakGPU = self.series.compactMap(\.maxGPUTemp).max()
        let peakWatts = self.series.compactMap(\.avgWatts).max()
        let drops = self.series.reduce(0) { $0 + $1.dropCount }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            self.infoTile(
                label: L10n.tr("Peak CPU"),
                value: peakCPU.map { String(format: "%.1f°C", $0) } ?? "--"
            )
            self.infoTile(
                label: L10n.tr("Peak GPU"),
                value: peakGPU.map { String(format: "%.1f°C", $0) } ?? "--"
            )
            self.infoTile(
                label: L10n.tr("Peak Watts"),
                value: peakWatts.map { String(format: "%.1f W", $0) } ?? "--"
            )
            self.infoTile(
                label: "Drops",
                value: "\(drops)"
            )
        }
    }

    private var coverageText: String {
        guard let oldest = self.status.oldestTimestamp,
              let newest = self.status.newestTimestamp else {
            return "--"
        }
        let seconds = max(0, Int(newest.timeIntervalSince(oldest)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }

    private func formatYAxisValue(_ val: Double) -> String {
        switch self.selectedCategory {
        case .thermal:
            return "\(Int(val))°"
        case .energyRAM:
            return String(format: "%.0f", val)
        case .network:
            return "\(Int(val))ms"
        }
    }

    private func infoTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TelemetryTheme.groupedBackground)
        )
    }

    private func refreshLogs() async {
        async let statusTask = TelemetryLogStore.shared.getStatus()
        async let seriesTask = TelemetryLogStore.shared.querySeries(
            windowSeconds: self.selectedWindow.rawValue,
            maxPoints: 200
        )
        let fetchedStatus = await statusTask
        let fetchedSeries = await seriesTask
        self.status = fetchedStatus
        self.series = fetchedSeries
    }
}
