import Foundation

/// Something said that creates an obligation or an ask.
public struct Commitment: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// You said you would do something.
        case promise
        /// You offered something.
        case offer
        /// Someone asked you for something.
        case request
        /// A time or date was agreed.
        case scheduling

        public var label: String {
            switch self {
            case .promise:    return "you committed"
            case .offer:      return "you offered"
            case .request:    return "they asked"
            case .scheduling: return "a time was set"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var speaker: Speaker
    public var at: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), kind: Kind, speaker: Speaker,
                at: TimeInterval, text: String) {
        self.id = id; self.kind = kind; self.speaker = speaker
        self.at = at; self.text = text
    }
}

/// Pulls commitments out of a transcript.
///
/// Deliberately pattern-based rather than a model: it runs on device with no
/// network, costs nothing, and is auditable — you can read exactly why a line
/// was flagged. It over-flags rather than under-flags, because a missed promise
/// is the failure that actually costs you something.
public enum CommitmentExtractor {
    private static let promise = [
        "i'll ", "i will ", "i'm going to ", "i am going to ", "i can ",
        "let me ", "i'll get ", "i'll send ", "i'll call ", "i'll have ",
        "i promise", "consider it done", "i've got it", "leave it with me"
    ]
    private static let offer = [
        "i could ", "want me to", "do you want me", "happy to ", "i'd be glad",
        "if you want i", "shall i ", "should i "
    ]
    private static let request = [
        "can you ", "could you ", "would you ", "will you ", "send me",
        "let me know", "i need you", "do you mind", "please "
    ]
    private static let scheduling = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday", "tomorrow", "next week", "this week", "tonight",
        "by friday", "end of day", "end of week", "o'clock", " am ", " pm ",
        "first thing"
    ]

    public static func extract(from utterances: [Utterance]) -> [Commitment] {
        var out: [Commitment] = []
        for u in utterances {
            let t = " " + u.text.lowercased() + " "

            // Who is speaking decides what a phrase means. "Can you send it"
            // from them is a request of you; the same words from you are a
            // request of them, and only the first is your problem.
            if u.speaker == .me {
                if promise.contains(where: t.contains) {
                    out.append(Commitment(kind: .promise, speaker: .me, at: u.start, text: u.text))
                } else if offer.contains(where: t.contains) {
                    out.append(Commitment(kind: .offer, speaker: .me, at: u.start, text: u.text))
                }
            } else if u.speaker == .them, request.contains(where: t.contains) {
                out.append(Commitment(kind: .request, speaker: .them, at: u.start, text: u.text))
            }

            // Scheduling is worth catching from either side, but only when it
            // rides along with an actual commitment or ask — otherwise every
            // mention of "Tuesday" becomes a task.
            if scheduling.contains(where: t.contains),
               promise.contains(where: t.contains) || request.contains(where: t.contains) {
                out.append(Commitment(kind: .scheduling, speaker: u.speaker,
                                      at: u.start, text: u.text))
            }
        }
        return out
    }
}
