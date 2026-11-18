import SwiftUI
import UIKit

struct DiagnosticView: View {
    @State private var sections: [DiagnosticSection] = []
    @State private var modelProbe = ModelProbe()
    @State private var voiceProbe = VoiceProbe()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Tests") {
                    Button {
                        Task { await modelProbe.run() }
                    } label: {
                        Label(modelProbe.isRunning ? "Le modèle réfléchit…" : "Tester le modèle Apple", systemImage: "brain")
                    }
                    .disabled(modelProbe.isRunning)
                    Text(modelProbe.summary).font(.footnote).foregroundStyle(.secondary)
                    if !modelProbe.answer.isEmpty {
                        Text(modelProbe.answer).font(.callout)
                    }

                    Button {
                        voiceProbe.speak()
                    } label: {
                        Label("Tester la voix", systemImage: "speaker.wave.2")
                    }
                    Text(voiceProbe.result).font(.footnote).foregroundStyle(.secondary)

                    Button {
                        Task {
                            await PermissionRequester.requestAll()
                            await reload()
                        }
                    } label: {
                        Label("Autoriser micro et reconnaissance vocale", systemImage: "mic")
                    }
                }

                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.lines) { line in
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.status.symbol)
                                Text(line.label)
                                Spacer(minLength: 12)
                                Text(line.value)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostic")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Actualiser", systemImage: "arrow.clockwise") {
                        Task { await reload() }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = report
                        copied = true
                    }
                    ShareLink(item: report) {
                        Label("Exporter", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        sections = await DiagnosticCollector.collect()
        copied = false
    }

    /// Le rapport en texte brut, à coller dans le journal du projet.
    private var report: String {
        var text = "Diagnostic — Assistant vocal local\n"
        text += Date.now.formatted(date: .numeric, time: .standard) + "\n"
        for section in sections {
            text += "\n## \(section.title)\n"
            for line in section.lines {
                text += "\(line.status.symbol) \(line.label) : \(line.value)\n"
            }
        }
        text += "\n## Tests\n"
        text += "Modèle Apple : \(modelProbe.summary)\n"
        if !modelProbe.answer.isEmpty { text += "Réponse : \(modelProbe.answer)\n" }
        text += "Voix : \(voiceProbe.result)\n"
        return text
    }
}
