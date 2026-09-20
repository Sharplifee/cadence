import CadenceCore
import EventKit
import Foundation

/// Writes accepted items to the calendar.
///
/// Only ever called for items you explicitly said yes to. Nothing here runs on
/// its own — an app that silently writes to your calendar gets deleted the
/// first time it is wrong.
@MainActor
public final class CalendarWriter {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async -> Bool {
        if #available(iOS 17, *) {
            return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
        return await withCheckedContinuation { c in
            store.requestAccess(to: .event) { ok, _ in c.resume(returning: ok) }
        }
    }

    public var isAuthorized: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17, *) { return s == .fullAccess || s == .writeOnly }
        return s == .authorized
    }

    /// Returns the created event identifier so the item can be marked and never
    /// written twice.
    public func add(_ item: ActionItem) throws -> String {
        guard let due = item.dueAt else {
            throw NSError(domain: "Cadence.Calendar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No date was found in that line."])
        }
        let event = EKEvent(eventStore: store)
        event.title = item.calendarTitle
        event.startDate = due
        event.endDate = due.addingTimeInterval(item.suggestedDuration)
        event.calendar = store.defaultCalendarForNewEvents
        event.timeZone = DatePhraseParser.timeZone
        // The source sentence and when it was heard, so three days later you
        // can tell what this actually was.
        event.notes = """
        \(item.text)

        Heard \(item.capturedAt.formatted(date: .abbreviated, time: .shortened)) by Looped.
        \(item.dateEvidence.map { "Date from: \($0)" } ?? "")
        """
        // A time nobody actually agreed gets no alarm — it would fire at a
        // moment that was never real.
        if item.hasExplicitTime {
            event.addAlarm(EKAlarm(relativeOffset: -900))
        }
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }
}
