import Foundation

/// One extracted thing you can accept or dismiss.
///
/// Everything the loop produces lands here as a proposal, never as a fact.
/// Nothing reaches your calendar without you saying yes, because an app that
/// silently writes to your calendar gets deleted the first time it is wrong.
public struct ActionItem: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var kind: Commitment.Kind
    public var text: String
    /// When the audio was captured.
    public var capturedAt: Date
    /// Parsed from the words, if a date was found at all.
    public var dueAt: Date?
    public var hasExplicitTime: Bool
    /// The words that produced the date, shown so you can see why.
    public var dateEvidence: String?
    /// User decision. Nil until they choose.
    public var accepted: Bool?
    /// Set once it is actually on the calendar, so it cannot be added twice.
    public var calendarEventID: String?

    public init(id: UUID = UUID(), kind: Commitment.Kind, text: String,
                capturedAt: Date = Date(), dueAt: Date? = nil,
                hasExplicitTime: Bool = false, dateEvidence: String? = nil,
                accepted: Bool? = nil, calendarEventID: String? = nil) {
        self.id = id; self.kind = kind; self.text = text
        self.capturedAt = capturedAt; self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime; self.dateEvidence = dateEvidence
        self.accepted = accepted; self.calendarEventID = calendarEventID
    }

    public var isOnCalendar: Bool { calendarEventID != nil }
    /// Only things with a date can become calendar events; the rest are notes.
    public var isSchedulable: Bool { dueAt != nil && !isOnCalendar }

    /// What the event is called on the calendar. The raw sentence is how you
    /// recognise it three days later; a tidy summary is how you fail to.
    public var calendarTitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        switch kind {
        case .promise:    return short
        case .offer:      return short
        case .request:    return "Asked: \(short)"
        case .scheduling: return short
        }
    }

    /// Duration for a calendar entry. A named hour is a soft target, so it gets
    /// a wider block than a time someone actually agreed.
    public var suggestedDuration: TimeInterval { hasExplicitTime ? 1800 : 3600 }
}

/// The review queue: everything the loop has proposed and not yet resolved.
public struct ActionQueue: Codable, Sendable, Equatable {
    public private(set) var items: [ActionItem] = []

    public init(items: [ActionItem] = []) { self.items = items }

    /// Adds only genuinely new items.
    ///
    /// A five-minute loop overlaps in practice — the same sentence can be heard
    /// at the end of one segment and the start of the next — so identical text
    /// captured close together is one thing, not two.
    public mutating func add(_ new: [ActionItem], dedupeWindow: TimeInterval = 900) {
        for item in new {
            let duplicate = items.contains { existing in
                existing.text.caseInsensitiveCompare(item.text) == .orderedSame &&
                abs(existing.capturedAt.timeIntervalSince(item.capturedAt)) < dedupeWindow
            }
            if !duplicate { items.append(item) }
        }
        items.sort { $0.capturedAt > $1.capturedAt }
    }

    public mutating func setAccepted(_ id: UUID, _ value: Bool?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].accepted = value
    }

    public mutating func markOnCalendar(_ id: UUID, eventID: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].calendarEventID = eventID
        items[i].accepted = true
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    /// Still waiting on a yes or no.
    public var undecided: [ActionItem] { items.filter { $0.accepted == nil } }
    /// Accepted, dated, and not yet written to the calendar.
    public var readyForCalendar: [ActionItem] {
        items.filter { $0.accepted == true && $0.isSchedulable }
    }
    public var onCalendar: [ActionItem] { items.filter(\.isOnCalendar) }
}

public enum ActionExtractor {
    /// Turn a transcript into proposals, dates included.
    public static func items(from utterances: [Utterance],
                             capturedAt: Date,
                             now: Date = Date()) -> [ActionItem] {
        CommitmentExtractor.extract(from: utterances).map { c in
            let phrase = DatePhraseParser.parse(c.text, now: now)
            return ActionItem(kind: c.kind, text: c.text, capturedAt: capturedAt,
                              dueAt: phrase?.date,
                              hasExplicitTime: phrase?.hasExplicitTime ?? false,
                              dateEvidence: phrase?.matched)
        }
    }
}
