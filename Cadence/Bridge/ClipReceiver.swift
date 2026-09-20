import CadenceCore
import Foundation
import WatchConnectivity

/// Receives clips from the Watch, stores them, and runs them through the same
/// recogniser and extractor the coached sessions use.
///
/// The phone is where a clip becomes useful: it has the speech recogniser, the
/// storage and the screen. The Watch only has the microphone and the buffer.
@MainActor
public final class ClipReceiver: ObservableObject {
    @Published public private(set) var library = ClipLibrary()
    @Published public private(set) var queue = ActionQueue()
    @Published public private(set) var processing = false

    private let fm = FileManager.default
    private lazy var root: URL = {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/Clips", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var queueURL: URL { root.appendingPathComponent("queue.json") }

    public init() { load() }

    // MARK: - Arrival

    public func receive(file: URL, metadata: [String: Any]) {
        guard let idString = metadata["clipID"] as? String,
              let id = UUID(uuidString: idString) else { return }

        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(file.lastPathComponent)
        try? fm.removeItem(at: dest)
        try? fm.moveItem(at: file, to: dest)

        var clip = library.clips.first(where: { $0.id == id })
            ?? MarkedClip(id: id,
                          markedAt: Date(timeIntervalSince1970:
                                          metadata["markedAt"] as? TimeInterval ?? Date().timeIntervalSince1970),
                          lookback: metadata["lookback"] as? TimeInterval ?? 120)
        if let n = metadata["note"] as? String, !n.isEmpty { clip.note = n }
        if !clip.segments.contains(dest.lastPathComponent) {
            clip.segments.append(dest.lastPathComponent)
            clip.segments.sort()
        }

        // Only transcribe once every segment has landed, or the transcript is
        // built from a clip with holes in it.
        let total = metadata["total"] as? Int ?? clip.segments.count
        clip.stage = clip.segments.count >= total ? .arrived : .sending
        library.upsert(clip)
        save()

        if clip.stage == .arrived { Task { await process(clip.id) } }
    }

    // MARK: - Processing

    public func process(_ id: UUID) async {
        guard var clip = library.clips.first(where: { $0.id == id }) else { return }
        processing = true
        defer { processing = false }

        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        var utterances: [Utterance] = []
        var offset: TimeInterval = 0
        var failure: String?

        for name in clip.segments {
            let url = dir.appendingPathComponent(name)
            do {
                let (text, duration) = try await ClipTranscriber.transcribe(url)
                if !text.isEmpty {
                    // The loop cannot tell who is speaking — the speaker gate
                    // needs the near-field comparison and the Watch is worn by
                    // one person. Attribute to .me and be honest about it
                    // rather than invent a separation that was never measured.
                    utterances.append(Utterance(speaker: .me, start: offset,
                                                end: offset + duration, text: text))
                }
                offset += duration
            } catch {
                failure = error.localizedDescription
            }
        }

        if utterances.isEmpty, let failure {
            clip.stage = .failed
            clip.errorMessage = failure
        } else {
            clip.transcript = utterances.map(\.text).joined(separator: " ")
            clip.commitments = CommitmentExtractor.extract(from: utterances)
            clip.stage = .processed
            clip.errorMessage = nil
            // Everything the loop finds becomes a proposal you can accept or
            // dismiss. Nothing is written anywhere on its own.
            queue.add(ActionExtractor.items(from: utterances, capturedAt: clip.markedAt))
        }
        library.upsert(clip)
        save()
    }

    /// Retry a clip that failed. The audio is still on disk, so this costs
    /// nothing but time.
    public func retry(_ id: UUID) async { await process(id) }

    public func audioURLs(for clip: MarkedClip) -> [URL] {
        let dir = root.appendingPathComponent(clip.id.uuidString, isDirectory: true)
        return clip.segments.map { dir.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    public func setAccepted(_ id: UUID, _ value: Bool?) { queue.setAccepted(id, value); save() }
    public func markOnCalendar(_ id: UUID, eventID: String) { queue.markOnCalendar(id, eventID: eventID); save() }
    public func removeItem(_ id: UUID) { queue.remove(id); save() }

    public func delete(_ id: UUID) {
        try? fm.removeItem(at: root.appendingPathComponent(id.uuidString))
        library.remove(id)
        save()
    }

    // MARK: - Persistence

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let libData = try? enc.encode(library),
              let queueData = try? enc.encode(queue) else { return }
        let qURL = queueURL
        DispatchQueue.global(qos: .utility).async { [indexURL] in
            try? libData.write(to: indexURL)
            try? queueData.write(to: qURL)
        }
    }

    private func load() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: indexURL),
           let lib = try? dec.decode(ClipLibrary.self, from: data) { library = lib }
        if let data = try? Data(contentsOf: queueURL),
           let q = try? dec.decode(ActionQueue.self, from: data) { queue = q }
    }
}
