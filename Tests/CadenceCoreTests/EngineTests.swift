import XCTest
@testable import CadenceCore

final class RingBufferTests: XCTestCase {
    func testWrapsAndKeepsNewest() {
        var b = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { b.append(i) }
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b.elements, [3, 4, 5])
    }
    func testEmpty() {
        let b = RingBuffer<Int>(capacity: 4)
        XCTAssertEqual(b.elements, [])
    }
}

final class TurnTrackerTests: XCTestCase {
    private func frame(_ t: Double, _ s: Speaker, db: Float = -20, rate: Float = 4) -> Frame {
        Frame(t: t, speaker: s, dbfs: db, f0: 120, syllableRate: rate, centroid: 900)
    }

    func testShortBurstsAreBackchannelsNotTurns() {
        let tracker = TurnTracker()
        _ = tracker.ingest(frame(0.5, .them))
        _ = tracker.ingest(frame(1.0, .me))     // 0.5 s of "mm-hm"
        _ = tracker.ingest(frame(1.5, .them))
        XCTAssertTrue(tracker.turns.allSatisfy { $0.speaker != .me },
                      "a sub-threshold backchannel must not count as taking the floor")
    }

    func testSustainedSpeechBecomesATurn() {
        let tracker = TurnTracker()
        for i in 1...8 { _ = tracker.ingest(frame(Double(i) * 0.5, .me)) }
        _ = tracker.ingest(frame(5.0, .silence))
        XCTAssertEqual(tracker.turns.count, 1)
        XCTAssertEqual(tracker.turns[0].speaker, .me)
        XCTAssertGreaterThan(tracker.turns[0].duration, 3)
    }
}

final class DivergenceEngineTests: XCTestCase {
    private func turn(_ s: Speaker, _ start: Double, _ end: Double,
                      db: Float, rate: Float, latency: Double = 0.4) -> Turn {
        Turn(speaker: s, start: start, end: end, meanDbfs: db, meanF0: 120,
             meanSyllableRate: rate, latency: latency)
    }

    func testAbstainsWithoutBothSpeakers() {
        let e = DivergenceEngine()
        e.ingest(turn(.me, 0, 3, db: -18, rate: 6))
        e.ingest(turn(.me, 4, 7, db: -18, rate: 6))
        XCTAssertEqual(e.current().confidence, 0,
                       "one-sided audio must report zero confidence, not a fake match")
    }

    func testDetectsFasterAndLouderThanThem() {
        let e = DivergenceEngine()
        var t = 0.0
        for _ in 0..<6 {
            e.ingest(turn(.them, t, t + 3, db: -30, rate: 4)); t += 3.5
            e.ingest(turn(.me, t, t + 6, db: -22, rate: 6)); t += 6.5
        }
        let d = e.current()
        XCTAssertEqual(d.rateRatio, 1.5, accuracy: 0.05)
        XCTAssertEqual(d.loudnessDelta, 8, accuracy: 0.5)
        XCTAssertEqual(d.turnLengthRatio, 2.0, accuracy: 0.05)
        XCTAssertGreaterThan(d.talkShare, 0.6)
        XCTAssertEqual(d.confidence, 1, accuracy: 0.01)
    }

    func testMatchedConversationReadsAsMatched() {
        let e = DivergenceEngine()
        var t = 0.0
        for _ in 0..<6 {
            e.ingest(turn(.them, t, t + 4, db: -26, rate: 4.5)); t += 4.5
            e.ingest(turn(.me, t, t + 4, db: -26, rate: 4.5)); t += 4.5
        }
        let d = e.current()
        XCTAssertEqual(d.rateRatio, 1, accuracy: 0.02)
        XCTAssertEqual(d.loudnessDelta, 0, accuracy: 0.02)
        XCTAssertEqual(d.talkShare, 0.5, accuracy: 0.02)
    }

    func testCountsInterruptions() {
        let e = DivergenceEngine()
        var t = 0.0
        for _ in 0..<6 {
            e.ingest(turn(.them, t, t + 3, db: -26, rate: 4)); t += 3
            e.ingest(turn(.me, t, t + 3, db: -26, rate: 4, latency: -0.6)); t += 3
        }
        XCTAssertGreaterThan(e.current().interruptRate, 2)
    }
}

final class CuePolicyTests: XCTestCase {
    private var loud: Divergence {
        Divergence(rateRatio: 1.6, loudnessDelta: 9, pitchDelta: 3,
                   turnLengthRatio: 2, talkShare: 0.8, interruptRate: 0, confidence: 1)
    }

    func testDoesNotFireBeforeSustainWindow() {
        let p = CuePolicy()
        XCTAssertNil(p.evaluate(loud, at: 0))
        XCTAssertNil(p.evaluate(loud, at: 5), "must not fire on a 5-second breach")
    }

    func testFiresAfterSustainedBreach() {
        let p = CuePolicy()
        _ = p.evaluate(loud, at: 0)
        XCTAssertNotNil(p.evaluate(loud, at: 11))
    }

