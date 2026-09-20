import Foundation

/// Decides whether the phone is allowed to record right now.
///
/// The hard fact, from Apple's own routing rules: **any active audio input
/// forces Bluetooth off A2DP and onto HFP** — mono, low bandwidth, the
/// "sounds like a phone call" downgrade. That happens even when the app asks
/// for the built-in microphone and even with allowBluetoothA2DP set. It is not
/// a bug to configure around; it is how the Bluetooth profiles work.
///
/// So the phone must simply not record while playback is routed anywhere that
/// would be wrecked by it. The watch has an entirely separate audio session and
/// does not touch the phone's route, so it covers those stretches instead.
public enum AudioPolicy {
    /// Output routes where starting a recording would audibly degrade playback.
    public static func degradesPlayback(_ route: AudioRouteKind) -> Bool {
        switch route {
        case .bluetooth:          return true   // A2DP collapses to HFP
        case .external:           return true   // CarPlay and AirPlay likewise
        case .speaker, .receiver: return false
        case .headphones:         return false  // wired keeps full quality
        }
    }

    public enum Decision: Equatable {
        case record
        case deferToWatch(reason: String)

        public var shouldRecord: Bool { self == .record }
        public var reason: String? {
            if case .deferToWatch(let r) = self { return r }
            return nil
        }
    }

    /// `enabled` is the user's switch; the rest is what is actually happening.
    public static func decide(enabled: Bool,
                              route: AudioRouteKind,
                              otherAudioPlaying: Bool) -> Decision {
        guard enabled else {
            return .deferToWatch(reason: "Phone recording is off — watch is covering.")
        }
        // Only a problem when something is actually playing. Recording over
        // idle Bluetooth bothers nobody.
        if otherAudioPlaying, degradesPlayback(route) {
            return .deferToWatch(
                reason: "Playing through \(route.label) — phone stays off so your audio keeps full quality. Watch is covering.")
        }
        return .record
    }
}
