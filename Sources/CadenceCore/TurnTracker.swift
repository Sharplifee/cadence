import Foundation

/// Collapses the frame stream into turns, and notices when you start talking
/// before they have finished.
public final class TurnTracker {
    private var current: (speaker: Speaker, start: TimeInterval, frames: [Frame])?
    private var lastEnd: TimeInterval = 0
    private var lastSpeaker: Speaker = .silence

    /// A turn must survive this long to count; below it, it is a backchannel
    /// ("mm-hm", "right") and should not be treated as taking the floor.
    /// Set above one analysis frame on purpose — a single 500 ms burst is
    /// exactly what agreement noise looks like, and counting it as a turn
    /// inflates your talk share with the sounds you make while listening.
    public var minTurnDuration: TimeInterval = 0.75

    public private(set) var turns: [Turn] = []

    public init() {}

    public func ingest(_ frame: Frame) -> Turn? {
        if frame.speaker == .silence {
            return current.map { _ in close(at: frame.t) } ?? nil
        }
        if let c = current, c.speaker == frame.speaker {
            current?.frames.append(frame)
            return nil
        }
        let finished = current != nil ? close(at: frame.t) : nil
        current = (frame.speaker, frame.t, [frame])
        return finished
    }

    private func close(at t: TimeInterval) -> Turn? {
        guard let c = current else { return nil }
        current = nil
        let duration = t - c.start
        guard duration >= minTurnDuration, !c.frames.isEmpty else { return nil }

        let n = Float(c.frames.count)
        let voiced = c.frames.filter { $0.f0 > 0 }
        let turn = Turn(
            speaker: c.speaker,
            start: c.start,
            end: t,
            meanDbfs: c.frames.reduce(0) { $0 + $1.dbfs } / n,
            meanF0: voiced.isEmpty ? 0 : voiced.reduce(0) { $0 + $1.f0 } / Float(voiced.count),
            meanSyllableRate: c.frames.reduce(0) { $0 + $1.syllableRate } / n,
            latency: c.speaker != lastSpeaker ? c.start - lastEnd : 0
        )
        turns.append(turn)
        lastEnd = t
        lastSpeaker = c.speaker
        return turn
    }
}
