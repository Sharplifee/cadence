import Foundation

/// The private vocabulary. One byte crosses to the watch; only Connor decodes it.
public enum CueCode: UInt8, Codable, CaseIterable, Sendable {
    case none            = 0
    /// You have accelerated past them. Two soft taps.
    case slowDown        = 1
    /// You are louder than the room needs. One long pulse.
    case lowerVolume     = 2
    /// Talk-share has collapsed in your favour. Three quick taps.
    case yieldFloor      = 3
    /// You are cutting them off. Sharp double-click.
    case stopOverlapping = 4
    /// Optional training mode: ticks at their turn cadence.
    case metronomeTick   = 5
    /// Session lifecycle.
    case sessionStart    = 6
    case sessionEnd      = 7

    public var label: String {
        switch self {
        case .none:            return "none"
        case .slowDown:        return "slow down"
        case .lowerVolume:     return "lower volume"
        case .yieldFloor:      return "yield the floor"
        case .stopOverlapping: return "stop overlapping"
        case .metronomeTick:   return "tick"
        case .sessionStart:    return "session start"
        case .sessionEnd:      return "session end"
        }
    }
}
