import SwiftUI
import UIKit

struct DiagnosticView: View {
    @State private var sections: [DiagnosticSection] = []
    @State private var modelProbe = ModelProbe()
    @State private var voiceProbe = VoiceProbe()
    @State private var copied = false
    @State private var shareItems: [Any]?
    @Environment(MetricsRecorder.self) private var metrics

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

                Section {
                    ForEach(metrics.summary, id: \.label) { line in
                        LabeledContent(line.label, value: line.value).font(.callout)
                    }
                    ForEach(metrics.exchanges.suffix(10).reversed()) { exchange in
                        Text(MetricsRecorder.describe(exchange))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Échanges mesurés")
                } footer: {
                    Text("Médianes depuis l'ouverture de l'app. Le chrono part quand tu relâches le bouton.")
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
                    Button("Exporter", systemImage: "square.and.arrow.up") {
                        shareItems = Self.shareItems(for: report)
                    }
                }
            }
            .task { await reload() }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                ActivityView(items: shareItems ?? [])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Le rapport est construit AU MOMENT du tap (pas à l'affichage de l'écran), et partagé
    /// à la fois en texte (corps du mail) et en fichier .txt (pièce jointe).
    private static func shareItems(for report: String) -> [Any] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnostic-assistant.txt")
        guard (try? report.write(to: url, atomically: true, encoding: .utf8)) != nil else { return [report] }
        return [report, url]
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

/// La feuille de partage d'iOS (Mail, Notes, Messages…).
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
