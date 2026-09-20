import CadenceCore
import Foundation
import WatchConnectivity

/// Files from the Watch can arrive while the app is backgrounded or on any
/// screen, so the delegate has to be a long-lived singleton rather than
/// anything owned by a view.
public final class WatchFileBridge: NSObject, WCSessionDelegate {
    public static let shared = WatchFileBridge()

    public weak var receiver: ClipReceiver?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        if s.delegate == nil { s.delegate = self }
        s.activate()
    }

    public func session(_ s: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted as soon as this returns, so it must be moved now,
        // not after a hop to the main actor.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + file.fileURL.lastPathComponent)
        try? FileManager.default.moveItem(at: file.fileURL, to: staged)
        let metadata = file.metadata ?? [:]
        Task { @MainActor in
            self.receiver?.receive(file: staged, metadata: metadata)
        }
    }

    public func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    public func sessionDidBecomeInactive(_ s: WCSession) {}
    public func sessionDidDeactivate(_ s: WCSession) { s.activate() }
}
