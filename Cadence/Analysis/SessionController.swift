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
    /// Live signals the UI needs so you can see it working rather than trust it.
    @Published public private(set) var level: Float = -60
    @Published public private(set) var currentSpeaker: Speaker = .silence
    @Published public private(set) var liveText: String = ""
    @Published public private(set) var utterances: [Utterance] = []
    @Published public private(set) var transcribing = false
    @Published public var sessionTitle: String = ""
    @Published public private(set) var warning: String?

    @Published public var settings = CueSettings()
    @Published public private(set) var watchReady = false

    public var metronomeEnabled: Bool {
        get { settings.metronomeEnabled }
        set { settings.metronomeEnabled = newValue }
    }

    private let capture = AudioCapture()
    private let vad = VoiceActivity()
    private var classifier: SpeakerClassifier = NearFieldClassifier()
    private let turns = TurnTracker()
    private let engine = DivergenceEngine()
    private let policy = CuePolicy()
    private let watch = WatchBridge()
    private let store = SessionStore()
    private let cuePlayer = CuePlayer()
    private let transcriber = Transcriber()
    private let recorder = SessionRecorder()
    private let launcher = WatchLauncher()
    private lazy var escalation = EscalationTracker { [weak self] in
        self?.settings ?? CueSettings()
    }

    private var sessionID = UUID()
    private var startedAt = Date()
    private var frameIndex = 0
    private var frames: [Frame] = []
    private var lastTick: TimeInterval = 0
    private var sessionDir: URL?
    private var utteranceStart: TimeInterval = 0
    private var utteranceSpeaker: Speaker = .silence
    private var lastCommittedText = ""
    private var lastRecognizerRestart: TimeInterval = 0
    private var frameLevels: [Float] = []

    public init() {
        capture.onFrame = { [weak self] samples in
            Task { @MainActor in self?.handle(samples) }
        }
        policy.applySensitivity(0.5)
        settings = SettingsStore.load()

        // Start/stop from the wrist drives the phone, not just the reverse.
        watch.onRemoteToggle = { [weak self] start in
            guard let self else { return }
            if start, !self.isRunning { try? self.start() }
            else if !start, self.isRunning { self.stop() }
        }

        transcriber.onPartial = { [weak self] text in
            guard let self else { return }
            self.liveText = text
            self.commitIfSpeakerChanged(text: text)
        }
    }

    public func persistSettings() { SettingsStore.save(settings) }

    public static func requestTranscriptionPermission() async -> Bool {
        await Transcriber.requestAuthorization()
    }

    // MARK: - Control

    public func applySensitivity(_ value: Double) {
        policy.applySensitivity(Float(value))
    }

    /// Fires a cue on demand across whatever channels are enabled, for the
    /// onboarding and settings screens. Learning the vocabulary should not
    /// require a bad conversation.
    public func preview(_ cue: CueCode, tier: Int = 1) {
        let channels = settings.resolvedChannels(streak: tier == 1 ? 1 : (tier == 2 ? settings.escalation.tier2At : settings.escalation.tier3At))
        deliver(cue, channels: channels, tier: tier)
    }

    /// One place decides what plays and where, so the phone and the wrist can
    /// never fall out of step about it.
    private func deliver(_ cue: CueCode, channels: Channels, tier: Int) {
        if settings.devices.contains(.phone) {
            cuePlayer.play(cue, channels: channels, tier: tier)
        }
        if settings.devices.contains(.watch) {
            watch.send(cue, strain: divergence.strain, channels: channels,
                       tier: tier, talkShare: Double(divergence.talkShare))
        }
    }

    public func prepareWatch() async {
        _ = await launcher.requestAuthorization()
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
        utterances.removeAll(); liveText = ""; lastCommittedText = ""
        warning = nil
        escalation.reset()

        sessionDir = store.directory(for: sessionID)
        if let dir = sessionDir { recorder.start(sessionID: sessionID, in: dir) }

        if transcriber.isAvailable {
            transcriber.start()
            transcribing = true
        } else {
            // Coaching still works without it — say so rather than pretending.
            transcribing = false
            warning = "Transcription is off: on-device speech recognition isn't available. Cues still work."
        }

        try capture.start()

        // Starting on the phone must start the watch too. This is one app on
        // two devices, so requiring the user to open both is a bug, not a step.
        if settings.devices.contains(.watch) {
            Task { @MainActor in
                do {
                    try await launcher.launchWatchApp()
                    watchReady = true
                } catch {
                    // The watch may be absent, locked or out of range. The
                    // phone still coaches on its own — degrade, never block.
                    watchReady = false
                }
                watch.send(.sessionStart, strain: 0, channels: .silent, tier: 1)
            }
        }
        isRunning = true
    }

    public func stop() {
        capture.stop()
        transcriber.stop(); transcribing = false
        commitUtterance(at: elapsed)
        let hasAudio = recorder.finish()
        watch.send(.sessionEnd, strain: 0, channels: .silent, tier: 1)
        isRunning = false

        let summary = SessionSummary(
            id: sessionID,
            startedAt: startedAt,
            duration: elapsed,
            talkShare: divergence.talkShare,
            interruptions: turns.turns.filter { $0.speaker == .me && $0.isInterruption }.count,
            cues: policy.events,
            correctionRate: policy.correctionRate,
            title: sessionTitle.isEmpty ? nil : sessionTitle,
            utterances: utterances,
            insights: Insights.derive(from: utterances, turns: turns.turns),
            hasAudio: hasAudio
        )
        sessionTitle = ""
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

        level = db
        currentSpeaker = speaker
        recorder.append(samples)
        transcriber.append(samples, sampleRate: AudioCapture.sampleRate)

        // SFSpeechRecognizer stops silently after about a minute per task, so
        // it is cycled on a speaker change rather than mid-sentence.
        if t - lastRecognizerRestart > 50, speaker == .silence, transcribing {
            lastRecognizerRestart = t
            commitUtterance(at: t)
            transcriber.restart()
        }

        if speaker != .silence, utteranceSpeaker == .silence {
            utteranceSpeaker = speaker; utteranceStart = t; frameLevels = []
        }
        if speaker != .silence { frameLevels.append(db) }

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
            let step = escalation.register(at: t)
            deliver(cue, channels: step.channels, tier: step.tier)
        } else if settings.metronomeEnabled,
                  let cadence = engine.theirCadence(), t - lastTick >= cadence {
            lastTick = t
            deliver(.metronomeTick, channels: [.haptic], tier: 1)
        } else {
            watch.sendStrain(d.strain)
        }

        // Acting on a cue drops you back to a private nudge. The ladder is a
        // response to being ignored, not to being imperfect.
        if policy.events.last?.corrected == true { escalation.registerCorrection() }
    }
}


// MARK: - Transcript assembly

extension SessionController {
    /// The recogniser has no idea who is talking; the speaker gate does. A
    /// change of speaker is what closes an utterance and starts the next.
    fileprivate func commitIfSpeakerChanged(text: String) {
        guard currentSpeaker != .silence, utteranceSpeaker != .silence,
              currentSpeaker != utteranceSpeaker else { return }
        commitUtterance(at: elapsed)
        utteranceSpeaker = currentSpeaker
        utteranceStart = elapsed
    }

    fileprivate func commitUtterance(at t: TimeInterval) {
        let newText = String(liveText.dropFirst(lastCommittedText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defer { lastCommittedText = liveText; frameLevels = [] }
        guard utteranceSpeaker != .silence, !newText.isEmpty, t > utteranceStart else {
            utteranceSpeaker = .silence
            return
        }
        let meanDb = frameLevels.isEmpty ? 0 : frameLevels.reduce(0,+) / Float(frameLevels.count)
        utterances.append(Utterance(speaker: utteranceSpeaker, start: utteranceStart,
                                    end: t, text: newText, meanDbfs: meanDb))
        utteranceSpeaker = .silence
    }
}
