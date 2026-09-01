import CadenceCore
import Foundation
import WatchConnectivity
import WatchKit

/// Receives cues from the phone. Four bytes now: the cue, the strain, the
/// channel mask and the escalation tier — so the wrist plays exactly what the
/// phone decided, and the two devices never disagree about how loud to be.
@MainActor
public final class PhoneReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published public var active = false
    @Published public var lastCue: CueCode = .none
    @Published public var strain: Double = 0
    @Published public var tier: Int = 1
    @Published public var talkShare: Double = 0.5

    public let cuePlayer = WatchCuePlayer()
    public let runtime = WorkoutRuntime()

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated public func session(_ s: WCSession, didReceiveMessageData data: Data) {
        let bytes = [UInt8](data)
        Task { @MainActor in self.handle(bytes) }
    }

    private func handle(_ bytes: [UInt8]) {
        guard let first = bytes.first, let cue = CueCode(rawValue: first) else { return }
        strain = bytes.count > 1 ? Double(bytes[1]) / 255 : strain
        if bytes.count > 4 { talkShare = Double(bytes[4]) / 255 }
        let channels = Channels(rawValue: bytes.count > 2 ? Int(bytes[2]) : Channels.haptic.rawValue)
        tier = bytes.count > 3 ? max(1, Int(bytes[3])) : 1

        switch cue {
        case .sessionStart:
            active = true
            // The phone launched us via startWatchApp, which already began a
            // workout session; start() is a no-op if one is running.
            runtime.start()
        case .sessionEnd:
            active = false
            runtime.stop()
        case .none:
            return                                  // strain-only ping
        default:
            lastCue = cue
        }
        cuePlayer.play(cue, channels: channels, tier: tier)
    }

    /// Control travels both ways. Reaching for your phone to start a
    /// conversation you are already in defeats the point of the wrist.
    public func toggleSession() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessageData(Data([active ? CueCode.sessionEnd.rawValue
                                                       : CueCode.sessionStart.rawValue,
                                                0, 0, 1]),
                                          replyHandler: nil, errorHandler: nil)
        active.toggle()
        if active { runtime.start() } else { runtime.stop() }
    }

    nonisolated public func session(_ s: WCSession,
                                    activationDidCompleteWith state: WCSessionActivationState,
                                    error: Error?) {}
}
