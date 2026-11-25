import SwiftSensors
import SwiftUI

/// Primary instrument dashboard for hardware thermals, PiP HUD launch, Slide Over,
/// and deep kernel diagnostics.
struct ContentView: View {
    @Environment(\.sensorsViewModel) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @Bindable var hudController: PiPHUDController
    @State private var navigationPath = NavigationPath()
    @State private var showCustomizationSheet: Bool = false

    private var config: TelemetryVisibilityConfig {
        self.hudController.visibilityConfig
    }

    private var visibleDashboardSections: [SensorSection] {
        SensorSection.allCases.filter { self.config.isDashboardSectionVisible($0) }
    }

    private var sectionColumns: [GridItem] {
        let count = (self.horizontalSizeClass == .regular) ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: TelemetryTheme.gridSpacing), count: count)
    }

    var body: some View {
        let showLiveStrip = self.config.showDashboardLiveStrip && self.config.hasAnyMetricEnabled
        let showPiPCard = self.config.showDashboardPiPCard
        let sections = self.visibleDashboardSections
        let showGrid = self.config.showDashboardSensorsGrid && !sections.isEmpty

        NavigationStack(path: self.$navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: TelemetryTheme.sectionSpacing) {
                    ArkDieBrandLogoView(style: .header)

                    if !showLiveStrip && !showPiPCard && !showGrid {
                        ContentUnavailableView {
                            Label(L10n.tr("Dashboard Hidden"), systemImage: "slider.horizontal.3")
                        } description: {
                            Text(L10n.tr("All main dashboard sections have been disabled."))
                        } actions: {
                            Button(L10n.tr("Customize Dashboard")) {
                                self.showCustomizationSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        if showLiveStrip {
                            LiveTelemetryStripView(
                                snapshot: self.hudController.latestSnapshot,
                                config: self.config
                            )
                        }

                        if showPiPCard {
                            HUDDashboardSection(hudController: self.hudController)
                        }

                        if showGrid {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tr("Sensors & Diagnostics"))
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)

                                LazyVGrid(columns: self.sectionColumns, spacing: TelemetryTheme.gridSpacing) {
                                    ForEach(sections, id: \.self) { section in
                                        NavigationLink(value: NavigationDestination.sectionDetail(section: section)) {
                                            self.sectionTile(section)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(TelemetryTheme.groupedBackground)
            .navigationTitle("ArkDieHuD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(L10n.tr("Customize"), systemImage: "slider.horizontal.3") {
                        self.showCustomizationSheet = true
                    }

                    Button(
                        self.hudController.isPiPActive ? L10n.tr("Close PiP") : L10n.tr("HUD PiP"),
                        systemImage: self.hudController.isPiPActive ? "pip.exit" : "pip.enter"
                    ) {
                        if self.hudController.isPiPActive {
                            self.hudController.stopPiP()
                        } else {
                            self.hudController.prepareAudioAndStartPiP()
                        }
                    }
                    .disabled(!self.hudController.isSupported)
                    .sensoryFeedback(.impact(weight: .medium), trigger: self.hudController.isPiPActive)
                }
            }
            .sheet(isPresented: self.$showCustomizationSheet) {
                TelemetryCustomizationSheetView(hudController: self.hudController)
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .sensorDetail(let sensorName):
                    SensorDetailView(sensorName: sensorName)
                case .sectionDetail(let section):
                    if section == .network {
                        NetworkDiagnosticsView(hudController: self.hudController)
                    } else if section == .telemetryLogs {
                        TelemetryLogsView(hudController: self.hudController)
                    } else {
                        SectionDetailView(section: section)
                    }
                case .slideOver:
                    SlideOverHUDView(hudController: self.hudController)
                case .networkDiagnostics:
                    NetworkDiagnosticsView(hudController: self.hudController)
                case .telemetryLogs:
                    TelemetryLogsView(hudController: self.hudController)
                }
            }
            .task {
                while !Task.isCancelled {
                    if self.scenePhase == .active {
                        self.viewModel.updateIfNeeded()
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func sectionTile(_ section: SensorSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.localizedTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(
                    section.subtitle(
                        from: self.viewModel,
                        snapshot: self.hudController.latestSnapshot,
                        isRecordingLogs: self.hudController.isRecordingLogs
                    )
                )
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, TelemetryTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                .fill(TelemetryTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: TelemetryTheme.compactCornerRadius)
                        .strokeBorder(TelemetryTheme.subtleBorder, lineWidth: 1)
                )
        )
    }
}

private extension SensorSection {
    var systemImage: String {
        switch self {
        case .network: return "network"
        case .telemetryLogs: return "externaldrive.badge.timemachine"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .thermal: return "thermometer.medium"
        case .voltage: return "bolt.circle"
        case .current: return "waveform.path"
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .disk: return "internaldrive"
        case .system: return "ipad"
        }
    }

    @MainActor
    func subtitle(from viewModel: SensorsViewModel, snapshot: TelemetrySnapshot, isRecordingLogs: Bool) -> String {
        switch self {
        case .network:
            let net = snapshot.network
            let ping = net.isLastProbeLost ? "DROP" : (net.pingMs.map { String(format: "%.0f ms", $0) } ?? "-- ms")
            return L10n.fmt("%@ • %@ • %.1f%% Loss", net.target.host, ping, net.totalLossPercent)
        case .telemetryLogs:
            return isRecordingLogs
                ? L10n.tr("24h recording active • SQLite WAL")
                : L10n.tr("24h recording paused")
        case .performance:
            let threads = viewModel.threadSummary?.totalThreads ?? 0
            return threads > 0
                ? L10n.fmt("Mach VM • %lld active threads", threads)
                : L10n.tr("Mach VM, Threads & Jetsam")
        case .thermal:
            return L10n.fmt("%lld IOHID sensors", viewModel.thermalSensorReadings.count)
        case .voltage:
            return L10n.fmt("%lld voltage rails", viewModel.voltageSensorReadings.count)
        case .current:
            return L10n.fmt("%lld current sensors", viewModel.currentSensorReadings.count)
        case .memory:
            return viewModel.formattedMemoryValues.indices.contains(6)
                ? L10n.fmt("In use: %@", viewModel.formattedMemoryValues[6])
                : L10n.tr("Mach VM Statistics")
        case .cpu:
            return viewModel.formattedCPUValues.first.map { L10n.fmt("Total load: %@", $0) } ?? L10n.tr("Kernel CPU")
        case .disk:
            return viewModel.formattedDiskValues.indices.contains(2)
                ? L10n.fmt("Free: %@", viewModel.formattedDiskValues[2])
                : L10n.tr("Storage space")
        case .system:
            return TelemetryTheme.localizedThermalState(viewModel.thermalState.rawValue)
        }
    }
}
