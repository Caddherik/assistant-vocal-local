import Foundation

/// Le chef d'orchestre : appui long → écoute → transcription → réponse en streaming → voix.
/// Toutes les transitions passent par lui ; il garde les tâches pour pouvoir tout annuler.
@MainActor
@Observable
final class AssistantController {
    private(set) var state: AssistantState = .idle
    private(set) var liveTranscript = ""
    private(set) var messages: [ChatMessage] = []

    let settings: AppSettings
    let metrics: MetricsRecorder

    @ObservationIgnored private let recognizer: any SpeechRecognizing
    @ObservationIgnored private let engine: any ChatEngine
    @ObservationIgnored private let voice: any SpeechSynthesizing
    @ObservationIgnored private let audio = AudioSessionManager()
    @ObservationIgnored private let locale = Locale(identifier: "fr-FR")

    @ObservationIgnored private var pressActive = false
    @ObservationIgnored private var recognizerRunning = false
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var chunker = SentenceChunker()
    @ObservationIgnored private var spokeSomething = false
    @ObservationIgnored private var pending: PendingMetrics?

    init(settings: AppSettings, metrics: MetricsRecorder) {
        self.settings = settings
        self.metrics = metrics
        recognizer = AppleSpeechRecognizer()
        engine = FoundationChatEngine(instructions: settings.effectiveInstructions)
        voice = AppleSpeechSynthesizer()

        voice.onFirstAudio = { [weak self] in self?.pending?.firstAudio = .now }
        voice.onFinishedAll = { [weak self] in self?.endExchange() }
        audio.onInterruption = { [weak self] in self?.cancelAll() }
        audio.onOutputLost = { [weak self] in self?.voice.stop() }
    }

    /// Au lancement : on charge le modèle tout de suite pour raccourcir le premier échange.
    func prepare() {
        engine.prewarm()
    }

    // MARK: - Le bouton

    func pressBegan() {
        guard !pressActive else { return }
        pressActive = true
        switch state {
        case .listening, .finalizing:
            return
        case .thinking, .speaking:
            interruptResponse()   // barge-in : on coupe et on écoute
        case .idle, .error:
            break
        }
        startListening()
    }

    func pressEnded() {
        guard pressActive else { return }
        pressActive = false
        guard state == .listening else { return }
        pending = PendingMetrics(speechEnd: .now)
        state = .finalizing
        if recognizerRunning {
            Task { await recognizer.stop() }
        }
        // Sinon, `startListening` verra que le bouton est relâché et arrêtera lui-même.
    }

    // MARK: - Écoute

    private func startListening() {
        liveTranscript = ""
        state = .listening
        listenTask = Task {
            do {
                try audio.activate()
                let stream = try await recognizer.start(locale: locale)
                recognizerRunning = true
                if !pressActive { await recognizer.stop() }
                for try await text in stream {
                    liveTranscript = text
                }
                recognizerRunning = false
                transcriptCompleted()
            } catch is CancellationError {
                recognizerRunning = false
            } catch {
                recognizerRunning = false
                fail(error.localizedDescription)
            }
        }
    }

    private func transcriptCompleted() {
        guard state == .finalizing else { return }
        pending?.finalText = .now
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            pending = nil
            state = .error("Je n'ai rien entendu. Maintiens le bouton pendant que tu parles.")
            audio.deactivate()
            return
        }
        respond(to: text)
    }

    // MARK: - Réponse

    private func respond(to text: String) {
        messages.append(ChatMessage(role: .user, text: text))
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)
        let replyID = reply.id

        state = .thinking
        chunker = SentenceChunker()
        spokeSomething = false
        voice.beginTurn()

        responseTask = Task {
            do {
                for try await cumulative in engine.respond(to: text) {
                    if pending?.firstToken == nil { pending?.firstToken = .now }
                    pending?.characters = cumulative.count
                    update(replyID, text: cumulative)
                    for sentence in chunker.feed(cumulative) { speak(sentence) }
                }
                try Task.checkCancellation()
                for sentence in chunker.flush() { speak(sentence) }
                pending?.lastToken = .now
                if case .speaking = state { state = .speaking(generating: false) }
                voice.finishTurn()
                if !spokeSomething { endExchange() }
            } catch is CancellationError {
                return
            } catch {
                let (message, mustReset) = FoundationChatEngine.message(for: error)
                if mustReset { engine.reset(instructions: settings.effectiveInstructions) }
                fail(message)
            }
        }
    }

    private func speak(_ sentence: String) {
        spokeSomething = true
        if state == .thinking { state = .speaking(generating: true) }
        voice.enqueue(sentence, voice: settings.resolvedVoice, rate: settings.speechRate)
    }

    private func update(_ id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    private func endExchange() {
        guard state.isResponding else { return }
        if let pending { metrics.record(pending.finish()) }
        pending = nil
        state = .idle
        audio.deactivate()
    }

    // MARK: - Annulations

    /// Barge-in : on garde le début de la réponse, on coupe le modèle et la voix.
    private func interruptResponse() {
        responseTask?.cancel()
        responseTask = nil
        voice.stop()
        pending = nil
        if let last = messages.indices.last, messages[last].role == .assistant {
            messages[last].text += " …"
        }
        state = .idle
    }

    /// Appel entrant, passage en arrière-plan : tout s'arrête, rien ne repart tout seul.
    func cancelAll() {
        pressActive = false
        listenTask?.cancel()
        listenTask = nil
        if recognizerRunning {
            recognizerRunning = false
            Task { await recognizer.cancel() }
        }
        if state.isResponding { interruptResponse() }
        pending = nil
        state = .idle
        audio.deactivate()
    }

    func newConversation() {
        cancelAll()
        messages = []
        liveTranscript = ""
        engine.reset(instructions: settings.effectiveInstructions)
    }

    private func fail(_ message: String) {
        voice.stop()
        pending = nil
        state = .error(message)
        audio.deactivate()
    }
}

/// Les horloges d'un échange en cours (voir l'architecture, §6).
struct PendingMetrics {
    let speechEnd: ContinuousClock.Instant
    var finalText: ContinuousClock.Instant?
    var firstToken: ContinuousClock.Instant?
    var firstAudio: ContinuousClock.Instant?
    var lastToken: ContinuousClock.Instant?
    var characters = 0

    init(speechEnd: ContinuousClock.Instant) {
        self.speechEnd = speechEnd
    }

    func finish() -> ExchangeMetrics {
        ExchangeMetrics(
            date: .now,
            toFinalText: finalText.map { $0 - speechEnd },
            toFirstToken: firstToken.map { $0 - speechEnd },
            firstTokenToFirstAudio: firstToken.flatMap { token in firstAudio.map { $0 - token } },
            toFirstAudio: firstAudio.map { $0 - speechEnd },
            generation: firstToken.flatMap { token in lastToken.map { $0 - token } },
            characters: characters,
            thermal: DiagnosticCollector.thermalLabel(ProcessInfo.processInfo.thermalState)
        )
    }
}
