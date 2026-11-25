import Charts
import SwiftSensors
import SwiftUI

/// Time-series latency chart plotting external protocol RTT(s), local gateway RTT,
/// and vertical drop markers across windows up to 1 hour with peak-preserving downsampling.
struct NetworkLatencyChartView: View {
    enum TimeWindow: Double, CaseIterable, Identifiable {
        case twoMinutes = 120
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case thirtyMinutes = 1800
        case oneHour = 3600

        var id: Double { self.rawValue }

        var title: String {
            switch self {
            case .twoMinutes: return "2m"
            case .fiveMinutes: return "5m"
            case .fifteenMinutes: return "15m"
            case .thirtyMinutes: return "30m"
            case .oneHour: return "1h"
            }
        }

        var showsSecondsOnAxis: Bool {
            switch self {
            case .twoMinutes, .fiveMinutes: return true
            case .fifteenMinutes, .thirtyMinutes, .oneHour: return false
            }
        }
    }

    private struct ChartPoint: Identifiable {
        let id: Int
        let timestamp: Date
        let targetRTTMs: Double?
        let gatewayRTTMs: Double?
        let icmpRTTMs: Double?
        let udpRTTMs: Double?
        let tcpRTTMs: Double?
    }

    let samples: [NetworkProbeSample]
    var isMultiProtocol: Bool = false

    @State private var selectedWindow: TimeWindow = .fiveMinutes

    private var filteredSamples: [NetworkProbeSample] {
        let cutoff = Date().addingTimeInterval(-self.selectedWindow.rawValue)
        return self.samples.filter { $0.timestamp >= cutoff }
    }

    private var totalDropCount: Int {
        self.filteredSamples.filter(\.isTargetLost).count
    }

    private var renderedDropDates: [Date] {
        Self.downsampleDates(self.filteredSamples.filter(\.isTargetLost).map(\.timestamp), maxCount: 180)
    }

    private var renderedIsolatedUDPDropDates: [Date] {
        guard self.isMultiProtocol else { return [] }
        let dates = self.filteredSamples
            .filter { $0.isUDPLost && !$0.isTargetLost }
            .map(\.timestamp)
        return Self.downsampleDates(dates, maxCount: 180)
    }

    private var renderedPoints: [ChartPoint] {
        let slice = self.filteredSamples
        guard !slice.isEmpty else { return [] }

        let maxVisualPoints = 240
        if slice.count <= maxVisualPoints {
            return slice.enumerated().map { idx, sample in
                ChartPoint(
                    id: idx,
                    timestamp: sample.timestamp,
                    targetRTTMs: sample.targetRTTMs,
                    gatewayRTTMs: sample.gatewayRTTMs,
                    icmpRTTMs: sample.icmpRTTMs,
                    udpRTTMs: sample.udpRTTMs,
                    tcpRTTMs: sample.tcpRTTMs
                )
            }
        }

        let bucketSize = Int(ceil(Double(slice.count) / Double(maxVisualPoints)))
        var result: [ChartPoint] = []
        result.reserveCapacity(maxVisualPoints)

        var start = 0
        var bucketIndex = 0
        while start < slice.count {
            let end = min(start + bucketSize, slice.count)
            let bucket = slice[start..<end]
            let timestamp = bucket.last?.timestamp ?? slice[start].timestamp

            result.append(ChartPoint(
                id: bucketIndex,
                timestamp: timestamp,
                targetRTTMs: bucket.compactMap(\.targetRTTMs).max(),
                gatewayRTTMs: bucket.compactMap(\.gatewayRTTMs).max(),
                icmpRTTMs: bucket.compactMap(\.icmpRTTMs).max(),
                udpRTTMs: bucket.compactMap(\.udpRTTMs).max(),
                tcpRTTMs: bucket.compactMap(\.tcpRTTMs).max()
            ))
            start = end
            bucketIndex += 1
        }
        return result
    }

