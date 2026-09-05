import Foundation

/// Decides ME / THEM / SILENCE / OVERLAP for each frame.
///
/// Phase 0 ships the near-field heuristic below: your phone is on your body, so
/// your voice arrives consistently louder and duller than anyone else's. That is
/// enough to be useful on day one and costs nothing.
///
/// Phase 1 swaps in a speaker-verification embedding behind the same protocol —
/// nothing downstream changes.
public protocol SpeakerClassifier {
    /// Persisted between launches. Without this the app is unusable after the
    /// first relaunch: onboarding is marked complete, the profile is gone, and
    /// every attempt to start reports "record your voice profile first".
    var profile: VoiceProfile? { get }
    mutating func restore(_ profile: VoiceProfile)
    func classify(dbfs: Float, centroid: Float, f0: Float) -> Speaker
    mutating func enroll(dbfs: Float, centroid: Float, f0: Float)
    var isCalibrated: Bool { get }
}

/// The learned voice profile, small enough to sit in UserDefaults.
public struct VoiceProfile: Codable, Sendable, Equatable {
    public var dbfs: Float
    public var centroid: Float
    public var f0: Float
    public var samples: Int
    public var recordedAt: Date

    public init(dbfs: Float, centroid: Float, f0: Float, samples: Int, recordedAt: Date = Date()) {
        self.dbfs = dbfs; self.centroid = centroid; self.f0 = f0
        self.samples = samples; self.recordedAt = recordedAt
    }
}

public struct NearFieldClassifier: SpeakerClassifier {
    // Running estimate of your own voice, built during a 60 s enrollment read.
    private var myDbfs: Float = 0
    private var myCentroid: Float = 0
    private var myF0: Float = 0
    private var samples = 0

    /// Below this many enrollment frames the gate abstains rather than guessing.
    /// A 30-second read yields roughly 40-50 speech frames once pauses between
    /// sentences are excluded, so this sits below that with margin.
    private let requiredSamples = 32

    public init() {}

    public init(profile: VoiceProfile) {
        myDbfs = profile.dbfs; myCentroid = profile.centroid
        myF0 = profile.f0; samples = profile.samples
    }

    public var isCalibrated: Bool { samples >= requiredSamples }

    public var profile: VoiceProfile? {
        isCalibrated ? VoiceProfile(dbfs: myDbfs, centroid: myCentroid,
                                    f0: myF0, samples: samples) : nil
    }

    public mutating func restore(_ p: VoiceProfile) {
        myDbfs = p.dbfs; myCentroid = p.centroid; myF0 = p.f0; samples = p.samples
    }

    public mutating func enroll(dbfs: Float, centroid: Float, f0: Float) {
        samples += 1
        let w = 1 / Float(samples)
        myDbfs += (dbfs - myDbfs) * w
        myCentroid += (centroid - myCentroid) * w
        if f0 > 0 { myF0 += (f0 - myF0) * w }
    }

    public func classify(dbfs: Float, centroid: Float, f0: Float) -> Speaker {
        guard isCalibrated else { return .them }

        var score: Float = 0
        // Level: near-field is the strongest single cue.
        score += (dbfs - (myDbfs - 8)) / 8
        // Timbre: your own voice at 30 cm is duller than theirs at 1.5 m.
        score += (myCentroid + 400 - centroid) / 800 * 0.6
        // Pitch: a coarse identity check, only when the frame is voiced.
        if f0 > 0, myF0 > 0 {
            score += (1 - min(abs(DSP.semitones(f0, myF0)) / 6, 1)) * 0.8
        }
        return score > 1.0 ? .me : .them
    }
}
