import CadenceCore
import Foundation

/// Local first. Audio never leaves the phone unless the session is explicitly
/// kept; metrics upload as JSON, which is a few kB per hour.
public final class SessionStore {
    private let fm = FileManager.default
    private lazy var root: URL = {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/Sessions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public init() {}

    /// Created up front so audio can stream into it while the session runs.
    public func directory(for id: UUID) -> URL {
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func audioURL(for id: UUID) -> URL? {
        let u = root.appendingPathComponent(id.uuidString).appendingPathComponent("audio.m4a")
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    public func delete(_ id: UUID) {
        try? fm.removeItem(at: root.appendingPathComponent(id.uuidString))
    }

    public func rename(_ id: UUID, to title: String) {
        guard var s = allSummaries().first(where: { $0.id == id }) else { return }
        s.title = title
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(s).write(to: root.appendingPathComponent(id.uuidString)
            .appendingPathComponent("summary.json"))
    }

    public func persist(summary: SessionSummary, frames: [Frame]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dir = root.appendingPathComponent(summary.id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? enc.encode(summary).write(to: dir.appendingPathComponent("summary.json"))
        try? enc.encode(frames).write(to: dir.appendingPathComponent("frames.json"))
        Task { await SyncClient.shared.upload(summary: summary, frames: frames) }
    }

    public func allSummaries() -> [SessionSummary] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("summary.json")) else { return nil }
            return try? dec.decode(SessionSummary.self, from: data)
        }.sorted { $0.startedAt > $1.startedAt }
    }
}
