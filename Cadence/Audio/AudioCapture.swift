import AVFoundation
import CadenceCore
import Foundation

/// Continuous mic capture that does not interrupt whatever else is playing, and
/// that survives the things which actually happen during a long conversation.
public final class AudioCapture {
    public static let sampleRate: Double = 16_000
    public static let frameSeconds: Double = 0.5

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?

    // Read cursor instead of removeFirst: this runs on the audio thread, and
    // removeFirst is O(n) memmove on every buffer.
    private var pending = [Float]()
    private var readIndex = 0
    private let frameLength = Int(sampleRate * frameSeconds)

    /// Called on the audio thread. Keep it allocation-light.
    public var onFrame: (([Float]) -> Void)?
    /// Capture stopped for a reason outside our control, and whether it came back.
    public var onAvailabilityChange: ((Bool, String?) -> Void)?
    /// Other audio started or stopped playing out loud. Speaker playback IS in
    /// the recording; this exists so the timeline can say what it was.
    public var onOtherAudioChange: ((Bool) -> Void)?
    /// Headphones came or went. Everything routed to them is inaudible to the
    /// microphone, so this is what marks a genuine hole in the recording.
    public var onHeadphonesChange: ((Bool) -> Void)?

    public var headphonesConnected: Bool {
        let outs = session.currentRoute.outputs.map(\.portType)
        return outs.contains { [.headphones, .bluetoothA2DP, .bluetoothLE,
                                .bluetoothHFP, .airPlay].contains($0) }
    }
    public var otherAudioPlaying: Bool { session.isOtherAudioPlaying }

    public private(set) var isCapturing = false
    private var wantsCapture = false

    public var isOtherAudioPlaying: Bool { session.isOtherAudioPlaying }

    /// Where playback is going. The mic records the room, so speaker audio is
    /// already in the recording and AirPods audio never can be.
    public var routeKind: AudioRouteKind {
        switch session.currentRoute.outputs.first?.portType {
        case .some(.builtInSpeaker):                   return .speaker
        case .some(.builtInReceiver):                  return .receiver
        case .some(.headphones), .some(.usbAudio):     return .headphones
        case .some(.bluetoothA2DP), .some(.bluetoothLE), .some(.bluetoothHFP):
                                                       return .bluetooth
        case .some(.carAudio), .some(.airPlay), .some(.HDMI):
                                                       return .external
        default:                                       return .speaker
        }
    }

    public func start() throws {
        wantsCapture = true
        try startEngine()
    }

    private func startEngine() throws {
        guard !isCapturing else { return }

        // .mixWithOthers is the whole reason music keeps playing.
        // .allowBluetooth lets AirPods act as the near-field mic when present.
        //
        // .measurement is load-bearing, not incidental: it disables automatic
        // gain control. With AGC on, iOS normalises the two voices toward each
        // other, which erases the loudness difference the speaker gate and the
        // volume cue both depend on. Do not "fix" this to .default — it makes
        // alert tones louder and the app wrong.
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(Self.sampleRate)
        try session.setPreferredIOBufferDuration(0.05)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "Cadence.Audio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The microphone reported no input format."])
        }
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: Self.sampleRate,
                                      channels: 1, interleaved: false) else {
            throw NSError(domain: "Cadence.Audio", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not build the 16 kHz mono format."])
        }
        outFormat = out
        converter = AVAudioConverter(from: inFormat, to: out)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
            self?.ingest(buf)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
        onAvailabilityChange?(true, nil)
        onHeadphonesChange?(headphonesConnected)
        lastOtherAudio = session.isOtherAudioPlaying
        onOtherAudioChange?(lastOtherAudio)
    }

    public func stop() {
        wantsCapture = false
        teardown()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func teardown() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pending.removeAll(keepingCapacity: true)
        readIndex = 0
        isCapturing = false
    }

    // MARK: - Staying alive

    /// A phone call, Siri, or an alarm ends the audio session. Without this the
    /// engine stops for good, the UI keeps saying "listening", and the app is
    /// silently dead for the rest of the conversation.
    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            teardown()
            onAvailabilityChange?(false, "Paused — something else took the microphone.")
        case .ended:
            let opts = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if opts.contains(.shouldResume) { resume() }
            else { onAvailabilityChange?(false, "Paused — tap start to resume listening.") }
        @unknown default:
            break
        }
    }

    /// Plugging in or pulling out AirPods changes the input hardware, which
    /// invalidates the tap format. Rebuild rather than keep a dead tap.
    @objc private func handleRouteChange(_ note: Notification) {
        guard wantsCapture,
              let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override,
             .categoryChange, .routeConfigurationChange:
            onHeadphonesChange?(headphonesConnected)
            resume()
        default:
            break
        }
    }

    @objc private func handleEngineConfigChange(_ note: Notification) {
        guard wantsCapture else { return }
        resume()
    }

    private func resume() {
        guard wantsCapture else { return }
        teardown()
        // The route settles a beat after the notification; restarting instantly
        // reliably throws.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.wantsCapture, !self.isCapturing else { return }
            do { try self.startEngine() }
            catch {
                self.onAvailabilityChange?(false, "Microphone unavailable: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Frame assembly

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let outFormat else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ptr = out.floatChannelData?[0] else { return }

        // Cheap to poll here and there is no notification for it.
        let playing = session.isOtherAudioPlaying
        if playing != lastOtherAudio {
            lastOtherAudio = playing
            DispatchQueue.main.async { [weak self] in self?.onOtherAudioChange?(playing) }
        }

        pending.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(out.frameLength)))
        while pending.count - readIndex >= frameLength {
            onFrame?(Array(pending[readIndex..<(readIndex + frameLength)]))
            readIndex += frameLength
        }
        // Compact occasionally rather than shifting the array every frame.
        if readIndex > frameLength * 8 {
            pending.removeFirst(readIndex)
            readIndex = 0
        }
    }
}
