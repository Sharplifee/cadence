import Foundation

public enum Speaker: String, Codable, Sendable {
    case me, them, silence, overlap
}

/// One 500 ms analysis frame.
public struct Frame: Codable, Sendable {
    public var t: TimeInterval        // seconds since session start
    public var speaker: Speaker
    public var dbfs: Float            // RMS level
    public var f0: Float              // fundamental frequency, Hz (0 = unvoiced)
    public var syllableRate: Float    // syllables/sec estimate
    public var centroid: Float        // spectral centroid, Hz

    public init(t: TimeInterval, speaker: Speaker, dbfs: Float, f0: Float,
                syllableRate: Float, centroid: Float) {
        self.t = t; self.speaker = speaker; self.dbfs = dbfs
        self.f0 = f0; self.syllableRate = syllableRate; self.centroid = centroid
    }
}

/// A contiguous run of speech by one speaker.
public struct Turn: Codable, Sendable {
    public var speaker: Speaker
    public var start: TimeInterval
    public var end: TimeInterval
    public var meanDbfs: Float
    public var meanF0: Float
    public var meanSyllableRate: Float
    /// Gap between the previous speaker stopping and this turn starting.
    /// Negative means this turn began before the other finished.
    public var latency: TimeInterval

    public var duration: TimeInterval { end - start }
    public var isInterruption: Bool { latency < -0.15 }

    public init(speaker: Speaker, start: TimeInterval, end: TimeInterval,
                meanDbfs: Float, meanF0: Float, meanSyllableRate: Float,
                latency: TimeInterval) {
        self.speaker = speaker; self.start = start; self.end = end
        self.meanDbfs = meanDbfs; self.meanF0 = meanF0
        self.meanSyllableRate = meanSyllableRate; self.latency = latency
    }
}

/// What the engine believes about the gap between you and them, right now.
public struct Divergence: Codable, Sendable {
    public var rateRatio: Float       // my syllable rate / theirs. 1.0 = matched
    public var loudnessDelta: Float   // my dBFS - theirs
    public var pitchDelta: Float      // my f0 - theirs, in semitones
    public var turnLengthRatio: Float // my mean turn / theirs
    public var talkShare: Float       // 0..1, my share of speaking time
    public var interruptRate: Float   // my interruptions per minute
    public var confidence: Float      // 0..1, how much of this is trustworthy

    public init(rateRatio: Float, loudnessDelta: Float, pitchDelta: Float,
                turnLengthRatio: Float, talkShare: Float,
                interruptRate: Float, confidence: Float) {
        self.rateRatio = rateRatio; self.loudnessDelta = loudnessDelta
        self.pitchDelta = pitchDelta; self.turnLengthRatio = turnLengthRatio
        self.talkShare = talkShare; self.interruptRate = interruptRate
        self.confidence = confidence
    }

    public static let matched = Divergence(rateRatio: 1, loudnessDelta: 0, pitchDelta: 0,
                                           turnLengthRatio: 1, talkShare: 0.5,
                                           interruptRate: 0, confidence: 0)
}

public struct CueEvent: Codable, Sendable {
    public var t: TimeInterval
    public var code: CueCode
    public var divergence: Divergence
    /// Filled in 30 s later: did the divergence actually close after the cue?
    public var corrected: Bool?

    public init(t: TimeInterval, code: CueCode, divergence: Divergence,
                corrected: Bool? = nil) {
        self.t = t; self.code = code
        self.divergence = divergence; self.corrected = corrected
    }
}

public struct SessionSummary: Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var duration: TimeInterval
    public var talkShare: Float
    public var interruptions: Int
    public var cues: [CueEvent]
    public var correctionRate: Float?
    /// User-supplied. "Coffee with Dylan" is worth infinitely more at review
    /// time than a timestamp.
    public var title: String?
    public var utterances: [Utterance]
    public var insights: Insights?
    /// Whether the audio file is still on disk next to this summary.
    public var hasAudio: Bool

    public init(id: UUID, startedAt: Date, duration: TimeInterval,
                talkShare: Float, interruptions: Int, cues: [CueEvent],
                correctionRate: Float?, title: String? = nil,
                utterances: [Utterance] = [], insights: Insights? = nil,
                hasAudio: Bool = false) {
        self.id = id; self.startedAt = startedAt; self.duration = duration
        self.talkShare = talkShare; self.interruptions = interruptions
        self.cues = cues; self.correctionRate = correctionRate
        self.title = title; self.utterances = utterances
        self.insights = insights; self.hasAudio = hasAudio
    }

    public var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        return startedAt.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

public extension Divergence {
    /// 0 = perfectly matched, 1 = fully off the rails. The worst axis wins,
    /// because a single bad dimension is what the other person actually feels.
    var strain: Double {
        guard confidence > 0 else { return 0 }
        let parts: [Float] = [
            abs(rateRatio - 1) / 0.5,
            abs(loudnessDelta) / 10,
            abs(talkShare - 0.5) / 0.35,
            interruptRate / 3
        ]
        return Double(min(max(parts.max() ?? 0, 0), 1))
    }

    var headline: String {
        guard confidence > 0.4 else { return "Listening" }
        switch strain {
        case ..<0.45: return "In step"
        case ..<0.75: return "Drifting ahead"
        default:      return "Running away"
        }
    }
}
