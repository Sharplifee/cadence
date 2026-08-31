import Foundation

/// Adaptive energy + zero-crossing gate. The noise floor tracks the room so a
/// loud restaurant does not read as continuous speech.
public final class VoiceActivity {
    private var noiseFloor: Float = -55
    private let attack: Float = 0.25   // fast when it gets louder
    private let release: Float = 0.02  // slow when it gets quieter

    /// dB above the tracked floor before a frame counts as speech.
    public var margin: Float = 9

    public init() {}

    public func isSpeech(dbfs: Float, zcr: Float) -> Bool {
        // Track the floor only on quiet frames so speech does not raise it.
        if dbfs < noiseFloor + margin {
            let rate = dbfs > noiseFloor ? attack : release
            noiseFloor += (dbfs - noiseFloor) * rate
        }
        // Very high ZCR is fricative noise or handling noise, not voiced speech.
        let plausible = zcr < 0.45
        return dbfs > noiseFloor + margin && plausible
    }

    public var currentFloor: Float { noiseFloor }
}
