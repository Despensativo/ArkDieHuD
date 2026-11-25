import SwiftSensors
import SwiftUI

/// Deep Performance & Darwin Kernel SLA telemetry section (Mach VM, Jetsam, Threads).
struct PerformanceSectionView: View {
    @Bindable var viewModel: SensorsViewModel

    var body: some View {
        Group {
            // MARK: - Mach VM & Jetsam Early Warning
            Section(header: Text(L10n.tr("Low-Level Memory (Mach VM & Jetsam)"))) {
                if let vm = self.viewModel.vmMetrics {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Dirty Ratio (Jetsam Alert)"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", vm.dirtyRatio * 100.0))
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundStyle(vm.isJetsamRisk ? .red : .green)
                        }
                        Spacer()
                        Label(
                            vm.isJetsamRisk ? L10n.tr("Critical Alert") : L10n.tr("Safe"),
                            systemImage: vm.isJetsamRisk ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                        )
                        .font(.footnote.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (vm.isJetsamRisk ? Color.red : Color.green).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(vm.isJetsamRisk ? .red : .green)
                    }
                    .padding(.vertical, 4)

                    InfoRow(label: "Physical Footprint", value: String(format: "%.2f MB", vm.physicalFootprintMB))
                    InfoRow(label: "Resident Size", value: String(format: "%.2f MB", Double(vm.residentSizeBytes) / 1_048_576.0))
                    InfoRow(label: "Internal Dirty Pages", value: String(format: "%.2f MB", Double(vm.internalDirtyBytes) / 1_048_576.0))
                    InfoRow(label: "Compressed Pages", value: String(format: "%.2f MB", Double(vm.compressedDirtyBytes) / 1_048_576.0))
                    if let remaining = vm.jetsamLimitRemainingMB {
                        InfoRow(label: L10n.tr("Headroom to Jetsam Kill"), value: L10n.fmt("%.0f MB remaining", remaining))
                    }
                    InfoRow(label: L10n.tr("Mapped VM Regions"), value: "\(vm.mappedRegionsCount)")

                    Button(role: .destructive) {
                        self.viewModel.triggerEmergencyPurge()
                    } label: {
                        Label(
                            self.viewModel.lastPurgeTime == nil
                                ? L10n.tr("Run Preventive Memory Purge")
                                : L10n.tr("Purge Executed (Caches Recycled)"),
                            systemImage: "trash.circle"
                        )
                        .frame(maxWidth: .infinity, minHeight: TelemetryTheme.minTouchTarget - 10)
                    }
                    .buttonStyle(.bordered)
                    .sensoryFeedback(.success, trigger: self.viewModel.lastPurgeTime)
                } else {
                    Text(L10n.tr("Loading Mach VM metrics..."))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Mach Thread CPU Scheduling & Starvation
            Section(header: Text(L10n.tr("Mach Thread Scheduling (task_threads)"))) {
                if let threads = self.viewModel.threadSummary {
                    InfoRow(label: L10n.tr("Total Threads"), value: "\(threads.totalThreads)")
                    InfoRow(label: L10n.tr("Running Threads"), value: "\(threads.runningThreads)")
                    InfoRow(label: L10n.tr("Waiting Threads"), value: "\(threads.waitingThreads)")

                    HStack {
                        Text(L10n.tr("Main Thread State"))
                        Spacer()
                        Label(
                            threads.isMainThreadStarved ? L10n.tr("Contention / Lock") : L10n.tr("Normal"),
                            systemImage: threads.isMainThreadStarved ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(threads.isMainThreadStarved ? .orange : .green)
                    }

                    ForEach(threads.topThreads) { thread in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(thread.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(thread.isMainThread ? Color.accentColor : .primary)
                                Spacer()
                                Text(String(format: "%.1f%% CPU", thread.cpuUsagePercent))
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                    .foregroundStyle(thread.cpuUsagePercent > 20 ? .orange : .secondary)
                            }
                            HStack {
                                Text(L10n.fmt("State: %@ • Pri: %lld", thread.runState.rawValue, thread.priority))
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if thread.sleepTimeSeconds > 0 {
                                    Text("Sleep: \(thread.sleepTimeSeconds)s")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text(L10n.tr("Loading process threads..."))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Deep VM Region Scanner
            Section(header: Text(L10n.tr("Mapped VM Region Scanner (>1MB)"))) {
                Button {
                    self.viewModel.scanLargeVMRegions()
                } label: {
                    Label(
                        self.viewModel.isScanningVM ? L10n.tr("Scanning Address Space...") : L10n.tr("Scan Large VM Regions"),
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, minHeight: TelemetryTheme.minTouchTarget - 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.viewModel.isScanningVM)
                .sensoryFeedback(.impact(weight: .light), trigger: self.viewModel.largeVMRegions.count)

                if !self.viewModel.largeVMRegions.isEmpty {
                    ForEach(self.viewModel.largeVMRegions) { region in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "0x%llX", region.address))
                                    .font(.system(.footnote, design: .monospaced))
                                Text(region.isWritable ? L10n.tr("Writable") : L10n.tr("Read-Only"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.2f MB", region.sizeMB))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(region.sizeMB > 10 ? .orange : .primary)
                        }
                    }
                } else if !self.viewModel.isScanningVM {
                    Text(L10n.tr("No large suspicious blocks detected at this time."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
