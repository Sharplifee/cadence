import CadenceCore
import Foundation

/// Settings that vanish on relaunch are worse than no settings, because the
/// user believes they took effect.
public enum SettingsStore {
    private static let key = "cadence.cueSettings"

    public static func load() -> CueSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(CueSettings.self, from: data)
        else { return CueSettings() }
        return s
    }

    public static func save(_ s: CueSettings) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
