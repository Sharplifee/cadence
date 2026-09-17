import Foundation

/// Where the phone is sending playback, and whether the microphone can hear it.
public enum AudioRouteKind: String, Codable, Sendable, CaseIterable {
    case speaker, receiver, headphones, bluetooth, external

    /// Sound on this route reaches the mic, so it is already in the recording.
    public var audibleToMic: Bool {
        switch self {
        case .speaker, .external: return true
        case .receiver, .headphones, .bluetooth: return false
        }
    }

    public var label: String {
        switch self {
        case .speaker:    return "Speaker"
        case .receiver:   return "Earpiece"
        case .headphones: return "Headphones"
        case .bluetooth:  return "AirPods"
        case .external:   return "External speaker"
        }
    }

    public var event: ContextEvent.Kind {
        audibleToMic ? .routeToSpeaker
                     : (self == .bluetooth ? .routeToBluetooth : .routeToHeadphones)
    }
}
