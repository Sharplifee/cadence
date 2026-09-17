import AVFoundation
import CadenceCore
import Foundation

/// Watches the audio environment and records what the microphone could and
/// could not hear.
///
/// The mic captures sound in the room, not the phone's audio bus. Anything
/// played to headphones never reaches it and cannot be recorded by any public
/// API. Rather than leave that as an unexplained silent stretch, this logs the
/// route and whether other audio was playing, so the review screen can say
/// "podcast was playing through AirPods here" instead of showing dead air.
@MainActor
public final class AmbientMonitor {
    public private(set) var events: [ContextEvent] = []
    private var lastMediaPlaying = false
    private var lastRouteKind: ContextEvent.Kind?
    private var startedAt = Date()

    public var onEvent: ((ContextEvent) -> Void)?

    public init() {}

    public func begin() {
        events.removeAll()
        lastMediaPlaying = false
        lastRouteKind = nil
        startedAt = Date()
        recordRoute()
        recordMediaState()
        NotificationCenter.default.addObserver(
            self, selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(silenceChanged),
            name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
    }

    public func end() {
        NotificationCenter.default.removeObserver(self)
    }

    public func mark(note: String?) {
        add(.init(t: elapsed, kind: .marked, detail: note))
    }

    public func noteMicPaused() { add(.init(t: elapsed, kind: .micPaused)) }
    public func noteMicResumed() { add(.init(t: elapsed, kind: .micResumed)) }

    /// Polled alongside the frame stream — there is no notification for another
    /// app starting playback, only this flag.
    public func poll() {
        recordMediaState()
    }

    private var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    private func add(_ e: ContextEvent) {
        events.append(e)
        onEvent?(e)
    }

    private func recordMediaState() {
        let playing = AVAudioSession.sharedInstance().isOtherAudioPlaying
        guard playing != lastMediaPlaying else { return }
        lastMediaPlaying = playing
        add(.init(t: elapsed, kind: playing ? .mediaStarted : .mediaStopped,
                  detail: playing ? "Other audio started" : nil))
    }

    private func recordRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let out = outputs.first else { return }
        let kind: ContextEvent.Kind
        switch out.portType {
        case .builtInSpeaker, .builtInReceiver:
            kind = .routeToSpeaker
        case .headphones, .headsetMic, .usbAudio:
            kind = .routeToHeadphones
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay:
            kind = .routeToBluetooth
        default:
            kind = .routeToSpeaker
        }
        guard kind != lastRouteKind else { return }
        lastRouteKind = kind
        add(.init(t: elapsed, kind: kind, detail: out.portName))
    }

    @objc private func routeChanged(_ n: Notification) {
        Task { @MainActor in self.recordRoute() }
    }

    @objc private func silenceChanged(_ n: Notification) {
        Task { @MainActor in self.recordMediaState() }
    }
}