    func testCooldownSuppressesRepeats() {
        let p = CuePolicy()
        _ = p.evaluate(loud, at: 0)
        XCTAssertNotNil(p.evaluate(loud, at: 11))
        XCTAssertNil(p.evaluate(loud, at: 25), "inside the 50 s cooldown nothing may fire")
        XCTAssertNil(p.evaluate(loud, at: 40))
    }

    func testAbstainsOnLowConfidence() {
        let p = CuePolicy()
        var d = loud; d.confidence = 0.2
        _ = p.evaluate(d, at: 0)
        XCTAssertNil(p.evaluate(d, at: 30), "never buzz on data we do not trust")
    }

    func testPrioritisesInterruptingOverPace() {
        let p = CuePolicy()
        var d = loud; d.interruptRate = 3
        _ = p.evaluate(d, at: 0)
        XCTAssertEqual(p.evaluate(d, at: 11), .stopOverlapping)
    }

    func testCorrectionScoring() {
        let p = CuePolicy()
        _ = p.evaluate(loud, at: 0)
        XCTAssertNotNil(p.evaluate(loud, at: 11))
        var improved = loud
        improved.talkShare = 0.5; improved.rateRatio = 1.0
        improved.loudnessDelta = 0; improved.interruptRate = 0
        p.scoreCorrection(at: 45, current: improved)
        XCTAssertEqual(p.correctionRate, 1.0)
    }
}

final class SpeakerGateTests: XCTestCase {
    func testAbstainsUntilEnrolled() {
        let c = NearFieldClassifier()
        XCTAssertFalse(c.isCalibrated)
    }

    func testSeparatesNearFieldFromFarField() {
        var c = NearFieldClassifier()
        for _ in 0..<80 { c.enroll(dbfs: -18, centroid: 800, f0: 115) }
        XCTAssertTrue(c.isCalibrated)
        XCTAssertEqual(c.classify(dbfs: -17, centroid: 820, f0: 118), .me)
        XCTAssertEqual(c.classify(dbfs: -34, centroid: 1600, f0: 210), .them)
    }
}

final class VoiceActivityTests: XCTestCase {
    func testTracksNoiseFloorAndDetectsSpeechAboveIt() {
        let vad = VoiceActivity()
        for _ in 0..<200 { _ = vad.isSpeech(dbfs: -60, zcr: 0.1) }
        XCTAssertFalse(vad.isSpeech(dbfs: -58, zcr: 0.1))
        XCTAssertTrue(vad.isSpeech(dbfs: -35, zcr: 0.1))
    }

    func testRejectsHighZeroCrossingNoise() {
        let vad = VoiceActivity()
        for _ in 0..<200 { _ = vad.isSpeech(dbfs: -60, zcr: 0.1) }
        XCTAssertFalse(vad.isSpeech(dbfs: -30, zcr: 0.8), "handling noise is not speech")
    }
}

final class StrainAndSensitivityTests: XCTestCase {
    func testStrainIsZeroWithoutConfidence() {
        XCTAssertEqual(Divergence.matched.strain, 0)
        XCTAssertEqual(Divergence.matched.headline, "Listening")
    }

    func testStrainTracksWorstAxis() {
        let d = Divergence(rateRatio: 1.0, loudnessDelta: 0, pitchDelta: 0,
                           turnLengthRatio: 1, talkShare: 0.85,
                           interruptRate: 0, confidence: 1)
        XCTAssertEqual(d.strain, 1.0, accuracy: 0.01)
        XCTAssertEqual(d.headline, "Running away")
    }

    func testMatchedConversationReadsInStep() {
        let d = Divergence(rateRatio: 1.05, loudnessDelta: 1, pitchDelta: 0,
                           turnLengthRatio: 1, talkShare: 0.52,
                           interruptRate: 0, confidence: 1)
        XCTAssertLessThan(d.strain, 0.45)
        XCTAssertEqual(d.headline, "In step")
    }

    func testSensitivityMovesEveryThresholdMonotonically() {
        let low = CuePolicy(); low.applySensitivity(0)
        let high = CuePolicy(); high.applySensitivity(1)
        XCTAssertGreaterThan(low.thresholds.rateRatio, high.thresholds.rateRatio)
        XCTAssertGreaterThan(low.thresholds.loudnessDelta, high.thresholds.loudnessDelta)
        XCTAssertGreaterThan(low.thresholds.talkShare, high.thresholds.talkShare)
        XCTAssertGreaterThan(low.thresholds.interruptRate, high.thresholds.interruptRate)
        XCTAssertGreaterThan(low.sustainDuration, high.sustainDuration)
    }

    func testEagerSensitivityFiresWhereCautiousDoesNot() {
        let d = Divergence(rateRatio: 1.25, loudnessDelta: 5, pitchDelta: 0,
                           turnLengthRatio: 1.4, talkShare: 0.65,
                           interruptRate: 1.6, confidence: 1)
        let cautious = CuePolicy(); cautious.applySensitivity(0)
        _ = cautious.evaluate(d, at: 0)
        XCTAssertNil(cautious.evaluate(d, at: 30))

        let eager = CuePolicy(); eager.applySensitivity(1)
        _ = eager.evaluate(d, at: 0)
        XCTAssertNotNil(eager.evaluate(d, at: 30))
    }
}

