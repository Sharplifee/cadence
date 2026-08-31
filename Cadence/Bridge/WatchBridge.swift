import CadenceCore
import Foundation
import WatchConnectivity

/// Two bytes cross the wire: the cue, and how far out of sync you are right
/// now. The phone does every calculation, which is the only reason the watch
/// lasts a whole evening.
public final class WatchBridge: NSObject, WCSessionDelegate {
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var lastStrainSend = Date.distantPast

    public override init() {
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public func send(_ cue: CueCode, strain: Double = 0) {
        guard let session, session.isReachable else { return }
        let byte = UInt8(min(max(strain, 0), 1) * 255)
        // Fire and forget — a dropped cue beats a queued, late one arriving
        // thirty seconds after the moment it was about.
        session.sendMessageData(Data([cue.rawValue, byte]), replyHandler: nil, errorHandler: nil)
    }

    /// Ring updates are throttled hard. The watch screen is off most of the
    /// time and every wake costs battery for a display nobody is looking at.
    public func sendStrain(_ strain: Double) {
        guard Date().timeIntervalSince(lastStrainSend) > 4 else { return }
        lastStrainSend = Date()
        send(.none, strain: strain)
    }

    public func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    public func sessionDidBecomeInactive(_ s: WCSession) {}
    public func sessionDidDeactivate(_ s: WCSession) { s.activate() }
}
