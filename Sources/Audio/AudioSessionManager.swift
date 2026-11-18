import AVFoundation
import Foundation

/// La session audio de l'app : micro + haut-parleur pendant un échange, rendue ensuite
/// (la musique reprend). Prévient le contrôleur des interruptions (appel, Siri, alarme)
/// et de la perte de la sortie audio (AirPods retirés).
@MainActor
final class AudioSessionManager {
    var onInterruption: (() -> Void)?
    var onOutputLost: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.onInterruption?() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let raw, AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.onOutputLost?() }
        })
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
