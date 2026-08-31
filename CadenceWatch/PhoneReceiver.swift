import CadenceCore
import Foundation
import WatchConnectivity
import WatchKit

/// Receives two bytes and keeps the app alive long enough to feel them.
public final class PhoneReceiver: NSObject, ObservableObject, WCSessionDelegate,
                                  WKExtendedRuntimeSessionDelegate {
    @Published public var active = false
    @Published public var lastCue: CueCode = .none
    @Published public var strain: Double = 0

    private var runtime: WKExtendedRuntimeSession?

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func session(_ s: WCSession, didReceiveMessageData data: Data) {
        guard let first = data.first, let cue = CueCode(rawValue: first) else { return }
        let strainByte = data.count > 1 ? Double(data[1]) / 255 : 0

        DispatchQueue.main.async {
            self.strain = strainByte
            switch cue {
            case .sessionStart: self.active = true;  self.beginRuntime()
            case .sessionEnd:   self.active = false; self.endRuntime()
            case .none:         return                       // strain-only ping
            default:            self.lastCue = cue
            }
            HapticPlayer.play(cue)
        }
    }

    /// An extended runtime session buys roughly an hour. It expires rather than
    /// dying, so it is restarted on expiry to cover a long dinner.
    private func beginRuntime() {
        guard runtime == nil else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        runtime = s
    }

    private func endRuntime() {
        runtime?.invalidate()
        runtime = nil
    }

    public func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {}
    public func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        runtime = nil
        if active { beginRuntime() }
    }
    public func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                       didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                       error: Error?) {
        runtime = nil
        if active { beginRuntime() }
    }

    public func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
