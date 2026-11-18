import AVFoundation
import Foundation
import FoundationModels
import Speech
import UIKit
import os

struct DiagnosticLine: Identifiable, Sendable {
    enum Status: Sendable {
        case ok, warning, problem, info

        var symbol: String {
            switch self {
            case .ok: "✅"
            case .warning: "⚠️"
            case .problem: "❌"
            case .info: "•"
            }
        }
    }

    let id = UUID()
    let label: String
    let value: String
    let status: Status
}

struct DiagnosticSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let lines: [DiagnosticLine]
}

/// Rassemble ce que l'iPhone sait de lui-même. Aucune donnée ne sort de l'appareil :
/// le rapport n'est partagé que si l'utilisateur appuie sur « Exporter ».
@MainActor
enum DiagnosticCollector {
    static func collect() async -> [DiagnosticSection] {
        [
            device(),
            appleIntelligence(),
            await speech(),
            voices(),
        ]
    }

    // MARK: - Appareil

    private static func device() -> DiagnosticSection {
        let info = ProcessInfo.processInfo
        let available = os_proc_available_memory()
        return DiagnosticSection(title: "Appareil", lines: [
            DiagnosticLine(label: "Modèle (identifiant)", value: machineIdentifier(), status: .info),
            DiagnosticLine(label: "Système", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)", status: .info),
            DiagnosticLine(label: "RAM totale", value: gigabytes(info.physicalMemory), status: .info),
            DiagnosticLine(
                label: "Mémoire encore disponible pour l'app",
                value: gigabytes(UInt64(max(available, 0))),
                status: available > 3 * 1_073_741_824 ? .ok : .warning
            ),
            DiagnosticLine(label: "Cœurs", value: "\(info.processorCount) (\(info.activeProcessorCount) actifs)", status: .info),
            DiagnosticLine(label: "État thermique", value: thermalLabel(info.thermalState), status: thermalStatus(info.thermalState)),
            DiagnosticLine(label: "Mode économie d'énergie", value: info.isLowPowerModeEnabled ? "activé" : "désactivé", status: .info),
            DiagnosticLine(label: "Langue de l'appareil", value: Locale.preferredLanguages.first ?? "?", status: .info),
            DiagnosticLine(label: "Région", value: Locale.current.region?.identifier ?? "?", status: .info),
        ])
    }

    // MARK: - Apple Intelligence (Foundation Models)

    private static func appleIntelligence() -> DiagnosticSection {
        let model = SystemLanguageModel.default
        var lines: [DiagnosticLine] = []

        switch model.availability {
        case .available:
            lines.append(DiagnosticLine(label: "Modèle Apple sur l'appareil", value: "disponible", status: .ok))
        case .unavailable(let reason):
            lines.append(DiagnosticLine(label: "Modèle Apple sur l'appareil", value: "indisponible : \(unavailableLabel(reason))", status: .problem))
        }

        let french = model.supportsLocale(Locale(identifier: "fr_FR"))
        lines.append(DiagnosticLine(label: "Français pris en charge", value: french ? "oui" : "non", status: french ? .ok : .problem))

        let languages = model.supportedLanguages
            .map { $0.minimalIdentifier }
            .sorted()
            .joined(separator: ", ")
        lines.append(DiagnosticLine(label: "Langues du modèle", value: languages.isEmpty ? "aucune" : languages, status: .info))
        lines.append(DiagnosticLine(label: "Taille du contexte", value: "\(model.contextSize) tokens", status: .info))

        return DiagnosticSection(title: "Apple Intelligence", lines: lines)
    }

