import Foundation

/// Which device produced a piece of audio.
public enum CaptureSource: String, Codable, Sendable, CaseIterable {
    case phone, watch

    /// The phone's microphone is better placed and better quality, so where
    /// both devices heard the same minute, the phone's version wins.
    public var preference: Int { self == .phone ? 0 : 1 }

    public var label: String { self == .phone ? "phone" : "watch" }
}

/// A recorded stretch from one device.
public struct CaptureRun: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var source: CaptureSource
    public var start: Date
    public var end: Date
    public var filename: String

    public init(id: UUID = UUID(), source: CaptureSource, start: Date,
                end: Date, filename: String) {
        self.id = id; self.source = source; self.start = start
        self.end = end; self.filename = filename
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One chosen stretch of the final timeline.
public struct CoverageSpan: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Nil means neither device was recording — a real hole.
    public var source: CaptureSource?
    public var start: Date
    public var end: Date
    public var filename: String?

    public init(id: UUID = UUID(), source: CaptureSource?, start: Date,
                end: Date, filename: String? = nil) {
        self.id = id; self.source = source; self.start = start
        self.end = end; self.filename = filename
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var isGap: Bool { source == nil }
}

/// Decides, minute by minute, which device's audio to actually use.
///
/// The phone has the better microphone but loses the session to every call,
/// voice memo and other recorder — and after a call, a backgrounded app often
/// cannot reactivate its session at all until you reopen it. The watch has a
/// worse microphone but its own audio session, so nothing you do on the phone
/// touches it.
///
/// So: record on both, prefer the phone wherever it managed to capture, and let
/// the watch fill only the holes. You get the good microphone most of the time
/// and never a missing stretch.
public enum CaptureMerger {
    /// Stretches shorter than this are dropped. Clocks on two devices are NTP
    /// synced but not identical, and a half-second sliver of watch audio
    /// between two phone runs is skew, not content.
    public static let minimumSpan: TimeInterval = 1.5

    public static func plan(runs: [CaptureRun],
                            from windowStart: Date? = nil,
                            to windowEnd: Date? = nil) -> [CoverageSpan] {
        guard !runs.isEmpty else { return [] }

        let start = windowStart ?? runs.map(\.start).min()!
        let end = windowEnd ?? runs.map(\.end).max()!
        guard end > start else { return [] }

        // Every instant where the answer could change.
        var edges: Set<TimeInterval> = [start.timeIntervalSince1970, end.timeIntervalSince1970]
        for r in runs {
            if r.start > start, r.start < end { edges.insert(r.start.timeIntervalSince1970) }
            if r.end > start, r.end < end { edges.insert(r.end.timeIntervalSince1970) }
        }
        let points = edges.sorted()

        var spans: [CoverageSpan] = []
        for i in 0..<(points.count - 1) {
            let a = Date(timeIntervalSince1970: points[i])
            let b = Date(timeIntervalSince1970: points[i + 1])
            let mid = Date(timeIntervalSince1970: (points[i] + points[i + 1]) / 2)

            // Phone first, then watch. Ties inside a source go to the run that
            // started earlier so the audio is contiguous.
            let covering = runs
                .filter { $0.start <= mid && $0.end >= mid }
                .sorted { l, r in
                    l.source.preference != r.source.preference
                        ? l.source.preference < r.source.preference
                        : l.start < r.start
                }
            let winner = covering.first
            spans.append(CoverageSpan(source: winner?.source, start: a, end: b,
                                      filename: winner?.filename))
        }

        return merge(spans.filter { $0.duration >= minimumSpan })
    }

    /// Collapse neighbours that came from the same file, so a plan reads as a
    /// handful of stretches rather than one row per edge.
    private static func merge(_ spans: [CoverageSpan]) -> [CoverageSpan] {
        var out: [CoverageSpan] = []
        for s in spans {
            if var last = out.last, last.source == s.source, last.filename == s.filename,
               abs(last.end.timeIntervalSince(s.start)) < 0.001 {
                last.end = s.end
                out[out.count - 1] = last
            } else {
                out.append(s)
            }
        }
        return out
    }

    /// Stretches where neither device was recording. This is what the review
    /// screen has to show honestly rather than presenting a transcript with
    /// silent holes in it.
    public static func gaps(in plan: [CoverageSpan]) -> [CoverageSpan] {
        plan.filter(\.isGap)
    }

    /// How much of the window the phone actually managed, 0–1. Worth surfacing:
    /// if this is persistently low, the phone loop is not earning its battery.
    public static func phoneShare(of plan: [CoverageSpan]) -> Double {
        let total = plan.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return 0 }
        let phone = plan.filter { $0.source == .phone }.reduce(0.0) { $0 + $1.duration }
        return phone / total
    }
}
