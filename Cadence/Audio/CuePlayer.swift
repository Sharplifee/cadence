import AVFoundation
import CadenceCore
import CoreHaptics
import Foundation
import UIKit

/// Plays a cue on the phone across every enabled channel, all driven by the
/// same CuePattern so the buzz, the beep and the torch blink land together and
/// read as one signal.
@MainActor
public final class CuePlayer {
    private var engine: CHHapticEngine?
    private var tonePlayer: AVAudioPlayer?

    public init() { prepareHaptics() }

    public func play(_ cue: CueCode, channels: Channels, tier: Int) {
        let pattern = CuePattern.pattern(for: cue)
        guard !pattern.pulses.isEmpty else { return }
        if channels.contains(.haptic) { playHaptic(pattern, tier: tier) }
        if channels.contains(.sound)  { playTone(pattern, tier: tier) }
        if channels.contains(.flash)  { playTorch(pattern) }
    }

    // MARK: - Haptics

    /// CoreHaptics rather than UINotificationFeedbackGenerator: the canned
    /// feedback styles cannot express a rhythm, and a rhythm is the entire
    /// vocabulary. Sharpness is raised with the tier so an escalated cue feels
    /// more urgent rather than merely louder.
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
    }

    private func playHaptic(_ pattern: CuePattern, tier: Int) {
        guard let engine else {
            // No haptic hardware — fall back rather than silently doing nothing.
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        let intensity = Float(min(0.75 + 0.125 * Double(tier - 1), 1.0))
        let sharpness = Float(min(0.45 + 0.25 * Double(tier - 1), 1.0))

        var events: [CHHapticEvent] = []
        for (at, on) in pattern.schedule {
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [.init(parameterID: .hapticIntensity, value: intensity),
                             .init(parameterID: .hapticSharpness, value: sharpness)],
                relativeTime: at, duration: on))
        }
        if let p = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: p) {
            try? engine.start()
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    // MARK: - Tone

    /// Synthesised rather than shipped as an audio file so the pitch can track
    /// the tier. Mixes with other audio and ducks nothing — this fires while
    /// you are mid-conversation, possibly with music playing.
    private func playTone(_ pattern: CuePattern, tier: Int) {
        let sr = 44_100.0
        let freq = 660.0 + 220.0 * Double(tier - 1)
        var samples = [Float]()
        for (at, on) in pattern.schedule {
            let startIdx = Int(at * sr)
            while samples.count < startIdx { samples.append(0) }
            let n = Int(on * sr)
            for i in 0..<n {
                let t = Double(i) / sr
                // Short attack/release envelope, or each pulse clicks.
                let env = min(min(t, on - t) / 0.008, 1.0)
                samples.append(Float(sin(2 * .pi * freq * t) * env * 0.35))
            }
        }
        guard !samples.isEmpty else { return }

        var data = Data()
        let bytes = samples.count * 2
        func append<T>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        data.append("RIFF".data(using: .ascii)!); append(UInt32(36 + bytes))
        data.append("WAVEfmt ".data(using: .ascii)!); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(sr))
        append(UInt32(sr) * 2); append(UInt16(2)); append(UInt16(16))
        data.append("data".data(using: .ascii)!); append(UInt32(bytes))
        for s in samples { append(Int16(max(-1, min(1, s)) * 32767)) }

        tonePlayer = try? AVAudioPlayer(data: data)
        tonePlayer?.volume = 1.0
        tonePlayer?.play()
    }

    // MARK: - Torch

    /// The rear torch blinks the same rhythm. Deliberately last in the ladder:
    /// it is the only channel other people in the room can notice.
    private func playTorch(_ pattern: CuePattern) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        for (at, on) in pattern.schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                try? device.lockForConfiguration()
                try? device.setTorchModeOn(level: 1.0)
                device.unlockForConfiguration()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + on) {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            }
        }
    }
}
