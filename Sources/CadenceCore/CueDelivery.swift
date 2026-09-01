import Foundation

/// Which output channels a cue is allowed to use.
public struct Channels: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let haptic = Channels(rawValue: 1 << 0)
    public static let sound  = Channels(rawValue: 1 << 1)
    public static let flash  = Channels(rawValue: 1 << 2)

    public static let silent: Channels = [.haptic]
    public static let all: Channels = [.haptic, .sound, .flash]
}

/// Where a cue is delivered. Both devices by default — the phone may be face
/// down on a table while the watch is under a cuff, and either can be missed.
public struct Devices: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let phone = Devices(rawValue: 1 << 0)
    public static let watch = Devices(rawValue: 1 << 1)
    public static let both: Devices = [.phone, .watch]
}

/// The escalation ladder.
///
/// A cue you have ignored three times is not the same event as a cue arriving
/// for the first time, and it should not feel the same. Tier 1 is a private
/// nudge; by tier 3 the app has concluded the nudge is not working and is
/// allowed to be rude about it.
public struct Escalation: Codable, Sendable, Equatable {
    /// Ignored-cue count at which each tier begins.
    public var tier2At: Int
    public var tier3At: Int
    /// What each tier is permitted to use.
    public var tier1: Channels
    public var tier2: Channels
    public var tier3: Channels
    /// Consecutive ignored cues reset after this long without one.
    public var decayAfter: TimeInterval

    public static let `default` = Escalation(
        tier2At: 4, tier3At: 6,
        tier1: [.haptic],
        tier2: [.haptic, .sound],
        tier3: [.haptic, .sound, .flash],
        decayAfter: 600
    )

    public init(tier2At: Int, tier3At: Int, tier1: Channels, tier2: Channels,
                tier3: Channels, decayAfter: TimeInterval) {
        self.tier2At = tier2At; self.tier3At = tier3At
        self.tier1 = tier1; self.tier2 = tier2; self.tier3 = tier3
        self.decayAfter = decayAfter
    }

    public func channels(forStreak streak: Int) -> Channels {
        if streak >= tier3At { return tier3 }
        if streak >= tier2At { return tier2 }
        return tier1
    }

    public func tier(forStreak streak: Int) -> Int {
        streak >= tier3At ? 3 : (streak >= tier2At ? 2 : 1)
    }
}

/// Everything the user can configure about how a cue reaches them.
public struct CueSettings: Codable, Sendable {
    public var devices: Devices = .both
    public var escalation: Escalation = .default
    /// Hard ceiling regardless of tier — flipping this off means the ladder can
    /// never reach for sound or light no matter how many cues are ignored.
    public var allowed: Channels = .all
    public var metronomeEnabled: Bool = false

    public init() {}

    public func resolvedChannels(streak: Int) -> Channels {
        escalation.channels(forStreak: streak).intersection(allowed)
    }
}

/// Tracks how many cues in a row went uncorrected, which is what drives the
/// ladder. Correcting after a cue drops you back to the bottom — the escalation
/// is a response to being ignored, not to being imperfect.
public final class EscalationTracker {
    private var streak = 0
    private var lastCueAt: TimeInterval = -.infinity
    private let settings: () -> CueSettings

    public init(settings: @escaping () -> CueSettings) { self.settings = settings }

    public var currentStreak: Int { streak }

    public func register(at t: TimeInterval) -> (streak: Int, channels: Channels, tier: Int) {
        let s = settings()
        if t - lastCueAt > s.escalation.decayAfter { streak = 0 }
        lastCueAt = t
        streak += 1
        return (streak, s.resolvedChannels(streak: streak), s.escalation.tier(forStreak: streak))
    }

    public func registerCorrection() { streak = 0 }

    public func reset() { streak = 0; lastCueAt = -.infinity }
}
