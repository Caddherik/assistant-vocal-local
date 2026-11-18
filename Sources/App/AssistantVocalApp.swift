import SwiftUI

@main
struct AssistantVocalApp: App {
    @State private var controller = AssistantController(settings: AppSettings(), metrics: MetricsRecorder())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
                .environment(controller.metrics)
        }
    }
}

struct RootView: View {
    @Environment(AssistantController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Assistant", systemImage: "waveform") {
                AssistantView()
            }
            Tab("Réglages", systemImage: "slider.horizontal.3") {
                SettingsView()
            }
            Tab("Diagnostic", systemImage: "stethoscope") {
                DiagnosticView()
            }
        }
        .task { controller.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.cancelAll() }
        }
    }
}
