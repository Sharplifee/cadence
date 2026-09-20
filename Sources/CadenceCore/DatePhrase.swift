import Foundation

/// Turns "Friday at 3" into an actual date.
///
/// This is the part that decides whether the calendar feature is useful or
/// infuriating, so it is pure, testable, and deliberately conservative: it
/// returns nil rather than guess. A wrong calendar entry is worse than none,
/// because you stop trusting the list and then you stop reading it.
///
/// All arithmetic runs in America/Denver. UTC date maths where the day matters
/// is a bug — "Friday" at 6pm Mountain is already Saturday in UTC.
public struct DatePhrase: Equatable, Sendable {
    public var date: Date
    /// False when only a day was found, so the UI can show "Friday" rather than
    /// pretending 9:00 was agreed.
    public var hasExplicitTime: Bool
    /// The words that produced it, so the user can see why.
    public var matched: String

    public init(date: Date, hasExplicitTime: Bool, matched: String) {
        self.date = date; self.hasExplicitTime = hasExplicitTime; self.matched = matched
    }
}

public enum DatePhraseParser {
    public static var timeZone = TimeZone(identifier: "America/Denver") ?? .current

    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]

    /// Named times people actually say. Each is a default hour, not a claim
    /// that an exact time was agreed.
    private static let namedTimes: [(String, Int, Bool)] = [
        ("first thing", 8, false), ("end of day", 17, false), ("end of week", 17, false),
        ("noon", 12, true), ("midday", 12, true), ("tonight", 19, false),
        ("this morning", 9, false), ("in the morning", 9, false), ("morning", 9, false),
        ("this afternoon", 14, false), ("afternoon", 14, false),
        ("this evening", 18, false), ("evening", 18, false)
    ]

    public static func parse(_ text: String, now: Date = Date()) -> DatePhrase? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let t = " " + text.lowercased() + " "

        var day: Date?
        var matched = ""

        // Day first, because a time with no day is almost always today or
        // tomorrow and we should not invent a week.
        if t.contains(" tomorrow") {
            day = cal.date(byAdding: .day, value: 1, to: now); matched = "tomorrow"
        } else if t.contains(" today") || t.contains(" tonight") {
            day = now; matched = t.contains(" tonight") ? "tonight" : "today"
        } else {
            for (name, weekday) in weekdays where t.contains(" " + name) {
                let wantsNextWeek = t.contains("next " + name) || t.contains(" next week")
                day = nextOccurrence(of: weekday, after: now, skipAWeek: wantsNextWeek, cal: cal)
                matched = wantsNextWeek ? "next \(name)" : name
                break
            }
        }

        // Time.
        var hour: Int?
        var minute = 0
        var explicit = false

        if let clock = clockTime(in: t) {
            hour = clock.hour; minute = clock.minute; explicit = true
            matched = matched.isEmpty ? clock.matched : "\(matched) at \(clock.matched)"
        } else {
            for (name, h, exact) in namedTimes where t.contains(name) {
                hour = h; explicit = exact
                matched = matched.isEmpty ? name : (matched == name ? name : "\(matched) \(name)")
                break
            }
        }

        guard day != nil || hour != nil else { return nil }

        // A time with no day means the next time that hour comes around.
        var base = day ?? now
        if day == nil, let h = hour {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = h; comps.minute = minute
            if let candidate = cal.date(from: comps), candidate <= now {
                base = cal.date(byAdding: .day, value: 1, to: now) ?? now
                matched = matched.isEmpty ? matched : "tomorrow \(matched)"
            }
        }

        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour ?? 9
        comps.minute = minute
        guard let result = cal.date(from: comps) else { return nil }
        return DatePhrase(date: result, hasExplicitTime: explicit, matched: matched)
    }

    private static func nextOccurrence(of weekday: Int, after now: Date,
                                       skipAWeek: Bool, cal: Calendar) -> Date? {
        let today = cal.component(.weekday, from: now)
        var delta = (weekday - today + 7) % 7
        // "Friday" said on Friday means next Friday, not five minutes ago.
        if delta == 0 { delta = 7 }
        if skipAWeek { delta += 7 }
        return cal.date(byAdding: .day, value: delta, to: now)
    }

    /// Finds "3pm", "3:30", "at 9", "10 o'clock".
    private static func clockTime(in t: String) -> (hour: Int, minute: Int, matched: String)? {
        let pattern = #"(?:\bat\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|o'clock)?\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = t as NSString

        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            guard let h = Int(ns.substring(with: m.range(at: 1))) else { continue }
            let minute = m.range(at: 2).location == NSNotFound ? 0
                       : Int(ns.substring(with: m.range(at: 2))) ?? 0
            let suffix = m.range(at: 3).location == NSNotFound ? ""
                       : ns.substring(with: m.range(at: 3))

            // A bare number with no am/pm and no "at" is a quantity, not a time.
            let whole = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            let anchored = whole.hasPrefix("at ") || !suffix.isEmpty || minute != 0
            guard anchored, h >= 1, h <= 24, minute < 60 else { continue }

            var hour = h
            if suffix == "pm", h < 12 { hour += 12 }
            if suffix == "am", h == 12 { hour = 0 }
            // No suffix: assume waking hours. "at 3" means the afternoon.
            if suffix.isEmpty || suffix == "o'clock", h >= 1, h <= 7 { hour = h + 12 }
            guard hour < 24 else { continue }
            return (hour, minute, whole)
        }
        return nil
    }
}
