import Foundation

/// A recognised utterance, attributed to a speaker.
///
/// Transcription and the divergence engine run off the same frame stream, so a
/// transcript line can always be matched back to the numbers that were true
/// while it was being said. That is the whole point of keeping one: "you sped
/// up here" is advice, "you sped up while saying this" is something you can act on.
public struct Utterance: Codable, Sendable, Identifiable {
    public var id: UUID
    public var speaker: Speaker
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    /// Snapshot of the numbers during this utterance.
    public var meanDbfs: Float
    public var syllableRate: Float

    public var duration: TimeInterval { end - start }
    public var wordCount: Int { text.split(separator: " ").count }
    /// Words per minute — the number people actually recognise about their pace.
    public var wpm: Double {
        duration > 0.5 ? Double(wordCount) / duration * 60 : 0
    }

    public init(id: UUID = UUID(), speaker: Speaker, start: TimeInterval,
                end: TimeInterval, text: String, meanDbfs: Float = 0,
                syllableRate: Float = 0) {
        self.id = id; self.speaker = speaker; self.start = start; self.end = end
        self.text = text; self.meanDbfs = meanDbfs; self.syllableRate = syllableRate
    }
}

/// Post-conversation analysis. Everything here is derived, not measured live —
/// it exists so the review screen has something to say beyond a list of buzzes.
public struct Insights: Codable, Sendable {
    public var talkShare: Float
    public var yourWPM: Double
    public var theirWPM: Double
    public var yourLongestTurn: TimeInterval
    public var interruptions: Int
    public var questionsAsked: Int
    public var longestMonologue: TimeInterval

    /// Plain-language findings, worst first. Deliberately blunt: a review screen
    /// that congratulates you is worthless.
    public var findings: [String] {
        var out: [String] = []
        if talkShare > 0.65 {
            out.append("You did \(Int(talkShare * 100))% of the talking. Anything past about 60% and the other person is being interviewed, not talked with.")
        } else if talkShare < 0.35 {
            out.append("You did only \(Int(talkShare * 100))% of the talking — worth knowing whether that was listening or withdrawing.")
        }
        if interruptions >= 3 {
            out.append("You started talking before they finished \(interruptions) times.")
        }
        if theirWPM > 0, yourWPM > theirWPM * 1.25 {
            out.append("You spoke at \(Int(yourWPM)) words per minute against their \(Int(theirWPM)). That gap is what reads as intensity.")
        }
        if longestMonologue > 90 {
            out.append("Your longest unbroken stretch was \(Int(longestMonologue)) seconds.")
        }
        if questionsAsked == 0 {
            out.append("You asked no questions. Questions are the cheapest way to hand the floor back.")
        } else if questionsAsked >= 5 {
            out.append("You asked \(questionsAsked) questions — that is the single strongest thing in this conversation.")
        }
        if out.isEmpty {
            out.append("Nothing stands out. Pace, volume and airtime all tracked the other person.")
        }
        return out
    }

    public init(talkShare: Float, yourWPM: Double, theirWPM: Double,
                yourLongestTurn: TimeInterval, interruptions: Int,
                questionsAsked: Int, longestMonologue: TimeInterval) {
        self.talkShare = talkShare; self.yourWPM = yourWPM; self.theirWPM = theirWPM
        self.yourLongestTurn = yourLongestTurn; self.interruptions = interruptions
        self.questionsAsked = questionsAsked; self.longestMonologue = longestMonologue
    }

    public static func derive(from utterances: [Utterance], turns: [Turn]) -> Insights {
        let mine = utterances.filter { $0.speaker == .me }
        let theirs = utterances.filter { $0.speaker == .them }

        func wpm(_ us: [Utterance]) -> Double {
            let words = us.reduce(0) { $0 + $1.wordCount }
            let secs = us.reduce(0.0) { $0 + $1.duration }
            return secs > 1 ? Double(words) / secs * 60 : 0
        }
        let myTime = mine.reduce(0.0) { $0 + $1.duration }
        let theirTime = theirs.reduce(0.0) { $0 + $1.duration }

        // A question mark is unreliable from a speech recogniser, so also count
        // the openers that actually carry a question in speech.
        let openers = ["what", "why", "how", "when", "where", "who", "do you",
                       "did you", "have you", "are you", "would you", "could you",
                       "is it", "was it", "tell me"]
        let questions = mine.filter { u in
            let t = u.text.lowercased()
            return t.contains("?") || openers.contains { t.hasPrefix($0) }
        }.count

        return Insights(
            talkShare: (myTime + theirTime) > 0 ? Float(myTime / (myTime + theirTime)) : 0.5,
            yourWPM: wpm(mine), theirWPM: wpm(theirs),
            yourLongestTurn: turns.filter { $0.speaker == .me }.map(\.duration).max() ?? 0,
            interruptions: turns.filter { $0.speaker == .me && $0.isInterruption }.count,
            questionsAsked: questions,
            longestMonologue: mine.map(\.duration).max() ?? 0
        )
    }
}
