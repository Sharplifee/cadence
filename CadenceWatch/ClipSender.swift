import CadenceCore
import Foundation
import WatchConnectivity

/// Ships frozen clips from the Watch to the phone.
///
/// `transferFile` rather than `sendMessageData`: it survives the phone being
/// asleep, out of range or the app being closed, queues on disk, and retries on
/// its own. A clip you marked walking to the car must not be lost because your
/// phone was in a pocket.
@MainActor
public final class ClipSender: NSObject, ObservableObject {
    @Published public private(set) var queued = 0
    @Published public private(set) var lastError: String?

    private let fm = FileManager.default

    public func send(clipDirectory dir: URL, clip: MarkedClip) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "m4a" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !files.isEmpty else {
            lastError = "Nothing to send — the clip had no audio."
            return
        }

        // Metadata rides with every file so the phone can reassemble the clip
        // without a second channel that could arrive first or not at all.
        for (i, url) in files.enumerated() {
            let meta: [String: Any] = [
                "clipID": clip.id.uuidString,
                "markedAt": clip.markedAt.timeIntervalSince1970,
                "lookback": clip.lookback,
                "note": clip.note ?? "",
                "index": i,
                "total": files.count
            ]
            session.transferFile(url, metadata: meta)
        }
        queued = session.outstandingFileTransfers.count
    }

    /// Delete the local copy only once the phone has it. Until then the Watch
    /// is the only place the audio exists.
    public func session(_ s: WCSession, didFinish transfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
            } else {
                try? self.fm.removeItem(at: transfer.file.fileURL)
            }
            self.queued = s.outstandingFileTransfers.count
        }
    }
}
