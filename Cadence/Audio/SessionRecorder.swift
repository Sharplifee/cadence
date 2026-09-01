import AVFoundation
import Foundation

/// Writes the conversation to disk so it can be played back at review time.
///
/// Compressed AAC at 16 kHz mono: about 4 MB an hour, which makes keeping a
/// month of conversations a non-decision. The file never leaves the phone.
public final class SessionRecorder {
    private var file: AVAudioFile?
    private let format: AVAudioFormat?

    public private(set) var url: URL?

    public init() {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: 16_000, channels: 1, interleaved: false)
    }

    public func start(sessionID: UUID, in directory: URL) {
        let dest = directory.appendingPathComponent("audio.m4a")
        url = dest
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        file = try? AVAudioFile(forWriting: dest, settings: settings)
    }

    public func append(_ samples: [Float]) {
        guard let file, let format,
              let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }
        try? file.write(from: buf)
    }

    public func finish() -> Bool {
        let ok = file != nil
        file = nil
        return ok
    }
}
