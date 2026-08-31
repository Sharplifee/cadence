import Foundation

/// Their last 90 seconds is the target. Everything here measures how far you
/// have drifted from it.
public final class DivergenceEngine {
    private let window: TimeInterval = 90
    private var turns = RingBuffer<Turn>(capacity: 240)
    private var now: TimeInterval = 0

    public init() {}

    public func ingest(_ turn: Turn) {
        turns.append(turn)
        now = max(now, turn.end)
    }

    public func advance(to t: TimeInterval) { now = max(now, t) }

    public func current() -> Divergence {
        let recent = turns.elements.filter { now - $0.end <= window }
        let mine = recent.filter { $0.speaker == .me }
        let theirs = recent.filter { $0.speaker == .them }

        // Without both sides there is nothing to compare against. Say so with
        // confidence 0 rather than inventing a number.
        guard mine.count >= 2, theirs.count >= 2 else { return .matched }

        let myRate = mean(mine.map { $0.meanSyllableRate })
        let theirRate = mean(theirs.map { $0.meanSyllableRate })
        let myDb = mean(mine.map { $0.meanDbfs })
        let theirDb = mean(theirs.map { $0.meanDbfs })
        let myF0 = mean(mine.filter { $0.meanF0 > 0 }.map { $0.meanF0 })
        let theirF0 = mean(theirs.filter { $0.meanF0 > 0 }.map { $0.meanF0 })
        let myLen = mean(mine.map { Float($0.duration) })
        let theirLen = mean(theirs.map { Float($0.duration) })

        let myTime = mine.reduce(0.0) { $0 + $1.duration }
        let theirTime = theirs.reduce(0.0) { $0 + $1.duration }
        let share = (myTime + theirTime) > 0 ? Float(myTime / (myTime + theirTime)) : 0.5

        let spanMinutes = Float(max(window, 1)) / 60
        let interrupts = Float(mine.filter { $0.isInterruption }.count) / spanMinutes

        // Confidence scales with how much of both speakers we actually have.
        let coverage = Float(min(mine.count, theirs.count)) / 6
        let confidence = min(coverage, 1)

        return Divergence(
            rateRatio: theirRate > 0.1 ? myRate / theirRate : 1,
            loudnessDelta: myDb - theirDb,
            pitchDelta: DSP.semitones(myF0, theirF0),
            turnLengthRatio: theirLen > 0.1 ? myLen / theirLen : 1,
            talkShare: share,
            interruptRate: interrupts,
            confidence: confidence
        )
    }

    /// The tick interval for metronome mode: their median turn cadence.
    public func theirCadence() -> TimeInterval? {
        let theirs = turns.elements.filter { $0.speaker == .them && now - $0.end <= window }
        guard theirs.count >= 3 else { return nil }
        let sorted = theirs.map { $0.duration }.sorted()
        return sorted[sorted.count / 2]
    }

    private func mean(_ xs: [Float]) -> Float {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Float(xs.count)
    }
}
