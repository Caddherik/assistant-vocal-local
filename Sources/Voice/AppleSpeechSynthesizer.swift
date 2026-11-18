import AVFoundation
import Foundation

/// Le texte redevient une voix, phrase par phrase.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onFirstAudio: (() -> Void)? { get set }
    var onFinishedAll: (() -> Void)? { get set }
    /// Nouveau tour de parole.
    func beginTurn()
    func enqueue(_ sentence: String, voice: AVSpeechSynthesisVoice?, rate: Float)
    /// Plus rien n'arrivera pour ce tour : `onFinishedAll` sera appelé quand la file sera vide.
    func finishTurn()
    func stop()
}

@MainActor
final class AppleSpeechSynthesizer: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    var onFirstAudio: (() -> Void)?
    var onFinishedAll: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var live: Set<ObjectIdentifier> = []
    private var turnClosed = false
    private var firstAudioReported = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func beginTurn() {
        live = []
        turnClosed = false
        firstAudioReported = false
    }

    func enqueue(_ sentence: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = rate
        live.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    func finishTurn() {
        turnClosed = true
        if live.isEmpty { onFinishedAll?() }
    }

    func stop() {
        live = []
        turnClosed = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func spokeFirstWord(of id: ObjectIdentifier) {
        guard live.contains(id), !firstAudioReported else { return }
        firstAudioReported = true
        onFirstAudio?()
    }

    private func finished(_ id: ObjectIdentifier) {
        guard live.remove(id) != nil else { return }
        if turnClosed, live.isEmpty { onFinishedAll?() }
    }

    // Le délégué peut être appelé hors du fil principal : on revient sur le MainActor.

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.spokeFirstWord(of: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}
