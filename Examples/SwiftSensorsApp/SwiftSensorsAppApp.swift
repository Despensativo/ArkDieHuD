import SwiftUI

@main
struct SwiftSensorsAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sensorsViewModel = SensorsViewModel()
    @State private var hudController = PiPHUDController()

    var body: some Scene {
        WindowGroup {
            ContentView(hudController: hudController)
                .environment(\.sensorsViewModel, self.sensorsViewModel)
                .onOpenURL { url in
                    if url.scheme == "swiftsensors", url.host == "pip" {
                        hudController.prepareAudioAndStartPiP()
                    }
                }
                .onChange(of: self.scenePhase) { _, newPhase in
                    if newPhase == .inactive || newPhase == .background {
                        Task {
                            await TelemetryLogStore.shared.flushNow()
                        }
                    }
                }
        }
    }
}
