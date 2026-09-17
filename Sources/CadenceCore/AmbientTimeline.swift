import Foundation

/// A moment Connor marked, and the window of audio it points at.
///
/// An idea arrives *after* whatever caused it, so a mark looks backwards. The
/// window ends at the press, not around it — the three minutes you just lived
/// through are the ones worth hearing again.
public struct Moment: Codable, Sendable, Identifiable {
    public static let lookback: TimeInterval = 120

    public var id: UUID
    public var t: TimeInterval
    public var note: String?

    public init(id: UUID = UUID(), t: TimeInterval, note: String? = nil) {
        self.id = id; self.t = t; self.note = note
    }

    public var label: String { (note?.isEmpty == false ? note : nil) ?? "Marked" }
    public var playbackStart: TimeInterval { max(0, t - Self.lookback) }
    public var window: ClosedRange<TimeInterval> { playbackStart...t }
}

/// Something the audio environment did.
public struct ContextEvent: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case mediaStarted, mediaStopped
        case routeToSpeaker, routeToHeadphones, routeToBluetooth
        case micPaused, micResumed
        case marked
    }

    public var id: UUID
    public var t: TimeInterval
    public var kind: Kind
    public var detail: String?

    public init(id: UUID = UUID(), t: TimeInterval, kind: Kind, detail: String? = nil) {
        self.id = id; self.t = t; self.kind = kind; self.detail = detail
    }

    /// Whether audio from this point onward was reaching the microphone.
    /// nil means the event says nothing about capture either way.
    public var capturesAudio: Bool? {
        switch kind {
        case .routeToSpeaker, .micResumed: return true
        case .routeToHeadphones, .routeToBluetooth, .micPaused: return false
        default: return nil
        }
    }

    public var label: String {
        switch kind {
        case .mediaStarted:      return detail ?? "Media started"
        case .mediaStopped:      return "Media stopped"
        case .routeToSpeaker:    return "Speaker"
        case .routeToHeadphones: return "Headphones"
        case .routeToBluetooth:  return detail ?? "Bluetooth"
        case .micPaused:         return detail ?? "Microphone paused"
        case .micResumed:        return "Microphone resumed"
        case .marked:            return "Marked"
        }
    }
}

/// What the phone's audio was doing across a session, and which parts of it the
/// microphone actually heard.
///
/// The honesty here is the point. The mic records sound in the room, not audio
/// streams — anything playing through the speaker is captured, anything on
/// AirPods never reaches the microphone and cannot be recovered. Rather than
/// leave silent stretches unexplained months later, the timeline records where
/// playback was routed so review can say plainly which audio is in the file.
public struct AmbientTimeline: Codable, Sendable {
    public var events: [ContextEvent]
    public var moments: [Moment]

    public init(events: [ContextEvent] = [], moments: [Moment] = []) {
        self.events = events
        self.moments = moments
    }

    public mutating func record(_ e: ContextEvent) { events.append(e) }
    public mutating func mark(_ m: Moment) {
        moments.append(m)
        events.append(ContextEvent(t: m.t, kind: .marked, detail: m.note))
    }

    /// Context events in time order. Marks are excluded — they are the press,
    /// not something the environment did.
    public var markers: [ContextEvent] {
        events.filter { $0.kind != .marked }.sorted { $0.t < $1.t }
    }

    public var bookmarks: [Moment] { moments.sorted { $0.t < $1.t } }

    // MARK: - Capture honesty

    /// Absent any route event we assume the speaker, which is the state a phone
    /// is in unless something changed it.
    public func playbackWasCaptured(at t: TimeInterval) -> Bool {
        events
            .filter { $0.t <= t && $0.capturesAudio != nil }
            .max { $0.t < $1.t }?
            .capturesAudio ?? true
    }

    public func mediaWasPlaying(at t: TimeInterval) -> Bool {
        let last = events
            .filter { $0.t <= t && ($0.kind == .mediaStarted || $0.kind == .mediaStopped) }
            .max { $0.t < $1.t }
        return last?.kind == .mediaStarted
    }

    /// One plain sentence for the review screen.
    public func context(at t: TimeInterval) -> String {
        let captured = playbackWasCaptured(at: t)
        if mediaWasPlaying(at: t) {
            return captured
                ? "Something was playing out loud, so it is in the recording."
                : "Something was playing through headphones, so it is not in the recording."
        }
        return captured
            ? "Audio was going to the speaker, so anything playing is in the recording."
            : "Audio was going to headphones, so anything playing is not in the recording."
    }

    /// Stretches where the microphone was not hearing everything.
    public func uncapturedRanges(upTo end: TimeInterval) -> [ClosedRange<TimeInterval>] {
        let relevant = events.filter { $0.capturesAudio != nil }.sorted { $0.t < $1.t }
        var ranges: [ClosedRange<TimeInterval>] = []
        var openedAt: TimeInterval?

        for e in relevant {
            if e.capturesAudio == false, openedAt == nil {
                openedAt = e.t
            } else if e.capturesAudio == true, let start = openedAt {
                if e.t > start { ranges.append(start...e.t) }
                openedAt = nil
            }
        }
        if let start = openedAt, end > start { ranges.append(start...end) }
        return ranges
    }

    public func gapSeconds(upTo end: TimeInterval) -> TimeInterval {
        uncapturedRanges(upTo: end).reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    /// What the environment did during the window a mark points at.
    public func context(around moment: Moment) -> [ContextEvent] {
        let w = moment.window
        return events
            .filter { $0.kind != .marked && w.contains($0.t) }
            .sorted { $0.t < $1.t }
    }
}
