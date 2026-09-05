import CadenceCore
import Foundation

/// The voice profile has to outlive the process. Without this, onboarding is
/// recorded as complete while the profile it produced is gone, so the app
/// launches into a state where every attempt to start a conversation fails and
/// the only way out is a settings screen the user has no reason to visit.
public enum VoiceProfileStore {
    private static let key = "cadence.voiceProfile"

    public static func load() -> VoiceProfile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VoiceProfile.self, from: data)
    }

    public static func save(_ p: VoiceProfile) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
