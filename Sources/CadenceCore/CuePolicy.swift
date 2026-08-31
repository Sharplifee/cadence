import Foundation

/// Turns divergence into a wrist buzz — sparingly.
///
/// Two rules keep this wearable instead of maddening: a breach must be
/// *sustained* before it fires, and nothing fires during a cooldown. A cue you
/// feel forty times an hour is a cue you stop feeling.
public final class CuePolicy {
    public struct Thresholds {
        public var rateRatio: Float       = 1.30   // 30 % faster than them
        public var loudnessDelta: Float   = 6.0    // dB above them
        public var talkShare: Float       = 0.68   // two thirds of the airtime
        public var interruptRate: Float   = 2.0    // per minute
        public var minConfidence: Float   = 0.5
        public init() {}
    }

    public var thresholds = Thresholds()
    public var sustainDuration: TimeInterval = 10
    public var cooldown: TimeInterval = 50

    private var breachStart: [CueCode: TimeInterval] = [:]
    private var lastFired: [CueCode: TimeInterval] = [:]
    private var lastFiredAny: TimeInterval = -.infinity

    public private(set) var events: [CueEvent] = []

    public init() {}

    /// One dial the user can actually reason about. 0 = only when you are
    /// clearly running away; 1 = eager. Everything scales together, because
    /// exposing four raw thresholds asks the user to be an audio engineer.
    public func applySensitivity(_ s: Float) {
        let k = min(max(s, 0), 1)
        thresholds.rateRatio      = 1.45 - 0.25 * k     // 1.45 -> 1.20
        thresholds.loudnessDelta  = 9.0  - 4.5  * k     // 9.0  -> 4.5
        thresholds.talkShare      = 0.78 - 0.16 * k     // 0.78 -> 0.62
        thresholds.interruptRate  = 3.2  - 1.7  * k     // 3.2  -> 1.5
        sustainDuration           = TimeInterval(14 - 7 * k)
        cooldown                  = TimeInterval(75 - 40 * k)
    }

    public func evaluate(_ d: Divergence, at t: TimeInterval) -> CueCode? {
        guard d.confidence >= thresholds.minConfidence else {
            breachStart.removeAll(); return nil
        }

        // Ordered by how much damage the behaviour does to the other person.
        var breached: [CueCode] = []
        if d.interruptRate  >= thresholds.interruptRate  { breached.append(.stopOverlapping) }
        if d.talkShare      >= thresholds.talkShare      { breached.append(.yieldFloor) }
        if d.loudnessDelta  >= thresholds.loudnessDelta  { breached.append(.lowerVolume) }
        if d.rateRatio      >= thresholds.rateRatio      { breached.append(.slowDown) }

        for code in CueCode.allCases where !breached.contains(code) {
            breachStart[code] = nil
        }
        guard let top = breached.first else { return nil }

        let began = breachStart[top] ?? t
        breachStart[top] = began
        guard t - began >= sustainDuration else { return nil }

        // Global cooldown stops a cascade; per-cue cooldown is longer so the
        // same nudge does not repeat before you have had a chance to act.
        guard t - lastFiredAny >= cooldown else { return nil }
        guard t - (lastFired[top] ?? -.infinity) >= cooldown * 2 else { return nil }

        lastFired[top] = t
        lastFiredAny = t
        breachStart[top] = nil
        events.append(CueEvent(t: t, code: top, divergence: d, corrected: nil))
        return top
    }

    /// Called 30 s after each cue. This column is the whole point of the app —
    /// it is the difference between logging behaviour and changing it.
    public func scoreCorrection(at t: TimeInterval, current d: Divergence) {
        for i in events.indices where events[i].corrected == nil && t - events[i].t >= 30 {
            let before = events[i].divergence
            let closed: Bool
            switch events[i].code {
            case .slowDown:        closed = d.rateRatio < before.rateRatio - 0.10
            case .lowerVolume:     closed = d.loudnessDelta < before.loudnessDelta - 2.0
            case .yieldFloor:      closed = d.talkShare < before.talkShare - 0.05
            case .stopOverlapping: closed = d.interruptRate < before.interruptRate - 0.5
            default:               closed = true
            }
            events[i].corrected = closed
        }
    }

    public var correctionRate: Float? {
        let scored = events.compactMap { $0.corrected }
        guard !scored.isEmpty else { return nil }
        return Float(scored.filter { $0 }.count) / Float(scored.count)
    }
}
