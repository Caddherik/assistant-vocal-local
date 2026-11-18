import AVFoundation
import Foundation

/// Les réglages, gardés sur l'iPhone (UserDefaults). Rien de personnel n'est écrit dans le code :
/// la consigne personnalisée (prénom, métier…) se saisit ici.
@MainActor
@Observable
final class AppSettings {
    /// La consigne de base, sans la longueur (réglée à part, voir `ResponseLength`).
    static let defaultInstructions = """
    Tu es un assistant vocal personnel. Tu tutoies ton interlocuteur et tu réponds en français, \
    avec des phrases faites pour être écoutées : pas de liste à puces, pas de titre, pas de mise \
    en forme. Réponds vraiment à la question : donne le raisonnement, les éléments utiles et un \
    exemple concret quand ça aide. Sur la santé humaine ou animale, donne les informations \
    générales que tu connais ; si tu n'es pas sûr d'un chiffre précis (une dose, une valeur, une \
    date), dis-le clairement au lieu de deviner. N'invente jamais de référence.
    """

    /// La longueur des réponses : ajoutée à la consigne par le code.
    enum ResponseLength: String, CaseIterable, Identifiable {
        case short, normal, detailed

        var id: String { rawValue }

        var label: String {
            switch self {
            case .short: "Courte"
            case .normal: "Normale"
            case .detailed: "Détaillée"
            }
        }

        var instruction: String {
            switch self {
            case .short: "Réponds en deux ou trois phrases."
            case .normal: "Réponds en un ou deux paragraphes, de cinq à huit phrases."
            case .detailed: "Développe ta réponse en plusieurs paragraphes, comme un collègue qui explique en détail."
            }
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voice) }
    }

    var speechRate: Float {
        didSet { defaults.set(speechRate, forKey: Keys.rate) }
    }

    var instructions: String {
        didSet { defaults.set(instructions, forKey: Keys.instructions) }
    }

    var responseLength: ResponseLength {
        didSet { defaults.set(responseLength.rawValue, forKey: Keys.length) }
    }

    /// Ce que reçoit vraiment le modèle : la consigne + la longueur.
    var effectiveInstructions: String {
        instructions + "\n" + responseLength.instruction
    }

    init() {
        voiceIdentifier = defaults.string(forKey: Keys.voice) ?? ""
        speechRate = defaults.object(forKey: Keys.rate) as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        instructions = defaults.string(forKey: Keys.instructions) ?? Self.defaultInstructions
        responseLength = defaults.string(forKey: Keys.length).flatMap(ResponseLength.init(rawValue:)) ?? .normal
    }

    /// La voix choisie, ou à défaut la meilleure voix française installée.
    var resolvedVoice: AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice
        }
        return DiagnosticCollector.frenchVoices().first ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }

    private enum Keys {
        static let voice = "voiceIdentifier"
        static let rate = "speechRate"
        // Nouvelle clé : l'ancienne consigne (2 à 4 phrases) est abandonnée.
        static let instructions = "instructions.v2"
        static let length = "responseLength"
    }
}
