import Foundation

/// A frozen moment: the audio the loop was holding when you pressed mark.
///
/// Clips are born on the Watch and finish their life on the phone. The Watch
/// has the microphone and the rolling buffer; the phone has the speech
/// recogniser, the storage and the screen. So a clip moves in stages, and the
/// stage is recorded — a clip that arrived but has not been transcribed is a
/// different thing from one that never arrived, and the UI has to say which.
public struct MarkedClip: Codable, Sendable, Identifiable, Equatable {
    public enum Stage: String, Codable, Sendable {
        /// Frozen on the Watch, not yet sent.
        case onWatch
        /// Transferring to the phone.
        case sending
        /// On the phone, audio only.
        case arrived
        /// Transcribed and mined for commitments.
        case processed
        /// Transfer or transcription failed; the audio may still be on the Watch.
        case failed

        public var label: String {
            switch self {
            case .onWatch:   return "on your watch"
            case .sending:   return "sending"
            case .arrived:   return "transcribing"
            case .processed: return "ready"
            case .failed:    return "failed"
            }
        }
    }

    public var id: UUID
    public var markedAt: Date
    /// How far back the clip reaches from the moment you pressed.
    public var lookback: TimeInterval
    public var stage: Stage
    public var note: String?
    /// Filenames of the segments that make up this clip, oldest first.
    public var segments: [String]
    public var transcript: String?
    public var commitments: [Commitment]
    public var errorMessage: String?

    public init(id: UUID = UUID(), markedAt: Date = Date(), lookback: TimeInterval = 120,
                stage: Stage = .onWatch, note: String? = nil, segments: [String] = [],
                transcript: String? = nil, commitments: [Commitment] = [],
                errorMessage: String? = nil) {
        self.id = id; self.markedAt = markedAt; self.lookback = lookback
        self.stage = stage; self.note = note; self.segments = segments
        self.transcript = transcript; self.commitments = commitments
        self.errorMessage = errorMessage
    }

    public var isComplete: Bool { stage == .processed }
    public var needsAttention: Bool { stage == .failed }

    /// What the clip covers, in wall-clock terms — the useful label at review
    /// time is the window the audio spans, not the instant you pressed.
    public var windowDescription: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let from = markedAt.addingTimeInterval(-lookback)
        return "\(f.string(from: from)) – \(f.string(from: markedAt))"
    }

    public var headline: String {
        if let n = note, !n.isEmpty { return n }
        if let c = commitments.first { return c.text }
        if let t = transcript, !t.isEmpty {
            return String(t.prefix(80)) + (t.count > 80 ? "…" : "")
        }
        return windowDescription
    }
}

/// The set of clips, ordered newest first, with the merge rule that keeps
/// Watch-side and phone-side updates from clobbering each other.
public struct ClipLibrary: Codable, Sendable, Equatable {
    public private(set) var clips: [MarkedClip] = []

    public init(clips: [MarkedClip] = []) {
        self.clips = clips.sorted { $0.markedAt > $1.markedAt }
    }

    /// Insert or advance a clip.
    ///
    /// Stages only ever move forward. Both devices report on the same clip and
    /// messages can arrive out of order — a late "sending" from the Watch must
    /// not drag a clip the phone has already transcribed back down the ladder.
    public mutating func upsert(_ clip: MarkedClip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else {
            clips.append(clip)
            clips.sort { $0.markedAt > $1.markedAt }
            return
        }
        var merged = clip
        if rank(clip.stage) < rank(clips[i].stage) {
            merged.stage = clips[i].stage
            merged.transcript = clip.transcript ?? clips[i].transcript
            merged.commitments = clip.commitments.isEmpty ? clips[i].commitments : clip.commitments
        }
        if merged.note == nil { merged.note = clips[i].note }
        clips[i] = merged
    }

    private func rank(_ s: MarkedClip.Stage) -> Int {
        switch s {
        case .failed:    return 0
        case .onWatch:   return 1
        case .sending:   return 2
        case .arrived:   return 3
        case .processed: return 4
        }
    }

    public mutating func remove(_ id: UUID) { clips.removeAll { $0.id == id } }

    public var pending: [MarkedClip] { clips.filter { !$0.isComplete && !$0.needsAttention } }
    public var failed: [MarkedClip] { clips.filter(\.needsAttention) }

    /// Every commitment across every processed clip, newest first. This is the
    /// list the app exists to produce.
    public var allCommitments: [(clip: MarkedClip, commitment: Commitment)] {
        clips.flatMap { c in c.commitments.map { (c, $0) } }
    }
}
