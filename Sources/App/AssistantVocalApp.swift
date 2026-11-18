import SwiftUI

@main
struct AssistantVocalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Assistant", systemImage: "waveform") {
                AssistantPlaceholderView()
            }
            Tab("Diagnostic", systemImage: "stethoscope") {
                DiagnosticView()
            }
        }
    }
}

/// Phase 1a, étape 1 : seul l'écran Diagnostic est livré.
/// Le chat vocal arrive une fois la disponibilité du modèle Apple confirmée sur l'iPhone.
struct AssistantPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Bientôt",
            systemImage: "mic.badge.plus",
            description: Text("Ouvre l'onglet Diagnostic, lance les tests, puis exporte le rapport.")
        )
    }
}