    private static func unavailableLabel(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "appareil non éligible"
        case .appleIntelligenceNotEnabled: "Apple Intelligence n'est pas activée"
        case .modelNotReady: "modèle pas encore prêt (téléchargement en cours ?)"
        @unknown default: "raison inconnue (\(String(describing: reason)))"
        }
    }

    // MARK: - Reconnaissance vocale

    private static func speech() async -> DiagnosticSection {
        var lines: [DiagnosticLine] = []

        let transcriberLocales = await SpeechTranscriber.supportedLocales
        let transcriberFrench = transcriberLocales.contains { $0.language.languageCode?.identifier == "fr" }
        lines.append(DiagnosticLine(
            label: "SpeechTranscriber : français",
            value: transcriberFrench ? "pris en charge" : "absent",
            status: transcriberFrench ? .ok : .problem
        ))
        lines.append(DiagnosticLine(label: "SpeechTranscriber : variantes fr", value: frenchVariants(transcriberLocales), status: .info))

        let installed = await SpeechTranscriber.installedLocales
        lines.append(DiagnosticLine(label: "SpeechTranscriber : déjà installé", value: frenchVariants(installed), status: .info))

        let dictationLocales = await DictationTranscriber.supportedLocales
        let dictationFrench = dictationLocales.contains { $0.language.languageCode?.identifier == "fr" }
        lines.append(DiagnosticLine(
            label: "DictationTranscriber : français",
            value: dictationFrench ? "pris en charge" : "absent",
            status: dictationFrench ? .ok : .warning
        ))

        let legacy = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
        let onDevice = legacy?.supportsOnDeviceRecognition ?? false
        lines.append(DiagnosticLine(label: "Ancienne API, sur l'appareil (fr-FR)", value: onDevice ? "oui" : "non", status: onDevice ? .ok : .info))

        lines.append(DiagnosticLine(label: "Autorisation reconnaissance vocale", value: speechAuthorizationLabel(), status: speechAuthorizationStatus()))
        lines.append(DiagnosticLine(label: "Autorisation micro", value: microphoneLabel(), status: microphoneStatus()))

        return DiagnosticSection(title: "Reconnaissance vocale", lines: lines)
    }

    private static func frenchVariants(_ locales: [Locale]) -> String {
        let french = locales
            .filter { $0.language.languageCode?.identifier == "fr" }
            .map(\.identifier)
            .sorted()
        return french.isEmpty ? "aucune" : french.joined(separator: ", ")
    }

    private static func speechAuthorizationLabel() -> String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "accordée"
        case .denied: "refusée"
        case .restricted: "restreinte"
        case .notDetermined: "pas encore demandée"
        @unknown default: "inconnue"
        }
    }

    private static func speechAuthorizationStatus() -> DiagnosticLine.Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .ok
        case .notDetermined: .warning
        default: .problem
        }
    }

    private static func microphoneLabel() -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "accordée"
        case .denied: "refusée"
        case .undetermined: "pas encore demandée"
        @unknown default: "inconnue"
        }
    }

    private static func microphoneStatus() -> DiagnosticLine.Status {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .ok
        case .undetermined: .warning
        default: .problem
        }
    }

    // MARK: - Voix

    private static func voices() -> DiagnosticSection {
        let french = frenchVoices()
        guard !french.isEmpty else {
            return DiagnosticSection(title: "Voix françaises", lines: [
                DiagnosticLine(label: "Voix installées", value: "aucune", status: .problem),
            ])
        }
        let hasGoodVoice = french.contains { $0.quality != .default }
        var lines = [DiagnosticLine(
            label: "Voix Premium ou Enhanced",
            value: hasGoodVoice ? "présente" : "absente : télécharge-la dans Réglages › Accessibilité › Contenu énoncé › Voix",
            status: hasGoodVoice ? .ok : .warning
        )]
        lines += french.map { voice in
            DiagnosticLine(label: voice.name, value: "\(voice.language) · \(qualityLabel(voice.quality))", status: .info)
        }
        return DiagnosticSection(title: "Voix françaises", lines: lines)
    }

    /// Les voix françaises, la meilleure qualité en premier.
    static func frenchVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        case .default: "standard"
        @unknown default: "inconnue"
        }
    }

    // MARK: - Utilitaires

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.2f Go", Double(bytes) / 1_073_741_824)
    }

    nonisolated static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "normal"
        case .fair: "tiède"
        case .serious: "chaud"
        case .critical: "critique"
        @unknown default: "inconnu"
        }
    }

    private static func thermalStatus(_ state: ProcessInfo.ThermalState) -> DiagnosticLine.Status {
        switch state {
        case .nominal, .fair: .ok
        case .serious: .warning
        default: .problem
        }
    }
}
