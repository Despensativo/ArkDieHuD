import SwiftSensors
import SwiftUI

/// Detailed telemetry view for a selected sensor or kernel domain, displaying
/// interactive time-series charts alongside individual formatted readouts.
struct SectionDetailView: View {
    let section: SensorSection
    @Environment(\.sensorsViewModel) private var viewModel

    var body: some View {
        Group {
            if self.section == .performance {
                List {
                    PerformanceSectionView(viewModel: self.viewModel)
                }
            } else {
                VStack(spacing: 0) {
                    self.chartForSection
                        .frame(height: 220)
                        .padding()

                    List {
                        self.sectionContent
                    }
                }
            }
        }
        .navigationTitle(self.section.localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                self.viewModel.updateIfNeeded()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var chartForSection: some View {
        switch self.section {
        case .network, .telemetryLogs, .performance:
            EmptyView()

        case .thermal:
            if self.viewModel.selectedThermalReadings.isEmpty {
                self.emptyChartPrompt(L10n.tr("Tap one or more thermal sensors below to plot on the chart."))
            } else {
                MultiSensorChart()
            }

        case .voltage:
            if self.viewModel.selectedVoltageReadings.isEmpty {
                self.emptyChartPrompt(L10n.tr("Select voltage sensors below to track the curve."))
            } else {
                VoltageChart()
            }

        case .current:
            if self.viewModel.selectedCurrentReadings.isEmpty {
                self.emptyChartPrompt(L10n.tr("Select current sensors below to track the curve."))
            } else {
                CurrentChart()
            }

        case .memory:
            if self.viewModel.selectedMemoryItems.isEmpty {
                self.emptyChartPrompt(L10n.tr("Select memory metrics below to track usage."))
            } else {
                MemoryChart()
            }

        case .cpu:
            if self.viewModel.selectedCPUItems.isEmpty {
                self.emptyChartPrompt(L10n.tr("Select CPU metrics below to track load."))
            } else {
                CPUChart()
            }

        case .disk:
            if self.viewModel.selectedDiskItems.isEmpty {
                self.emptyChartPrompt(L10n.tr("Select storage metrics below to display."))
            } else {
                DiskChart()
            }

        case .system:
            ContentUnavailableView(
                L10n.tr("System Information"),
                systemImage: "ipad",
                description: Text(L10n.tr("Static summary and current iPadOS thermal state."))
            )
        }
    }

    private func emptyChartPrompt(_ message: String) -> some View {
        ContentUnavailableView(
            L10n.tr("No items in chart"),
            systemImage: "chart.xyaxis.line",
            description: Text(message)
        )
        .onAppear {
            self.viewModel.updateIfNeeded()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch self.section {
        case .network, .telemetryLogs, .performance:
            EmptyView()

        case .thermal:
            ForEach(self.viewModel.thermalSensorReadings, id: \.id) { sensor in
                let isSelected = self.viewModel.selectedThermalReadings.contains(sensor.name)
                let fallback = String(format: "%.1f °C", sensor.temperature)
                let displayValue = self.viewModel.thermalSensorReadings
                    .firstIndex(where: { $0.id == sensor.id })
                    .flatMap { idx in
                        idx < self.viewModel.formattedTemperatures.count
                            ? self.viewModel.formattedTemperatures[idx]
                            : nil
                    } ?? fallback

                self.selectableRow(
                    title: sensor.name,
                    value: displayValue,
                    isSelected: isSelected
                ) {
                    self.toggle(&self.viewModel.selectedThermalReadings, item: sensor.name)
                }
            }

        case .voltage:
            ForEach(self.viewModel.voltageSensorReadings, id: \.id) { sensor in
                let isSelected = self.viewModel.selectedVoltageReadings.contains(sensor.name)
                let fallback = String(format: "%.2f V", sensor.voltage)
                let displayValue = self.viewModel.voltageSensorReadings
                    .firstIndex(where: { $0.id == sensor.id })
                    .flatMap { idx in
                        idx < self.viewModel.formattedVoltages.count
                            ? self.viewModel.formattedVoltages[idx]
                            : nil
                    } ?? fallback

                self.selectableRow(
                    title: sensor.name,
                    value: displayValue,
                    isSelected: isSelected
                ) {
                    self.toggle(&self.viewModel.selectedVoltageReadings, item: sensor.name)
                }
            }

        case .current:
            ForEach(self.viewModel.currentSensorReadings, id: \.id) { sensor in
                let isSelected = self.viewModel.selectedCurrentReadings.contains(sensor.name)
                let fallback = String(format: "%.3f A", sensor.current)
                let displayValue = self.viewModel.currentSensorReadings
                    .firstIndex(where: { $0.id == sensor.id })
                    .flatMap { idx in
                        idx < self.viewModel.formattedCurrents.count
                            ? self.viewModel.formattedCurrents[idx]
                            : nil
                    } ?? fallback

                self.selectableRow(
                    title: sensor.name,
                    value: displayValue,
                    isSelected: isSelected
                ) {
                    self.toggle(&self.viewModel.selectedCurrentReadings, item: sensor.name)
                }
            }

        case .memory:
            if self.viewModel.memoryStats != nil {
                ForEach(MemoryMetricType.allCases, id: \.self) { metricType in
                    let value = metricType.rawValue < self.viewModel.formattedMemoryValues.count
                        ? self.viewModel.formattedMemoryValues[metricType.rawValue]
                        : "--"
                    self.selectableRow(
                        title: metricType.localizedName,
                        value: value,
                        isSelected: self.viewModel.selectedMemoryItems.contains(metricType.rawValue)
                    ) {
                        self.toggle(&self.viewModel.selectedMemoryItems, item: metricType.rawValue)
                    }
                }
            } else {
                Text(L10n.tr("Memory metrics unavailable"))
                    .foregroundStyle(.secondary)
            }

        case .cpu:
            if self.viewModel.cpuStats != nil {
                ForEach(CPUMetricType.allCases, id: \.self) { metricType in
                    let value = metricType.rawValue < self.viewModel.formattedCPUValues.count
                        ? self.viewModel.formattedCPUValues[metricType.rawValue]
                        : "--"
                    self.selectableRow(
                        title: metricType.localizedName,
                        value: value,
                        isSelected: self.viewModel.selectedCPUItems.contains(metricType.rawValue)
                    ) {
                        self.toggle(&self.viewModel.selectedCPUItems, item: metricType.rawValue)
                    }
                }
            } else {
                Text(L10n.tr("CPU metrics unavailable"))
                    .foregroundStyle(.secondary)
            }

        case .disk:
            if self.viewModel.diskStats != nil {
                ForEach(DiskMetricType.allCases, id: \.self) { metricType in
                    let value = metricType.rawValue < self.viewModel.formattedDiskValues.count
                        ? self.viewModel.formattedDiskValues[metricType.rawValue]
                        : "--"
                    self.selectableRow(
                        title: metricType.localizedName,
                        value: value,
                        isSelected: self.viewModel.selectedDiskItems.contains(metricType.rawValue)
                    ) {
                        self.toggle(&self.viewModel.selectedDiskItems, item: metricType.rawValue)
                    }
                }
            } else {
                Text(L10n.tr("Storage metrics unavailable"))
                    .foregroundStyle(.secondary)
            }

        case .system:
            let items = [
                (L10n.tr("Thermal State"), TelemetryTheme.localizedThermalState(self.viewModel.thermalState.rawValue)),
                (L10n.tr("Uptime"), self.viewModel.uptimeText),
                (L10n.tr("Device"), ProcessInfo.processInfo.isiOSAppOnMac ? "Mac (Designed for iPad)" : "iPad / iOS"),
                (L10n.tr("OS Version"), ProcessInfo.processInfo.operatingSystemVersionString),
            ]

            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(item.1)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func selectableRow(
        title: String,
        value: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, item: T) {
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
    }
}
