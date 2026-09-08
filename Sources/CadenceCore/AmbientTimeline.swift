import Foundation

/// Something worth being able to jump back to.
public struct Marker: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// You pressed the button. The whole point.
        case bookmark
        /// Other audio started or stopped playing out loud.
        case mediaStarted, mediaStopped
        /// Route changed — headphones in or out. Matters because audio through
        /// headphones is not in the recording at all, and future-you needs to
        /// know the gap is a limitation rather than silence.
        case headphonesConnected, headphonesDisconnected
        /// Capture was lost and recovered.
        case captureLost, captureResumed
        case sessionStart, sessionEnd
    }

    public var id: UUID
    public var t: TimeInterval
    public var kind: Kind
    public var note: String?

    public init(id: UUID = UUID(), t: TimeInterval, kind: Kind, note: String? = nil) {
        self.id = id; self.t = t; self.kind = kind; self.note = note
    }

    public var label: String {
        switch kind {
        case .bookmark:               return note?.isEmpty == false ? note! : "Marked"
        case .mediaStarted:           return "Media started playing"
        case .mediaStopped:           return "Media stopped"
        case .headphonesConnected:    return "Headphones connected"
        case .headphonesDisconnected: return "Headphones disconnected"
        case .captureLost:            return "Capture interrupted"
        case .captureResumed:         return "Capture resumed"
        case .sessionStart:           return "Started"
        case .sessionEnd:             return "Ended"
        }
    }

    /// True where audio was reaching your ears but not the microphone.
    public var opensAudioGap: Bool { kind == .headphonesConnected || kind == .captureLost }
    public var closesAudioGap: Bool { kind == .headphonesDisconnected || kind == .captureResumed }
}

/// The ambient record: markers plus the spans where the recording is knowingly
/// incomplete.
///
/// The gap tracking exists because of a hard platform limit. iOS gives no app
/// access to another app's audio output, so anything played through headphones
/// is inaudible to the microphone. Silently producing a recording with holes in
/// it would be worse than useless — you would replay a moment, hear nothing, and
/// conclude nothing was happening.
public struct AmbientTimeline: Codable, Sendable {
    public var markers: [Marker] = []

    public init(markers: [Marker] = []) { self.markers = markers }

    public mutating func add(_ m: Marker) {
        markers.append(m)
        markers.sort { $0.t < $1.t }
    }

    public var bookmarks: [Marker] { markers.filter { $0.kind == .bookmark } }

    /// Periods where sound was going to headphones, or capture was down, and is
    /// therefore absent from the audio file.
    public func audioGaps(upTo end: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
        var gaps: [(TimeInterval, TimeInterval)] = []
        var open: TimeInterval?
        for m in markers {
            if m.opensAudioGap, open == nil { open = m.t }
            else if m.closesAudioGap, let s = open { gaps.append((s, m.t)); open = nil }
        }
        if let s = open { gaps.append((s, end)) }
        return gaps
    }

    public func gapSeconds(upTo end: TimeInterval) -> TimeInterval {
        audioGaps(upTo: end).reduce(0) { $0 + ($1.end - $1.start) }
    }

    /// Everything within a window either side of a bookmark — the context that
    /// might have sparked it.
    public func context(around marker: Marker, window: TimeInterval = 120) -> [Marker] {
        markers.filter { abs($0.t - marker.t) <= window && $0.id != marker.id }
    }
}
