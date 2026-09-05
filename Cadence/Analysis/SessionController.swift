import AVFoundation
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
    @Published public private(set) var isEnrolled = false

    public var metronomeEnabled: Bool {
        get { settings.metronomeEnabled }
        set { settings.metronomeEnabled = newValue }
    }

    private let capture = AudioCapture()
    private let vad = VoiceActivity()
    private let analyzer = FrameAnalyzer(sampleRate: Float(AudioCapture.sampleRate))
    private let dspQueue = DispatchQueue(label: "cadence.dsp", qos: .userInitiated)
    private let assembler = TranscriptAssembler()
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
    private var lastRecognizerRestart: TimeInterval = 0
    private var scoredCueCount = 0
    private var lastScoredCorrection = -1

    public init() {
        // DSP runs on the audio-processing queue; only the finished numbers
        // hop to the main actor. Doing the FFT and autocorrelation on the main
        // actor competed with SwiftUI for exactly the frames it was animating.
        capture.onFrame = { [weak self] samples in
            guard let self else { return }
            self.dspQueue.async {
                let r = self.analyzer.analyze(samples, vad: self.vad)
                Task { @MainActor in self.apply(r, samples: samples) }
            }
        }
        policy.applySensitivity(0.5)
        settings = SettingsStore.load()

        // Restore the voice profile, or the app relaunches into a dead state.
        if let p = VoiceProfileStore.load() {
            classifier.restore(p)
            isEnrolled = true
        }

        // Start/stop from the wrist drives the phone, not just the reverse.
        watch.onRemoteToggle = { [weak self] start in
            guard let self else { return }
            if start, !self.isRunning { try? self.start() }
            else if !start, self.isRunning { self.stop() }
        }

        transcriber.onPartial = { [weak self] text in
            self?.ingestRecognizedText(text)
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
        if let p = classifier.profile {
            VoiceProfileStore.save(p)
            isEnrolled = true
        }
    }

    public func clearEnrollment() {
        VoiceProfileStore.clear()
        classifier = NearFieldClassifier()
        isEnrolled = false
    }

    public func start() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw NSError(domain: "Cadence", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access is off. Turn it on in iOS Settings, Self Attune, Microphone."
            ])
        }
        guard classifier.isCalibrated else {
            throw NSError(domain: "Cadence", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Record your voice profile first — Settings, then Re-record voice profile."
            ])
        }
        sessionID = UUID(); startedAt = Date()
        frameIndex = 0; frames.removeAll(); elapsed = 0
        lastCue = .none; divergence = .matched
        assembler.reset(); utterances.removeAll(); liveText = ""
        scoredCueCount = 0; lastScoredCorrection = -1
        lastRecognizerRestart = 0
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
        assembler.finish(text: liveText, at: elapsed)
        utterances = assembler.utterances
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

    /// Runs on the main actor with the DSP already done.
    private func apply(_ r: FrameAnalyzer.Result, samples: [Float]) {
        if isEnrolling {
            if r.isSpeech {
                classifier.enroll(dbfs: r.dbfs, centroid: r.centroid, f0: r.f0)
            }
            level = r.dbfs
            return
        }

        frameIndex += 1
        let t = Double(frameIndex) * AudioCapture.frameSeconds
        elapsed = t
        level = r.dbfs

        let speaker: Speaker = r.isSpeech
            ? classifier.classify(dbfs: r.dbfs, centroid: r.centroid, f0: r.f0)
            : .silence
        currentSpeaker = speaker

        recorder.append(samples)
        transcriber.append(samples, sampleRate: AudioCapture.sampleRate)
        assembler.observe(speaker: speaker, dbfs: r.dbfs, at: t)

        // SFSpeechRecognizer stops silently after roughly a minute per task.
        // Cycle it during a pause, and tell the assembler — its committed
        // prefix must reset with it or every later utterance comes out empty.
        if t - lastRecognizerRestart > 50, speaker == .silence, transcribing {
            lastRecognizerRestart = t
            assembler.recognizerRestarted(at: t, finalText: liveText)
            utterances = assembler.utterances
            liveText = ""
            transcriber.restart()
        }

        let frame = Frame(t: t, speaker: speaker, dbfs: r.dbfs, f0: r.f0,
                          syllableRate: r.syllableRate, centroid: r.centroid)
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
            scoredCueCount = policy.events.count
        } else if settings.metronomeEnabled,
                  let cadence = engine.theirCadence(),
                  t - lastTick >= max(cadence, 2.0) {
            lastTick = t
            deliver(.metronomeTick, channels: [.haptic], tier: 1)
        } else {
            watch.sendStrain(d.strain)
        }

        // Only credit a correction once per cue, not on every frame after it.
        if policy.events.count == scoredCueCount,
           let last = policy.events.last, last.corrected == true,
           lastScoredCorrection != scoredCueCount {
            lastScoredCorrection = scoredCueCount
            escalation.registerCorrection()
        }
    }
}

// MARK: - Transcript

extension SessionController {
    /// The recogniser produced new text. Attribution is the speaker gate's job,
    /// not the recogniser's — it has no idea who is talking.
    fileprivate func ingestRecognizedText(_ text: String) {
        liveText = text
        assembler.update(text: text, speaker: currentSpeaker, at: elapsed)
        if assembler.utterances.count != utterances.count {
            utterances = assembler.utterances
        }
    }
}
