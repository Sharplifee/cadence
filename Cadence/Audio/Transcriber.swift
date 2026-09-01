import CadenceCore
import Foundation
import Speech

/// On-device speech recognition, fed the same audio the analysis engine sees.
///
/// `requiresOnDeviceRecognition` is not optional here. Server recognition would
/// ship every private conversation to Apple, which contradicts the one promise
/// this app makes, and it stops working the moment signal drops.
@MainActor
public final class Transcriber {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Emitted whenever the recogniser settles on more text.
    public var onPartial: ((String) -> Void)?

    public private(set) var isRunning = false
    public private(set) var lastError: String?

    public var isAvailable: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { status in
                c.resume(returning: status == .authorized)
            }
        }
    }

    public func start() {
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition is unavailable on this device."
            return
        }
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.requiresOnDeviceRecognition = true
        r.taskHint = .dictation
        if #available(iOS 16, *) { r.addsPunctuation = true }
        request = r
        isRunning = true

        task = recognizer.recognitionTask(with: r) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.onPartial?(result.bestTranscription.formattedString)
                }
                if let error {
                    self.lastError = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    /// Called from the audio tap with the same PCM the analysis engine gets.
    public func append(_ samples: [Float], sampleRate: Double) {
        guard isRunning, let request,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate, channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }
        request.append(buffer)
    }

    /// The recogniser has a hard ~60 s ceiling per task, so a long conversation
    /// has to be restarted periodically or transcription silently stops partway.
    public func restart() {
        stop()
        start()
    }

    public func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isRunning = false
    }
}
