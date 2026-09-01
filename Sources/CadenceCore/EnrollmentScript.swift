import Foundation

/// The enrollment read.
///
/// Two constraints shaped this text. It has to cover the sound range of normal
/// speech — every vowel, plosives, fricatives, nasals — because the profile is
/// built from what it hears, and reading a single flat sentence produces a
/// profile that only matches you when you are bored. And it has to be dull
/// enough to read at a natural pace: anything interesting makes people perform,
/// and a performed voice is not the voice the app has to recognise at dinner.
///
/// Timed at roughly 30 seconds spoken normally.
public enum EnrollmentScript {
    public static let targetDuration: TimeInterval = 30

    public static let lines: [String] = [
        "The quiet harbour filled with morning fog, and every boat sat waiting for the tide to turn.",
        "Judges vexed the lawyer by quizzing him about the exact phrasing of clause thirty-two.",
        "She packed five dozen jugs of liquid wax before the big truck arrived at eight.",
        "Numbers, names, and long winding sentences all sound different when you say them out loud.",
        "Keep going at your normal pace — there is no need to slow down or speak clearly for this.",
        "When the timer runs out, the app will know your voice well enough to pick it out of a room."
    ]

    /// Rough progress hint so the UI can highlight the line you should be on.
    public static func lineIndex(atFraction f: Double) -> Int {
        let i = Int(f * Double(lines.count))
        return min(max(i, 0), lines.count - 1)
    }
}
