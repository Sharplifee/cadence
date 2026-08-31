import AVFoundation
import Foundation

/// Continuous mic capture that does not interrupt whatever else is playing.
/// 16 kHz mono is enough for every feature we extract and a quarter of the battery.
public final class AudioCapture {
    public static let sampleRate: Double = 16_000
    public static let frameSeconds: Double = 0.5

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var converter: AVAudioConverter?
    private var pending = [Float]()
    private let frameLength = Int(sampleRate * frameSeconds)

    /// Called on the audio thread. Keep it allocation-free.
    public var onFrame: (([Float]) -> Void)?

    public init() {}

    public func start() throws {
        // .mixWithOthers is the whole reason music keeps playing.
        // .allowBluetooth lets AirPods act as the near-field mic when present.
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(Self.sampleRate)
        try session.setPreferredIOBufferDuration(0.05)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Self.sampleRate,
                                            channels: 1,
                                            interleaved: false) else {
            throw NSError(domain: "Cadence.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "could not build 16k mono format"])
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
            self?.ingest(buf, to: outFormat)
        }

        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        pending.removeAll(keepingCapacity: true)
    }

    private func ingest(_ buffer: AVAudioPCMBuffer, to outFormat: AVAudioFormat) {
        guard let converter else { return }
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

        pending.append(contentsOf: UnsafeBufferPointer(start: ptr, count: Int(out.frameLength)))
        while pending.count >= frameLength {
            let chunk = Array(pending[0..<frameLength])
            pending.removeFirst(frameLength)
            onFrame?(chunk)
        }
    }
}
