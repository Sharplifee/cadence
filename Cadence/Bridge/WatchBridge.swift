import CadenceCore
import Foundation
import WatchConnectivity

/// Four bytes cross the wire: cue, strain, channel mask, tier. The phone owns
/// every decision so the two devices can never disagree about what to play.
public final class WatchBridge: NSObject, WCSessionDelegate {
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var lastStrainSend = Date.distantPast

    /// Called when the watch asks the phone to start or stop.
    public var onRemoteToggle: ((Bool) -> Void)?

    public override init() {
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public var isWatchReachable: Bool { session?.isReachable ?? false }
    public var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }

    public func send(_ cue: CueCode, strain: Double = 0,
                     channels: Channels = .silent, tier: Int = 1,
                     talkShare: Double = 0.5) {
        guard let session, session.isReachable else { return }
        let payload = Data([cue.rawValue,
                            UInt8(min(max(strain, 0), 1) * 255),
                            UInt8(clamping: channels.rawValue),
                            UInt8(clamping: tier),
                            UInt8(min(max(talkShare, 0), 1) * 255)])
        // Fire and forget: a dropped cue beats a queued one arriving thirty
        // seconds after the moment it was about.
        session.sendMessageData(payload, replyHandler: nil, errorHandler: nil)
    }

    /// Ring updates are throttled hard — the watch screen is off most of the
    /// time and every wake costs battery for a display nobody is looking at.
    public func sendStrain(_ strain: Double) {
        guard Date().timeIntervalSince(lastStrainSend) > 4 else { return }
        lastStrainSend = Date()
        send(.none, strain: strain)
    }

    public func session(_ s: WCSession, didReceiveMessageData data: Data) {
        guard let first = data.first, let cue = CueCode(rawValue: first) else { return }
        switch cue {
        case .sessionStart: DispatchQueue.main.async { self.onRemoteToggle?(true) }
        case .sessionEnd:   DispatchQueue.main.async { self.onRemoteToggle?(false) }
        default: break
        }
    }

    public func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    public func sessionDidBecomeInactive(_ s: WCSession) {}
    public func sessionDidDeactivate(_ s: WCSession) { s.activate() }
}
