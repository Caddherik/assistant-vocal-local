import AVFoundation
import Foundation

/// Les réglages, gardés sur l'iPhone (UserDefaults). Rien de personnel n'est écrit dans le code :
/// la consigne personnalisée (prénom, métier…) se saisit ici.
@MainActor
@Observable
final class AppSettings {
    static let defaultInstructions = """
    Tu es un assistant vocal personnel. Tu tutoies ton interlocuteur et tu réponds en français, \
    en deux à quatre phrases courtes, faites pour être écoutées : pas de liste, pas de titre, \
    pas de mise en forme. Si tu n'es pas sûr d'un fait — une dose, un chiffre, un diagnostic, \
    une date —, dis « je ne sais pas » plutôt que de deviner. Tu n'es pas une source médicale \
    ni vétérinaire. N'invente jamais de référence.
    """

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

    init() {
        voiceIdentifier = defaults.string(forKey: Keys.voice) ?? ""
        speechRate = defaults.object(forKey: Keys.rate) as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        instructions = defaults.string(forKey: Keys.instructions) ?? Self.defaultInstructions
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
        static let instructions = "instructions"
    }
}
