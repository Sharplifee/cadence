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
