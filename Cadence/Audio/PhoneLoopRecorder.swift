import AVFoundation
import CadenceCore
import Foundation
import UIKit

/// The phone half of dual capture.
///
/// The phone has the better microphone, so its audio is preferred wherever it
/// exists. It also loses the session constantly — every call, voice memo and
/// other recorder takes the mic — and after a call ends, a backgrounded app
/// frequently cannot reactivate its session at all until it is foregrounded.
/// That is a documented iOS behaviour, not something to engineer around.
///
/// So this recorder is built to fail gracefully and often: it records what it
/// can, records honestly when it could not, and lets the watch cover the rest.
@MainActor
public final class PhoneLoopRecorder: NSObject, ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var runs: [CaptureRun] = []
    @Published public private(set) var interrupted = false
    @Published public private(set) var lastMessage: String?

    public var segmentMinutes: Int {
        UserDefaults.standard.object(forKey: "loopMinutes") as? Int ?? 5
    }

    private let session = AVAudioSession.sharedInstance()
    private var recorder: AVAudioRecorder?
    private var rotateTimer: Timer?
    private var retryTimer: Timer?
    private var currentStart: Date?
    private var currentName = ""
    private var wantsRecording = false

    private let fm = FileManager.default
    private lazy var dir: URL = {
        let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/PhoneLoop", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    public override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(interruption),
                       name: AVAudioSession.interruptionNotification, object: session)
        nc.addObserver(self, selector: #selector(foregrounded),
                       name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Control

    public func start() {
        wantsRecording = true
        attemptStart()
        // The phone will lose the mic repeatedly. Rather than give up on the
        // first failure, keep trying quietly — the watch is covering meanwhile.
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.wantsRecording, !self.isRecording else { return }
                self.attemptStart()
            }
        }
    }

    public func stop() {
        wantsRecording = false
        retryTimer?.invalidate(); retryTimer = nil
        rotateTimer?.invalidate(); rotateTimer = nil
        closeCurrentRun()
        recorder?.stop(); recorder = nil
        isRecording = false
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func attemptStart() {
        guard wantsRecording, !isRecording else { return }
        do {
            // .mixWithOthers so the loop never stops your music or a video, and
            // .measurement for the same reason the coaching path uses it.
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            try openFile()
            rotateTimer?.invalidate()
            rotateTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(segmentMinutes) * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rotate() }
            }
            isRecording = true
            interrupted = false
            lastMessage = nil
        } catch {
            // Expected and routine. The watch has this minute.
            isRecording = false
            lastMessage = "Phone mic busy — watch is covering."
        }
    }

    // MARK: - Files

    private func openFile() throws {
        let name = "phone-\(Int(Date().timeIntervalSince1970)).m4a"
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]
        let r = try AVAudioRecorder(url: dir.appendingPathComponent(name), settings: settings)
        r.record()
        recorder = r
        currentName = name
        currentStart = Date()
    }

    /// Records what this run actually covered. The merger works from real
    /// start and end times, so a run cut short by a call must be recorded as
    /// short — claiming the full five minutes would hide the hole the watch
    /// needs to fill.
    private func closeCurrentRun() {
        guard let start = currentStart, !currentName.isEmpty else { return }
        let end = Date()
        if end.timeIntervalSince(start) >= 2 {
            runs.append(CaptureRun(source: .phone, start: start, end: end,
                                   filename: currentName))
        } else {
            try? fm.removeItem(at: dir.appendingPathComponent(currentName))
        }
        currentStart = nil
        currentName = ""
    }

    private func rotate() {
        recorder?.stop()
        closeCurrentRun()
        do { try openFile() }
        catch {
            isRecording = false
            lastMessage = "Phone mic busy — watch is covering."
        }
    }

    public func fileURL(_ name: String) -> URL { dir.appendingPathComponent(name) }

    public func clearRuns() { runs.removeAll() }

    // MARK: - Losing and regaining the mic

    @objc private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                self.recorder?.stop()
                self.closeCurrentRun()
                self.isRecording = false
                self.interrupted = true
                self.lastMessage = "Phone mic taken by another app — watch is covering."
            case .ended:
                // Reactivation from the background reliably fails after a call.
                // Trying anyway costs nothing; the retry timer and the
                // foreground hook are what actually recover it.
                self.attemptStart()
            @unknown default: break
            }
        }
    }

    /// The documented recovery path: reopening the app is often the only thing
    /// that lets the session reactivate after a call.
    @objc private func foregrounded() {
        Task { @MainActor in
            guard self.wantsRecording, !self.isRecording else { return }
            self.attemptStart()
        }
    }
}