    var body: some View {
        let points = self.renderedPoints
        let dropDates = self.renderedDropDates
        let udpIsolatedDates = self.renderedIsolatedUDPDropDates

        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label(L10n.tr("Latency & Drops"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    self.windowPicker
                        .frame(maxWidth: 280)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.tr("Latency & Drops"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    self.windowPicker
                }
            }

            if self.filteredSamples.count < 2 {
                ContentUnavailableView(
                    L10n.tr("Collecting network samples"),
                    systemImage: "waveform.path.ecg",
                    description: Text(L10n.tr("The chart appears after the first few seconds of probing."))
                )
                .frame(height: 210)
            } else {
                Chart {
                    if self.isMultiProtocol {
                        ForEach(points) { point in
                            if let icmp = point.icmpRTTMs {
                                LineMark(
                                    x: .value(L10n.tr("Time"), point.timestamp),
                                    y: .value("RTT", icmp),
                                    series: .value(L10n.tr("Probe"), "ICMP")
                                )
                                .foregroundStyle(Color.accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }

                        ForEach(points) { point in
                            if let udp = point.udpRTTMs {
                                LineMark(
                                    x: .value(L10n.tr("Time"), point.timestamp),
                                    y: .value("RTT", udp),
                                    series: .value(L10n.tr("Probe"), "UDP")
                                )
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }

                        ForEach(points) { point in
                            if let tcp = point.tcpRTTMs {
                                LineMark(
                                    x: .value(L10n.tr("Time"), point.timestamp),
                                    y: .value("RTT", tcp),
                                    series: .value(L10n.tr("Probe"), "TCP")
                                )
                                .foregroundStyle(.purple)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            }
                        }
                    } else {
                        ForEach(points) { point in
                            if let rtt = point.targetRTTMs {
                                LineMark(
                                    x: .value(L10n.tr("Time"), point.timestamp),
                                    y: .value("RTT", rtt),
                                    series: .value(L10n.tr("Probe"), L10n.tr("External Target"))
                                )
                                .foregroundStyle(Color.accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }

                    ForEach(points) { point in
                        if let gwRTT = point.gatewayRTTMs {
                            LineMark(
                                x: .value(L10n.tr("Time"), point.timestamp),
                                y: .value("RTT", gwRTT),
                                series: .value(L10n.tr("Probe"), L10n.tr("Router"))
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }

                    ForEach(Array(udpIsolatedDates.enumerated()), id: \.offset) { _, udpDropDate in
                        RuleMark(x: .value("UDP Drop", udpDropDate))
                            .foregroundStyle(.orange.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    ForEach(Array(dropDates.enumerated()), id: \.offset) { _, dropDate in
                        RuleMark(x: .value("Drop", dropDate))
                            .foregroundStyle(.red.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        if self.selectedWindow.showsSecondsOnAxis {
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
                            if let ms = value.as(Double.self) {
                                Text("\(Int(ms))ms")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .frame(height: 220)

                self.legendView(hasIsolatedUDPDrops: !udpIsolatedDates.isEmpty)
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
            ForEach(TimeWindow.allCases) { window in
                Text(window.title).tag(window)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func legendView(hasIsolatedUDPDrops: Bool) -> some View {
        if self.isMultiProtocol {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 98), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                self.legendItem(color: Color.accentColor, title: "ICMP", systemImage: "globe")
                self.legendItem(color: .orange, title: "UDP", systemImage: "bolt.horizontal.fill")
                self.legendItem(color: .purple, title: "TCP", systemImage: "arrow.left.arrow.right")
                self.legendItem(color: .green, title: L10n.tr("Router"), systemImage: "wifi.router")
                self.legendItem(
                    color: .red,
                    title: "Drop (\(self.totalDropCount))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                if hasIsolatedUDPDrops {
                    self.legendItem(color: .orange, title: "UDP Drop", systemImage: "bolt.slash.fill")
                }
            }
            .font(.footnote)
        } else {
            HStack(spacing: 16) {
                self.legendItem(color: Color.accentColor, title: L10n.tr("External Target"), systemImage: "globe")
                self.legendItem(color: .green, title: L10n.tr("Local Router"), systemImage: "wifi.router")
                self.legendItem(
                    color: .red,
                    title: "Drop (\(self.totalDropCount))",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            .font(.footnote)
        }
    }

    private func legendItem(color: Color, title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
    }

    private static func downsampleDates(_ dates: [Date], maxCount: Int) -> [Date] {
        guard dates.count > maxCount, maxCount > 0 else { return dates }
        let step = Double(dates.count) / Double(maxCount)
        return (0..<maxCount).map { idx in
            let sampleIdx = min(dates.count - 1, Int(Double(idx) * step))
            return dates[sampleIdx]
        }
    }
}
