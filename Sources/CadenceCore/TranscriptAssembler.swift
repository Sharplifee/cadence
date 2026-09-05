import Foundation

/// Turns a speech recogniser's rolling text plus the speaker gate's opinion into
/// attributed utterances.
///
/// This exists as its own testable type because the naive version had a fatal
/// bug: it sliced new text with `liveText.dropFirst(committed.count)`, which
/// works right up until the recogniser is restarted. `SFSpeechRecognizer` stops
/// after about a minute, so the app restarts it — the new task's text begins at
/// empty while `committed` still holds the previous minute, the slice returns
/// nothing forever, and transcription silently dies 50 seconds into every
/// conversation while continuing to look healthy.
public final class TranscriptAssembler {
    public private(set) var utterances: [Utterance] = []

    private var committedPrefix = ""
    private var openSpeaker: Speaker = .silence
    private var openStart: TimeInterval = 0
    private var levels: [Float] = []

    public init() {}

    public func reset() {
        utterances.removeAll()
        committedPrefix = ""
        openSpeaker = .silence
        levels = []
    }

    /// The recogniser was restarted, so its text begins again from empty.
    /// Anything not yet committed is lost either way; what must not happen is
    /// carrying the old prefix forward and slicing against it.
    public func recognizerRestarted(at t: TimeInterval, finalText: String) {
        commit(text: finalText, at: t)
        committedPrefix = ""
    }

    public func observe(speaker: Speaker, dbfs: Float, at t: TimeInterval) {
        if speaker != .silence {
            if openSpeaker == .silence {
                openSpeaker = speaker; openStart = t; levels = []
            }
            levels.append(dbfs)
        }
    }

    /// Called whenever the recogniser produces text. A change of speaker is what
    /// closes an utterance — the recogniser has no idea who is talking.
    public func update(text: String, speaker: Speaker, at t: TimeInterval) {
        guard speaker != .silence, openSpeaker != .silence else { return }
        if speaker != openSpeaker {
            commit(text: text, at: t)
            openSpeaker = speaker
            openStart = t
            levels = []
        }
    }

    public func finish(text: String, at t: TimeInterval) {
        commit(text: text, at: t)
    }

    private func commit(text: String, at t: TimeInterval) {
        let newText: String
        if text.hasPrefix(committedPrefix) {
            newText = String(text.dropFirst(committedPrefix.count))
        } else {
            // The recogniser revised earlier words, or restarted. Taking the
            // whole string beats silently emitting nothing.
            newText = text
        }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        committedPrefix = text

        guard openSpeaker != .silence, !trimmed.isEmpty, t > openStart else {
            openSpeaker = .silence
            return
        }
        let mean = levels.isEmpty ? 0 : levels.reduce(0, +) / Float(levels.count)
        utterances.append(Utterance(speaker: openSpeaker, start: openStart,
                                    end: t, text: trimmed, meanDbfs: mean))
        openSpeaker = .silence
        levels = []
    }
}
