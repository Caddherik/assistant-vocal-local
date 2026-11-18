import Foundation
import FoundationModels

/// Notre couche au-dessus du protocole `LanguageModel` d'Apple. Elle ne connaît que le texte :
/// aucun outil (et surtout pas le web) n'est donné au modèle.
@MainActor
protocol ChatEngine: AnyObject {
    func prewarm()
    /// Le texte de la réponse, cumulé, au fil de la génération.
    func respond(to prompt: String) -> AsyncThrowingStream<String, Error>
    func reset(instructions: String)
}

/// Le modèle Apple, sur l'iPhone. La session est gardée ouverte (elle porte l'historique
/// de la conversation) et préchauffée pour raccourcir le premier token.
@MainActor
final class FoundationChatEngine: ChatEngine {
    private var session: LanguageModelSession

    init(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
    }

    func prewarm() {
        session.prewarm()
    }

    func reset(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
        session.prewarm()
    }

    func respond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        let task = Task {
            do {
                for try await snapshot in self.session.streamResponse(to: prompt) {
                    continuation.yield(snapshot.content)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Une erreur du modèle, dite en français.
    static func message(for error: Error) -> (text: String, mustReset: Bool) {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return ("Erreur du modèle : \(error.localizedDescription)", false)
        }
        switch generationError {
        case .exceededContextWindowSize:
            return ("La conversation est trop longue pour le modèle : je repars d'une page blanche.", true)
        case .guardrailViolation:
            return ("Le filtre de sécurité d'Apple a bloqué cette réponse. Il refuse certains sujets, comme les stupéfiants, et je ne peux pas le désactiver.", false)
        case .unsupportedLanguageOrLocale:
            return ("Le modèle ne prend pas en charge cette langue.", false)
        case .assetsUnavailable:
            return ("Le modèle Apple n'est pas prêt (téléchargement en cours ?).", false)
        default:
            return ("Erreur du modèle : \(generationError.localizedDescription)", false)
        }
    }
}
