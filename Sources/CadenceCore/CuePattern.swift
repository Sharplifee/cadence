import Foundation

/// One rhythm, four outputs.
///
/// The pattern is defined once here and driven identically by wrist haptics,
/// phone haptics, alert tones, the phone torch and the watch screen. That is
/// deliberate: the whole point is that a cue feels like *one* signal arriving on
/// whatever channels are enabled, not four unrelated notifications.
public struct CuePattern: Codable, Sendable, Equatable {
    /// Seconds. `on` is the pulse, `gap` is the silence that follows it.
    public struct Pulse: Codable, Sendable, Equatable {
        public var on: TimeInterval
        public var gap: TimeInterval
        public init(on: TimeInterval, gap: TimeInterval) { self.on = on; self.gap = gap }
    }

    public var pulses: [Pulse]
    public init(pulses: [Pulse]) { self.pulses = pulses }

    public var duration: TimeInterval {
        pulses.reduce(0) { $0 + $1.on + $1.gap }
    }

    /// Absolute offsets from the start of the pattern, for schedulers that need
    /// to queue each pulse rather than sleep between them.
    public var schedule: [(at: TimeInterval, on: TimeInterval)] {
        var t: TimeInterval = 0
        var out: [(TimeInterval, TimeInterval)] = []
        for p in pulses {
            out.append((t, p.on))
            t += p.on + p.gap
        }
        return out
    }

    // Patterns are distinguishable by rhythm alone — through a sleeve, in a
    // pocket, without looking. Short-short is never confusable with one long.
    public static func pattern(for cue: CueCode) -> CuePattern {
        switch cue {
        case .slowDown:        return .init(pulses: [.init(on: 0.14, gap: 0.26),
                                                     .init(on: 0.14, gap: 0)])
        case .lowerVolume:     return .init(pulses: [.init(on: 0.70, gap: 0)])
        case .yieldFloor:      return .init(pulses: [.init(on: 0.09, gap: 0.11),
                                                     .init(on: 0.09, gap: 0.11),
                                                     .init(on: 0.09, gap: 0)])
        case .stopOverlapping: return .init(pulses: [.init(on: 0.06, gap: 0.07),
                                                     .init(on: 0.06, gap: 0.07),
                                                     .init(on: 0.30, gap: 0)])
        case .metronomeTick:   return .init(pulses: [.init(on: 0.05, gap: 0)])
        case .sessionStart:    return .init(pulses: [.init(on: 0.10, gap: 0.10),
                                                     .init(on: 0.25, gap: 0)])
        case .sessionEnd:      return .init(pulses: [.init(on: 0.25, gap: 0.10),
                                                     .init(on: 0.10, gap: 0)])
        case .none:            return .init(pulses: [])
        }
    }
}
