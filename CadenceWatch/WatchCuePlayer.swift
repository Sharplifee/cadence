import AVFoundation
import CadenceCore
import Foundation
import SwiftUI
import WatchKit

/// Plays a cue on the wrist across every enabled channel, from the same
/// CuePattern the phone uses, so both devices pulse the identical rhythm at the
/// same moment.
@MainActor
public final class WatchCuePlayer: ObservableObject {
    /// Drives the full-screen white flash. The watch has no torch, so the
    /// display is the light — and under a cuff it is genuinely visible.
    @Published public var flashOn = false

    private var player: AVAudioPlayer?

    public init() {}

    public func play(_ cue: CueCode, channels: Channels, tier: Int) {
        let pattern = CuePattern.pattern(for: cue)
        guard !pattern.pulses.isEmpty else { return }
        if channels.contains(.haptic) { playHaptic(pattern, tier: tier) }
        if channels.contains(.sound)  { playTone(pattern, tier: tier) }
        if channels.contains(.flash)  { playFlash(pattern) }
    }

    /// watchOS exposes a fixed palette rather than arbitrary waveforms, so the
    /// rhythm carries the meaning and the type carries the urgency.
    private func playHaptic(_ pattern: CuePattern, tier: Int) {
        let type: WKHapticType = tier >= 3 ? .failure : (tier == 2 ? .notification : .click)
        let device = WKInterfaceDevice.current()
        for (at, _) in pattern.schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { device.play(type) }
        }
    }

    private func playTone(_ pattern: CuePattern, tier: Int) {
        let sr = 44_100.0
        let freq = 660.0 + 220.0 * Double(tier - 1)
        var samples = [Float]()
        for (at, on) in pattern.schedule {
            while samples.count < Int(at * sr) { samples.append(0) }
            let n = Int(on * sr)
            for i in 0..<n {
                let t = Double(i) / sr
                let env = min(min(t, on - t) / 0.008, 1.0)
                samples.append(Float(sin(2 * .pi * freq * t) * env * 0.4))
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

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.volume = 1.0
        player?.play()
    }

    private func playFlash(_ pattern: CuePattern) {
        for (at, on) in pattern.schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.flashOn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + on) { self.flashOn = false }
        }
    }
}
