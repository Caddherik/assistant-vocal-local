import Foundation

/// Les états de l'assistant (voir la machine à états de l'architecture).
enum AssistantState: Equatable, Sendable {
    case idle
    case listening
    case finalizing
    case thinking
    case speaking(generating: Bool)
    case error(String)

    var label: String {
        switch self {
        case .idle: "Maintiens le bouton pour parler"
        case .listening: "Je t'écoute…"
        case .finalizing: "…"
        case .thinking: "Je réfléchis…"
        case .speaking: "Je parle — maintiens pour m'interrompre"
        case .error(let message): message
        }
    }

    var isResponding: Bool {
        switch self {
        case .thinking, .speaking: true
        default: false
        }
    }
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}
