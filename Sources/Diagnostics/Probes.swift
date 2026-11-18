import AVFoundation
import Foundation
import FoundationModels
import Speech

/// Test du modèle Apple : une question courte, en streaming, chronométrée.
@MainActor
@Observable
final class ModelProbe {
    private(set) var isRunning = false
    private(set) var answer = ""
    private(set) var timeToFirstToken: Duration?
    private(set) var totalTime: Duration?
    private(set) var errorMessage: String?

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        answer = ""
        timeToFirstToken = nil
        totalTime = nil
        errorMessage = nil
        defer { isRunning = false }

        let instructions: String = "Tu es un assistant vocal. Réponds en français, en une ou deux phrases courtes."
        let prompt: String = "Présente-toi, puis donne-moi une astuce pour bien dormir."
        let session = LanguageModelSession(instructions: instructions)
        let clock = ContinuousClock()
        let start = clock.now

        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                if timeToFirstToken == nil { timeToFirstToken = clock.now - start }
                answer = snapshot.content
            }
            totalTime = clock.now - start
        } catch {
            errorMessage = String(describing: error)
        }
    }

    var summary: String {
        if let errorMessage { return "Erreur : \(errorMessage)" }
        guard let totalTime else { return "pas encore lancé" }
        let first = timeToFirstToken.map(Self.seconds) ?? "?"
        return "1er token \(first) · total \(Self.seconds(totalTime)) · \(answer.count) caractères"
    }

    static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2f s", value)
    }
}

/// Test de la voix : une phrase avec la meilleure voix française installée,
/// chronométrée jusqu'au premier son.
@MainActor
@Observable
final class VoiceProbe: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let clock = ContinuousClock()
    private var start: ContinuousClock.Instant?
    private(set) var result = "pas encore lancé"

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            result = "Erreur audio : \(error.localizedDescription)"
            return
        }
        let utterance = AVSpeechUtterance(string: "Bonjour. Ceci est un test de la voix française, entièrement sur ton iPhone.")
        let voice = DiagnosticCollector.frenchVoices().first
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "fr-FR")
        result = "voix : \(voice?.name ?? "fr-FR par défaut")…"
        start = clock.now
        synthesizer.speak(utterance)
    }

    private func didStart(at instant: ContinuousClock.Instant) {
        guard let start else { return }
        let voiceName = DiagnosticCollector.frenchVoices().first?.name ?? "fr-FR par défaut"
        result = "voix : \(voiceName) · 1er son après \(ModelProbe.seconds(instant - start))"
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let now = ContinuousClock.now
        Task { @MainActor in self.didStart(at: now) }
    }
}

/// Les deux autorisations dont l'assistant aura besoin (micro, reconnaissance vocale).
@MainActor
enum PermissionRequester {
    static func requestAll() async {
        _ = await AVAudioApplication.requestRecordPermission()
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
