import Foundation

/// A thing that happened to the audio environment, not to the conversation.
///
/// The mic records sound in the room, not the phone's audio stream, so anything
/// played through headphones is inaudible to it. Rather than pretend otherwise,
/// the timeline records *when* other audio was playing and what the route was,
/// so a silent stretch in the recording is explained rather than mysterious.
public struct ContextEvent: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case mediaStarted        // something else began playing
        case mediaStopped
        case routeToSpeaker      // audible to the mic — it gets recorded
        case routeToHeadphones   // NOT audible to the mic — recording goes quiet
        case routeToBluetooth
        case micPaused           // call, Siri, alarm
        case micResumed
        case marked              // Connor pressed the button
    }

    public var id: UUID
    public var t: TimeInterval
    public var kind: Kind
    public var detail: String?

    public init(id: UUID = UUID(), t: TimeInterval, kind: Kind, detail: String? = nil) {
        self.id = id; self.t = t; self.kind = kind; self.detail = detail
    }

    /// True when the mic could not hear whatever was playing.
    public var meansAudioWasNotCaptured: Bool {
        kind == .routeToHeadphones || kind == .routeToBluetooth || kind == .micPaused
    }

    public var label: String {
        switch kind {
        case .mediaStarted:      return detail ?? "Media started"
        case .mediaStopped:      return "Media stopped"
        case .routeToSpeaker:    return "Speaker — audio being captured"
        case .routeToHeadphones: return "Headphones — playback not captured"
        case .routeToBluetooth:  return detail.map { "\($0) — playback not captured" }
                                        ?? "Bluetooth — playback not captured"
        case .micPaused:         return "Mic interrupted"
        case .micResumed:        return "Mic resumed"
        case .marked:            return detail ?? "Marked"
        }
    }
}

/// A bookmark Connor dropped, plus the window around it worth replaying.
public struct Moment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var t: TimeInterval
    public var note: String?
    /// How far back to start playback. An idea arrives after the thing that
    /// caused it, so the useful window is behind the press, not around it.
    public var lookbackSeconds: TimeInterval

    public init(id: UUID = UUID(), t: TimeInterval, note: String? = nil,
                lookbackSeconds: TimeInterval = 120) {
        self.id = id; self.t = t; self.note = note
        self.lookbackSeconds = lookbackSeconds
    }

    public var playbackStart: TimeInterval { max(0, t - lookbackSeconds) }
}

/// Answers "what was I hearing at 14:32" from the event log.
public struct AmbientTimeline: Codable, Sendable {
    public var events: [ContextEvent]
    public var moments: [Moment]

    public init(events: [ContextEvent] = [], moments: [Moment] = []) {
        self.events = events; self.moments = moments
    }

    /// Whether audio playing at this instant would have reached the mic.
    public func playbackWasCaptured(at t: TimeInterval) -> Bool {
        let routes = events
            .filter { $0.t <= t }
            .filter { [.routeToSpeaker, .routeToHeadphones, .routeToBluetooth].contains($0.kind) }
        // No route event yet means the built-in speaker, which the mic hears.
        return routes.last.map { $0.kind == .routeToSpeaker } ?? true
    }

    public func mediaWasPlaying(at t: TimeInterval) -> Bool {
        let media = events.filter { $0.t <= t }
            .filter { $0.kind == .mediaStarted || $0.kind == .mediaStopped }
        return media.last?.kind == .mediaStarted
    }

    /// Plain description of the audio environment at a moment, for the review
    /// screen. This is the whole point of the log.
    public func context(at t: TimeInterval) -> String {
        let playing = mediaWasPlaying(at: t)
        let captured = playbackWasCaptured(at: t)
        switch (playing, captured) {
        case (true, true):  return "Media was playing out loud and is in the recording."
        case (true, false): return "Media was playing through headphones, so it is not in the recording."
        case (false, _):    return "No other audio was playing."
        }
    }

    /// Stretches where the recording will be missing whatever was played.
    public func uncapturedRanges(upTo end: TimeInterval) -> [ClosedRange<TimeInterval>] {
        var out: [ClosedRange<TimeInterval>] = []
        var openedAt: TimeInterval?
        for e in events.sorted(by: { $0.t < $1.t }) {
            if e.meansAudioWasNotCaptured, openedAt == nil {
                openedAt = e.t
            } else if !e.meansAudioWasNotCaptured, let start = openedAt,
                      [.routeToSpeaker, .micResumed].contains(e.kind) {
                if e.t > start { out.append(start...e.t) }
                openedAt = nil
            }
        }
        if let start = openedAt, end > start { out.append(start...end) }
        return out
    }
}
