import AVFoundation
import CadenceCore
import Foundation
import WatchKit

/// The always-on loop, running on the wrist.
///
/// It lives on the Watch rather than the phone for one reason: the Watch has
/// its own audio session. That means you can record a voice memo, take a call,
/// or run any other audio app on the phone and none of it touches this loop.
/// On the phone the two would fight over the same session every time.
///
/// Nothing is kept by default. Audio rotates through short segments and the
/// oldest are deleted as they age out of the window, so the only audio that
/// ever survives is what you explicitly mark.
@MainActor
public final class WatchAmbientRecorder: NSObject, ObservableObject {
    @Published public private(set) var isLooping = false
    @Published public private(set) var bufferedSeconds: TimeInterval = 0
    @Published public private(set) var savedClips: Int = 0
    @Published public private(set) var lastError: String?

    /// How far back a mark reaches.
    public var lookback: TimeInterval = 120

    /// Length of each automatic recording. Five minutes by default; the loop
    /// closes one file and opens the next with only the gap it takes to do it.
    public var segmentMinutes: Int {
        get { UserDefaults.standard.object(forKey: "loopMinutes") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "loopMinutes") }
    }

    /// Every completed segment is sent for transcription, not just marked ones.
    /// The point is that you never have to decide to capture something.
    public var autoSendEverySegment: Bool {
        get { UserDefaults.standard.object(forKey: "loopAutoSend") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "loopAutoSend") }
    }

    @Published public private(set) var segmentsSent = 0
    @Published public private(set) var currentSegmentElapsed: TimeInterval = 0

    private var buffer = RollingBuffer(window: 600, segmentLength: 30)
    private let sender = ClipSender()
    private var recorder: AVAudioRecorder?
    private var rotateTimer: Timer?
    private var tickTimer: Timer?
    private var segmentStartedAt: Date?
    private var startedAt = Date()

    private let fm = FileManager.default
    private lazy var loopDir: URL = {
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("loop", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private lazy var savedDir: URL = {
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("marks", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    public override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: - Control

    public func startLoop() {
        guard !isLooping else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // .record, not .playAndRecord: the loop only captures, so asking
            // for a duplex route would push Bluetooth to HFP for nothing.
            // .mixWithOthers so it never stops anything else, and never gets
            // stopped by it.
            try s.setCategory(.record, mode: .default,
                              options: [.mixWithOthers, .overrideMutedMicrophoneInterruption])
            try s.setActive(true)
            startedAt = Date()
            buffer.reset()
            clearLoopDir()
            buffer = RollingBuffer(window: TimeInterval(segmentMinutes) * 60 * 2,
                                   segmentLength: TimeInterval(segmentMinutes) * 60)
            try openSegment()
            segmentStartedAt = Date()
            rotateTimer = Timer.scheduledTimer(withTimeInterval: buffer.segmentLength,
                                               repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rotate() }
            }
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let s = self.segmentStartedAt else { return }
                    self.currentSegmentElapsed = Date().timeIntervalSince(s)
                }
            }
            isLooping = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func stopLoop() {
        rotateTimer?.invalidate(); rotateTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        // Send the partial segment rather than throw away what it captured.
        if autoSendEverySegment { rotate(sendOnly: true) }
        segmentStartedAt = nil; currentSegmentElapsed = 0
        recorder?.stop(); recorder = nil
        isLooping = false
        bufferedSeconds = 0
        clearLoopDir()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Freeze the last `lookback` seconds. This is the only path by which audio
    /// survives — everything else is deleted as it ages out.
    @discardableResult
    public func markMoment(note: String? = nil) -> URL? {
        guard isLooping else { return nil }
        // Close the open segment first, or the most recent — and most relevant
        // — audio is still buffered and never lands in the clip.
        rotate()

        let now = Date().timeIntervalSince(startedAt)
        let wanted = buffer.segments(coveringLast: lookback, endingAt: now)
        guard !wanted.isEmpty else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = savedDir.appendingPathComponent("mark-\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)

        for seg in wanted {
            let src = loopDir.appendingPathComponent(seg.filename)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.copyItem(at: src, to: dest.appendingPathComponent(seg.filename))
        }
        if let note, let data = note.data(using: .utf8) {
            try? data.write(to: dest.appendingPathComponent("note.txt"))
        }
        savedClips += 1
        WKInterfaceDevice.current().play(.success)

        // Hand it to the phone immediately. The watch is the only place this
        // audio exists until the transfer completes, so nothing is deleted here.
        let clip = MarkedClip(markedAt: Date(), lookback: lookback,
                              stage: .sending, note: note,
                              segments: wanted.map(\.filename))
        sender.send(clipDirectory: dest, clip: clip)
        return dest
    }

    public func savedMarks() -> [URL] {
        ((try? fm.contentsOfDirectory(at: savedDir, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - Segments

    private func openSegment() throws {
        let name = "seg-\(buffer.segments.count + savedClips)-\(UUID().uuidString.prefix(4)).m4a"
        // 16 kHz mono AAC: roughly 4 MB an hour, so a ten-minute window costs
        // well under a megabyte on a device with very little room to spare.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]
        let r = try AVAudioRecorder(url: loopDir.appendingPathComponent(name), settings: settings)
        r.delegate = self
        r.record()
        recorder = r
        currentFilename = name
    }

    private var currentFilename = ""

    /// Close the current file and immediately open the next. The gap is the
    /// time it takes to do exactly that — no processing happens in between,
    /// because anything slow here becomes a hole in the recording.
    private func rotate(sendOnly: Bool = false) {
        guard isLooping || recorder != nil else { return }
        recorder?.stop()
        let closed = currentFilename
        let elapsed = Date().timeIntervalSince(startedAt)

        // Reopen FIRST so the microphone is live again before anything else.
        if !sendOnly {
            do { try openSegment(); segmentStartedAt = Date(); currentSegmentElapsed = 0 }
            catch { lastError = error.localizedDescription; isLooping = false }
        }

        let expired = buffer.rotate(at: elapsed)
        if var last = buffer.segments.last {
            last.filename = closed
            buffer.replaceLast(with: last)
        }
        bufferedSeconds = buffer.coveredDuration

        if autoSendEverySegment, !closed.isEmpty {
            let url = loopDir.appendingPathComponent(closed)
            if fm.fileExists(atPath: url.path) {
                sender.sendSegment(url,
                                   capturedAt: Date().addingTimeInterval(-buffer.segmentLength),
                                   length: buffer.segmentLength)
                segmentsSent += 1
            }
        } else {
            // Not auto-sending: fall back to the rolling window and delete old
            // audio so the watch does not fill up.
            for e in expired {
                try? fm.removeItem(at: loopDir.appendingPathComponent(e.filename))
            }
        }
    }

    private func clearLoopDir() {
        for f in (try? fm.contentsOfDirectory(at: loopDir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: f)
        }
    }

    // MARK: - Staying alive

    /// A call or Siri on the Watch ends the session. The loop is worthless if it
    /// quietly stops, so it restarts itself the moment the interruption lifts.
    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                self.recorder?.stop()
                self.lastError = "Loop paused — something else took the microphone."
            case .ended:
                guard self.isLooping else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                do { try self.openSegment(); self.lastError = nil }
                catch { self.lastError = error.localizedDescription }
            @unknown default: break
            }
        }
    }
}

extension WatchAmbientRecorder: AVAudioRecorderDelegate {
    nonisolated public func audioRecorderEncodeErrorDidOccur(_ r: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.lastError = error?.localizedDescription }
    }
}
