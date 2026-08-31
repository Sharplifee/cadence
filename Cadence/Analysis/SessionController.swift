import CadenceCore
import Combine
import Foundation

/// The spine. Audio in, cues out, session on disk. Everything it publishes is
/// read directly by the UI; everything it computes lives in CadenceCore, which
/// is why the logic is unit-tested and this file is not.
@MainActor
public final class SessionController: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var isEnrolling = false
    @Published public private(set) var divergence: Divergence = .matched
    @Published public private(set) var lastCue: CueCode = .none
    @Published public private(set) var elapsed: TimeInterval = 0

    public var metronomeEnabled = false

    private let capture = AudioCapture()
    private let vad = VoiceActivity()
    private var classifier: SpeakerClassifier = NearFieldClassifier()
    private let turns = TurnTracker()
    private let engine = DivergenceEngine()
    private let policy = CuePolicy()
    private let watch = WatchBridge()
    private let store = SessionStore()

    private var sessionID = UUID()
    private var startedAt = Date()
    private var frameIndex = 0
    private var frames: [Frame] = []
    private var lastTick: TimeInterval = 0

    public init() {
        capture.onFrame = { [weak self] samples in
            Task { @MainActor in self?.handle(samples) }
        }
        policy.applySensitivity(0.5)
    }

    // MARK: - Control

    public func applySensitivity(_ value: Double) {
        policy.applySensitivity(Float(value))
    }

    /// Fires a cue on the watch on demand, for the onboarding and settings
    /// screens. Learning the vocabulary should not require a bad conversation.
    public func preview(_ cue: CueCode) {
        watch.send(cue)
    }

    public func startEnrollment() throws {
        isEnrolling = true
        classifier = NearFieldClassifier()
        try capture.start()
    }

    public func finishEnrollment() {
        isEnrolling = false
        capture.stop()
    }

    public func start() throws {
        guard classifier.isCalibrated else {
            throw NSError(domain: "Cadence", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Record your voice profile first — Settings, then Re-record."
            ])
        }
        sessionID = UUID(); startedAt = Date()
        frameIndex = 0; frames.removeAll(); elapsed = 0
        lastCue = .none; divergence = .matched
        try capture.start()
        watch.send(.sessionStart)
        isRunning = true
    }

    public func stop() {
        capture.stop()
        watch.send(.sessionEnd)
        isRunning = false

        let summary = SessionSummary(
            id: sessionID,
            startedAt: startedAt,
            duration: elapsed,
            talkShare: divergence.talkShare,
            interruptions: turns.turns.filter { $0.speaker == .me && $0.isInterruption }.count,
            cues: policy.events,
            correctionRate: policy.correctionRate
        )
        store.persist(summary: summary, frames: frames)
    }

    // MARK: - Frame pipeline

    private func handle(_ samples: [Float]) {
        let sr = Float(AudioCapture.sampleRate)
        let db = DSP.rmsDBFS(samples)
        let zcr = DSP.zeroCrossingRate(samples)
        let speech = vad.isSpeech(dbfs: db, zcr: zcr)
        let f0 = speech ? DSP.fundamental(samples, sampleRate: sr) : 0
        let centroid = speech ? DSP.spectralCentroid(samples, sampleRate: sr) : 0

        if isEnrolling {
            if speech { classifier.enroll(dbfs: db, centroid: centroid, f0: f0) }
            return
        }

        frameIndex += 1
        let t = Double(frameIndex) * AudioCapture.frameSeconds
        elapsed = t

        let speaker: Speaker = speech
            ? classifier.classify(dbfs: db, centroid: centroid, f0: f0)
            : .silence

        let frame = Frame(t: t, speaker: speaker, dbfs: db, f0: f0,
                          syllableRate: speech ? DSP.syllableRate(samples, sampleRate: sr) : 0,
                          centroid: centroid)
        frames.append(frame)

        if let finished = turns.ingest(frame) { engine.ingest(finished) }
        engine.advance(to: t)

        let d = engine.current()
        divergence = d
        policy.scoreCorrection(at: t, current: d)

        if let cue = policy.evaluate(d, at: t) {
            lastCue = cue
            watch.send(cue, strain: d.strain)
        } else if metronomeEnabled, let cadence = engine.theirCadence(), t - lastTick >= cadence {
            lastTick = t
            watch.send(.metronomeTick, strain: d.strain)
        } else {
            watch.sendStrain(d.strain)
        }
    }
}
