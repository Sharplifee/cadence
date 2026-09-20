import Foundation

/// A fixed-duration window of recent audio, kept as rotating segments.
///
/// The point of an always-on loop is that you do not decide to record — you
/// decide, after the fact, that the last few minutes mattered. So audio is
/// written continuously into short segments and the oldest are deleted once the
/// window is full. Nothing is kept unless you mark it.
///
/// Segments rather than one growing file for three reasons: deleting the oldest
/// minute is a file delete instead of a rewrite, a crash costs one segment
/// instead of the whole buffer, and freezing a mark is a copy of a few files.
public struct RollingBuffer: Equatable {
    public struct Segment: Equatable, Codable, Sendable {
        public var index: Int
        public var start: TimeInterval
        public var duration: TimeInterval
        public var filename: String

        public var end: TimeInterval { start + duration }
        public init(index: Int, start: TimeInterval, duration: TimeInterval, filename: String) {
            self.index = index; self.start = start
            self.duration = duration; self.filename = filename
        }
    }

    /// How much history to keep. Ten minutes at 16 kHz mono AAC is ~700 kB.
    public let window: TimeInterval
    public let segmentLength: TimeInterval

    public private(set) var segments: [Segment] = []
    private var nextIndex = 0

    public init(window: TimeInterval = 600, segmentLength: TimeInterval = 30) {
        self.window = max(window, segmentLength)
        self.segmentLength = segmentLength
    }

    public var coveredDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    public var oldestTime: TimeInterval { segments.first?.start ?? 0 }

    /// Close the current segment and open the next. Returns any segments that
    /// have aged out and whose files the caller should delete.
    @discardableResult
    public mutating func rotate(at t: TimeInterval) -> [Segment] {
        let seg = Segment(index: nextIndex,
                          start: max(0, t - segmentLength),
                          duration: segmentLength,
                          filename: "seg-\(nextIndex).m4a")
        nextIndex += 1
        segments.append(seg)

        var expired: [Segment] = []
        while coveredDuration > window, let oldest = segments.first {
            segments.removeFirst()
            expired.append(oldest)
        }
        return expired
    }

    /// The segments needed to play back the `lookback` seconds before `t`.
    /// This is what a mark freezes.
    public func segments(coveringLast lookback: TimeInterval, endingAt t: TimeInterval) -> [Segment] {
        let from = t - lookback
        return segments.filter { $0.end > from && $0.start < t }
    }

    /// The recorder names its own files, so the segment the buffer just opened
    /// has to be corrected to match what actually landed on disk.
    public mutating func replaceLast(with segment: Segment) {
        guard !segments.isEmpty else { return }
        segments[segments.count - 1] = segment
    }

    public mutating func reset() { segments.removeAll(); nextIndex = 0 }
}
