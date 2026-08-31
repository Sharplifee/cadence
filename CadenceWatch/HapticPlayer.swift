import CadenceCore
import Foundation
import WatchKit

/// watchOS gives you a fixed palette, so the vocabulary is built out of timing.
/// Each pattern must be distinguishable through a sleeve, without looking.
public enum HapticPlayer {
    public static func play(_ cue: CueCode) {
        switch cue {
        case .slowDown:        sequence([.click, .click], gap: 0.28)
        case .lowerVolume:     sequence([.directionDown], gap: 0)
        case .yieldFloor:      sequence([.click, .click, .click], gap: 0.12)
        case .stopOverlapping: sequence([.retry, .retry], gap: 0.09)
        case .metronomeTick:   sequence([.click], gap: 0)
        case .sessionStart:    sequence([.start], gap: 0)
        case .sessionEnd:      sequence([.stop], gap: 0)
        case .none:            break
        }
    }

    private static func sequence(_ types: [WKHapticType], gap: TimeInterval) {
        let device = WKInterfaceDevice.current()
        for (i, type) in types.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + gap * Double(i)) {
                device.play(type)
            }
        }
    }
}
