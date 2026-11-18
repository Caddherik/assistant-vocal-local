import Foundation

/// Les mesures d'un échange complet, prises par l'app elle-même (pas d'Instruments sans Mac).
struct ExchangeMetrics: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    /// Fin de parole (bouton relâché) → texte final de la transcription.
    let toFinalText: Duration?
    /// Fin de parole → premier token du modèle.
    let toFirstToken: Duration?
    /// Premier token → premier mot prononcé.
    let firstTokenToFirstAudio: Duration?
    /// Fin de parole → premier mot prononcé : ce que l'oreille ressent.
    let toFirstAudio: Duration?
    /// Premier → dernier token.
    let generation: Duration?
    let characters: Int
    let thermal: String
}

@MainActor
@Observable
final class MetricsRecorder {
    private(set) var exchanges: [ExchangeMetrics] = []

    func record(_ metrics: ExchangeMetrics) {
        exchanges.append(metrics)
        if exchanges.count > 50 { exchanges.removeFirst() }
    }

    /// Les médianes, sur tous les échanges mesurés depuis l'ouverture de l'app.
    var summary: [(label: String, value: String)] {
        [
            ("Échanges mesurés", "\(exchanges.count)"),
            ("Fin de parole → texte final", Self.median(exchanges.map(\.toFinalText))),
            ("Fin de parole → 1er token", Self.median(exchanges.map(\.toFirstToken))),
            ("1er token → 1er mot dit", Self.median(exchanges.map(\.firstTokenToFirstAudio))),
            ("Fin de parole → 1er mot dit", Self.median(exchanges.map(\.toFirstAudio))),
            ("Durée de génération", Self.median(exchanges.map(\.generation))),
        ]
    }

    var report: String {
        var text = "## Échanges mesurés (médianes)\n"
        for line in summary { text += "• \(line.label) : \(line.value)\n" }
        for (index, exchange) in exchanges.enumerated() {
            text += "\(index + 1). " + Self.describe(exchange) + "\n"
        }
        return text
    }

    static func describe(_ exchange: ExchangeMetrics) -> String {
        "texte \(format(exchange.toFinalText)) · 1er token \(format(exchange.toFirstToken)) · "
            + "1er mot \(format(exchange.toFirstAudio)) · génération \(format(exchange.generation)) · "
            + "\(exchange.characters) car. · \(exchange.thermal)"
    }

    static func format(_ duration: Duration?) -> String {
        duration.map(ModelProbe.seconds) ?? "–"
    }

    private static func median(_ values: [Duration?]) -> String {
        let sorted = values.compactMap { $0 }.sorted()
        guard !sorted.isEmpty else { return "–" }
        return ModelProbe.seconds(sorted[sorted.count / 2])
    }
}