final class CuePatternTests: XCTestCase {
    func testEveryCueHasADistinctRhythm() {
        let cues: [CueCode] = [.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping]
        let patterns = cues.map { CuePattern.pattern(for: $0) }
        for i in patterns.indices {
            for j in patterns.indices where i != j {
                XCTAssertNotEqual(patterns[i], patterns[j],
                                  "two cues share a rhythm and cannot be told apart")
            }
        }
    }

    func testScheduleOffsetsAccumulate() {
        let p = CuePattern(pulses: [.init(on: 0.1, gap: 0.2), .init(on: 0.1, gap: 0)])
        let s = p.schedule
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].at, 0, accuracy: 0.001)
        XCTAssertEqual(s[1].at, 0.3, accuracy: 0.001)
        XCTAssertEqual(p.duration, 0.4, accuracy: 0.001)
    }

    func testNoneIsSilent() {
        XCTAssertTrue(CuePattern.pattern(for: .none).pulses.isEmpty)
        XCTAssertEqual(CuePattern.pattern(for: .none).duration, 0)
    }

    func testPatternsAreShortEnoughToLandInAConversation() {
        for c in CueCode.allCases {
            XCTAssertLessThan(CuePattern.pattern(for: c).duration, 1.0,
                              "\(c.label) takes too long to feel")
        }
    }
}

final class EscalationTests: XCTestCase {
    func testLadderClimbsWithIgnoredCues() {
        var s = CueSettings()
        let t = EscalationTracker { s }
        _ = s
        var last = (streak: 0, channels: Channels.silent, tier: 0)
        for i in 1...6 { last = t.register(at: Double(i) * 60) }
        XCTAssertEqual(last.streak, 6)
        XCTAssertEqual(last.tier, 3)
        XCTAssertTrue(last.channels.contains(.flash))
    }

    func testFirstCuesAreHapticOnly() {
        let s = CueSettings()
        let t = EscalationTracker { s }
        let r = t.register(at: 0)
        XCTAssertEqual(r.tier, 1)
        XCTAssertTrue(r.channels.contains(.haptic))
        XCTAssertFalse(r.channels.contains(.sound))
        XCTAssertFalse(r.channels.contains(.flash))
    }

    func testCorrectingResetsTheLadder() {
        let s = CueSettings()
        let t = EscalationTracker { s }
        for i in 1...5 { _ = t.register(at: Double(i) * 60) }
        t.registerCorrection()
        XCTAssertEqual(t.register(at: 400).tier, 1,
                       "correcting must drop you back to a private nudge")
    }

    func testStreakDecaysAfterQuietPeriod() {
        let s = CueSettings()
        let t = EscalationTracker { s }
        for i in 1...5 { _ = t.register(at: Double(i) * 60) }
        XCTAssertEqual(t.register(at: 5000).streak, 1)
    }

    func testAllowedChannelsCapTheLadder() {
        var s = CueSettings()
        s.allowed = [.haptic, .sound]        // user has switched flashing off
        let t = EscalationTracker { s }
        var last = (streak: 0, channels: Channels.silent, tier: 0)
        for i in 1...9 { last = t.register(at: Double(i) * 60) }
        XCTAssertEqual(last.tier, 3)
        XCTAssertFalse(last.channels.contains(.flash),
                       "an explicit user opt-out must survive every escalation tier")
    }

    func testSilentModeNeverMakesNoise() {
        var s = CueSettings()
        s.allowed = .silent
        let t = EscalationTracker { s }
        var last = (streak: 0, channels: Channels.all, tier: 0)
        for i in 1...12 { last = t.register(at: Double(i) * 60) }
        XCTAssertEqual(last.channels, .haptic)
    }
}

final class EnrollmentScriptTests: XCTestCase {
    func testScriptIsLongEnoughToReadForThirtySeconds() {
        // ~150 words/min conversational -> 2.5 words/sec -> ~75 words for 30 s.
        let words = EnrollmentScript.lines.joined(separator: " ")
            .split(separator: " ").count
        XCTAssertGreaterThan(words, 60)
        XCTAssertLessThan(words, 110, "too long to finish inside the timer")
    }

    func testScriptCoversTheAlphabet() {
        // A profile built from a narrow sound range only matches a narrow voice.
        let text = EnrollmentScript.lines.joined().lowercased()
        let missing = "abcdefghijklmnopqrstuvwxyz".filter { !text.contains($0) }
        XCTAssertTrue(missing.isEmpty, "script never exercises: \(String(missing))")
    }

    func testLineIndexStaysInBounds() {
        XCTAssertEqual(EnrollmentScript.lineIndex(atFraction: -1), 0)
        XCTAssertEqual(EnrollmentScript.lineIndex(atFraction: 0), 0)
        XCTAssertEqual(EnrollmentScript.lineIndex(atFraction: 2),
                       EnrollmentScript.lines.count - 1)
    }
}
