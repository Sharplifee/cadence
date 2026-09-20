import AVFoundation
import Foundation
import Speech

/// Transcribes a finished audio file, as opposed to a live stream.
///
/// A recorded file uses `SFSpeechURLRecognitionRequest`, which has none of the
/// live recogniser's one-minute ceiling — the reason the live path has to be
/// restarted mid-conversation does not apply here.
public enum ClipTranscriber {
    public static func transcribe(_ url: URL) async throws -> (text: String, duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw NSError(domain: "Cadence.Clip", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognition is unavailable."])
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        // On-device only, same promise as everywhere else in the app.
        request.requiresOnDeviceRecognition = true
        if #available(iOS 16, *) { request.addsPunctuation = true }

        let text: String = try await withCheckedThrowingContinuation { c in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error, !resumed { resumed = true; c.resume(throwing: error); return }
                guard let result, result.isFinal, !resumed else { return }
                resumed = true
                c.resume(returning: result.bestTranscription.formattedString)
            }
        }
        return (text, duration)
    }
}
