import AVFoundation
import Foundation
import Speech

/// La parole devient du texte.
@MainActor
protocol SpeechRecognizing: AnyObject {
    /// Démarre l'écoute. Le flux renvoie le texte reconnu jusqu'ici (cumulé), puis se termine
    /// après `stop()` avec le texte final.
    func start(locale: Locale) async throws -> AsyncThrowingStream<String, Error>
    /// Fin de l'appui long : on finalise ce qui a été dit.
    func stop() async
    /// Interruption : on jette tout.
    func cancel() async
}

enum SpeechRecognitionError: LocalizedError {
    case microphoneUnavailable
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "Le micro n'est pas disponible. Autorise-le dans l'onglet Diagnostic."
        case .formatUnavailable: "La reconnaissance vocale n'accepte pas le format du micro."
        }
    }
}

/// SpeechAnalyzer + SpeechTranscriber (iOS 26+), entièrement sur l'iPhone.
@MainActor
final class AppleSpeechRecognizer: SpeechRecognizing {
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func start(locale: Locale) async throws -> AsyncThrowingStream<String, Error> {
        let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechRecognitionError.formatUnavailable
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let microphoneFormat = input.outputFormat(forBus: 0)
        guard microphoneFormat.sampleRate > 0, microphoneFormat.channelCount > 0 else {
            throw SpeechRecognitionError.microphoneUnavailable
        }
        guard let converter = AVAudioConverter(from: microphoneFormat, to: analyzerFormat) else {
            throw SpeechRecognitionError.formatUnavailable
        }

        let (inputs, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: inputs)

        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: microphoneFormat,
            block: Self.makeTapBlock(converter: converter, format: analyzerFormat, builder: builder)
        )
        engine.prepare()
        try engine.start()

        audioEngine = engine
        self.analyzer = analyzer
        inputBuilder = builder

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        continuation.yield(finalized)
                    } else {
                        continuation.yield(finalized + text)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func stop() async {
        stopAudio()
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
    }

    func cancel() async {
        stopAudio()
        inputBuilder?.finish()
        inputBuilder = nil
        resultsTask?.cancel()
        resultsTask = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }

    private func stopAudio() {
        guard let audioEngine else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine = nil
    }

    /// Le bloc appelé par le micro, sur un fil audio temps réel : il est construit hors du
    /// MainActor (fonction `nonisolated`), sinon Swift 6 le croirait lié au fil principal.
    nonisolated private static func makeTapBlock(
        converter: AVAudioConverter,
        format: AVAudioFormat,
        builder: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {


        return { buffer, _ in
            nonisolated(unsafe) let source = buffer
            let ratio = format.sampleRate / source.format.sampleRate
            let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            let delivered = DeliveredFlag()
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                if delivered.value {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                delivered.value = true
                inputStatus.pointee = .haveData
                return source
            }
            if status != .error, converted.frameLength > 0 {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}

/// Indique si le tampon du micro a déjà été donné au convertisseur (une fois par appel).
private final class DeliveredFlag: @unchecked Sendable {
    var value = false
}
