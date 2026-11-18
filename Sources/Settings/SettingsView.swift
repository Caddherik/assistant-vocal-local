import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AssistantController.self) private var controller
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        @Bindable var settings = controller.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Voix", selection: $settings.voiceIdentifier) {
                        Text("La meilleure installée").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language) · \(Self.quality(voice.quality))").tag(voice.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Vitesse de parole")
                        Slider(value: $settings.speechRate, in: 0.35...0.65)
                    }
                } header: {
                    Text("Voix")
                } footer: {
                    Text("Une voix « Enhanced » ou « Premium » sonne bien mieux : Réglages › Accessibilité › Contenu énoncé › Voix.")
                }

                Section {
                    Picker("Longueur", selection: $settings.responseLength) {
                        ForEach(AppSettings.ResponseLength.allCases) { length in
                            Text(length.label).tag(length)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.responseLength) { controller.newConversation() }
                } header: {
                    Text("Longueur des réponses")
                } footer: {
                    Text("Changer la longueur démarre une nouvelle conversation.")
                }

                Section("Modèle") {
                    LabeledContent("Modèle", value: "Apple, sur l'iPhone")
                    LabeledContent("Second modèle (MLX)", value: "Phase 1b")
                }

                Section {
                    TextEditor(text: $settings.instructions)
                        .frame(minHeight: 220)
                        .font(.callout)
                    Button("Appliquer : nouvelle conversation") {
                        controller.newConversation()
                    }
                    Button("Revenir à la consigne par défaut", role: .destructive) {
                        settings.instructions = AppSettings.defaultInstructions
                    }
                } header: {
                    Text("Consigne du modèle")
                } footer: {
                    Text("Ajoute ici ton prénom ou ton métier : la consigne reste sur l'iPhone, elle n'est pas dans le code publié.")
                }
            }
            .navigationTitle("Réglages")
            .onAppear { voices = DiagnosticCollector.frenchVoices() }
        }
    }

    private static func quality(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "standard"
        }
    }
}
