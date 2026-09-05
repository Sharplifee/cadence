import Foundation

/// The per-frame DSP, isolated from any actor so it can run off the main thread.
///
/// This is not a style choice. `fundamental` alone is a normalised
/// autocorrelation over 8,000 samples across ~200 lags — roughly two million
/// multiply-accumulates every 500 ms. Running that on the main actor, which is
/// what the first version did, competes directly with SwiftUI for the exact
/// window in which the ring and level meter are animating.
public struct FrameAnalyzer: Sendable {
    public let sampleRate: Float

    public init(sampleRate: Float) { self.sampleRate = sampleRate }

    public struct Result: Sendable {
        public var dbfs: Float
        public var zcr: Float
        public var f0: Float
        public var centroid: Float
        public var syllableRate: Float
        public var isSpeech: Bool
    }

    /// `vad` is passed in rather than owned because its noise floor is stateful
    /// and must persist across frames.
    public func analyze(_ samples: [Float], vad: VoiceActivity) -> Result {
        let dbfs = DSP.rmsDBFS(samples)
        let zcr = DSP.zeroCrossingRate(samples)
        let speech = vad.isSpeech(dbfs: dbfs, zcr: zcr)

        // Everything below is only meaningful for voiced audio, and skipping it
        // on silence is most of the CPU saving in a real conversation.
        guard speech else {
            return Result(dbfs: dbfs, zcr: zcr, f0: 0, centroid: 0,
                          syllableRate: 0, isSpeech: false)
        }
        return Result(
            dbfs: dbfs, zcr: zcr,
            f0: DSP.fundamental(samples, sampleRate: sampleRate),
            centroid: DSP.spectralCentroid(samples, sampleRate: sampleRate),
            syllableRate: DSP.syllableRate(samples, sampleRate: sampleRate),
            isSpeech: true
        )
    }
}
