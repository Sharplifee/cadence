import CadenceCore
import SwiftUI

/// Sensitivity is one dial because nobody can reason about "interruptions per
/// minute". Delivery is explicit because being buzzed, beeped at or flashed in
/// company are completely different social risks and only you can price them.
struct SettingsView: View {
    @EnvironmentObject var controller: SessionController
    @AppStorage("sensitivity") private var sensitivity: Double = 0.5
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage("hasEnrolled") private var hasEnrolled = true

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        sensitivityCard
                        devicesCard
                        channelsCard
                        escalationCard
                        previewCard
                        privacyCard
                        profileCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var sensitivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sensitivity").font(.subheadline.weight(.medium))
                Slider(value: $sensitivity, in: 0...1)
                    .onChange(of: sensitivity) { _, v in controller.applySensitivity(v) }
                HStack { Text("rarely"); Spacer(); Text("often") }
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(describe(sensitivity)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var devicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where cues arrive").font(.subheadline.weight(.medium))
                Toggle("Phone", isOn: binding(for: .phone)).font(.subheadline)
                Toggle("Watch", isOn: binding(for: .watch)).font(.subheadline)
                Text("Starting a conversation on the phone wakes the watch app automatically. You never open both.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var channelsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("How cues arrive").font(.subheadline.weight(.medium))
                Toggle("Vibration", isOn: channelBinding(.haptic)).font(.subheadline)
                Toggle("Sound", isOn: channelBinding(.sound)).font(.subheadline)
                Toggle("Flash", isOn: channelBinding(.flash)).font(.subheadline)
                Text("Flash blinks the phone torch and the watch face in the same rhythm as the vibration. Switching one off here overrides every escalation tier below.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// The ladder is the interesting control, so it gets shown rather than
    /// hidden behind a single "escalate" toggle.
    private var escalationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Escalation").font(.subheadline.weight(.medium))
                Text("A cue you have ignored three times is not the same event as the first one, and should not feel the same.")
                    .font(.caption).foregroundStyle(.secondary)

                tierRow(1, "cues 1–\(controller.settings.escalation.tier2At - 1)",
                        controller.settings.escalation.tier1)
                tierRow(2, "cues \(controller.settings.escalation.tier2At)–\(controller.settings.escalation.tier3At - 1)",
                        controller.settings.escalation.tier2)
                tierRow(3, "cue \(controller.settings.escalation.tier3At) onward",
                        controller.settings.escalation.tier3)

                Stepper("Sound from cue \(controller.settings.escalation.tier2At)",
                        value: Binding(get: { controller.settings.escalation.tier2At },
                                       set: { controller.settings.escalation.tier2At = min($0, controller.settings.escalation.tier3At - 1); controller.persistSettings() }),
                        in: 2...9).font(.subheadline)
                Stepper("Flash from cue \(controller.settings.escalation.tier3At)",
                        value: Binding(get: { controller.settings.escalation.tier3At },
                                       set: { controller.settings.escalation.tier3At = max($0, controller.settings.escalation.tier2At + 1); controller.persistSettings() }),
                        in: 3...12).font(.subheadline)

                Text("Correcting after a cue drops you back to tier 1. The ladder responds to being ignored, not to being imperfect.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func tierRow(_ n: Int, _ range: String, _ ch: Channels) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Ink.strainColor(Double(n - 1) / 2), in: Circle())
                .foregroundStyle(Ink.bg)
            Text(range).font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                if ch.contains(.haptic) { Image(systemName: "waveform") }
                if ch.contains(.sound)  { Image(systemName: "speaker.wave.2") }
                if ch.contains(.flash)  { Image(systemName: "flashlight.on.fill") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Feel the cues").font(.subheadline.weight(.medium))
                ForEach([CueCode.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping], id: \.rawValue) { cue in
                    HStack {
                        HapticGlyph(cue: cue).frame(width: 52, alignment: .leading)
                        Text(cue.label).font(.subheadline)
                        Spacer()
                        ForEach(1...3, id: \.self) { tier in
                            Button("T\(tier)") { controller.preview(cue, tier: tier) }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Ink.bg, in: Capsule())
                        }
                    }
                }
                Text("T1 to T3 plays each escalation tier so you know what the loud one feels like before it happens in company.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Upload metrics", isOn: $syncEnabled).font(.subheadline)
                Text("Numbers only — never audio. Audio never leaves this phone under any setting.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your voice profile").font(.subheadline.weight(.medium))
                Text("Recorded once. Redo it only if separation gets unreliable — a new case, a different pocket, or a bad cold all change how you sound to the phone.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Re-record voice profile") {
                    controller.clearEnrollment()
                    hasEnrolled = false
                }
                    .font(.subheadline).foregroundStyle(Ink.drifting)
            }
        }
    }

    private func binding(for d: Devices) -> Binding<Bool> {
        Binding(get: { controller.settings.devices.contains(d) },
                set: { on in
                    var s = controller.settings.devices
                    if on { s.insert(d) } else { s.remove(d) }
                    // Removing the last device would silently disable the app.
                    if s.isEmpty { s = d == .phone ? .watch : .phone }
                    controller.settings.devices = s; controller.persistSettings()
                })
    }

    private func channelBinding(_ c: Channels) -> Binding<Bool> {
        Binding(get: { controller.settings.allowed.contains(c) },
                set: { on in
                    var s = controller.settings.allowed
                    if on { s.insert(c) } else { s.remove(c) }
                    if s.isEmpty { s = [.haptic] }
                    controller.settings.allowed = s; controller.persistSettings()
                })
    }

    private func describe(_ s: Double) -> String {
        switch s {
        case ..<0.3: return "Only when you are clearly running away. Maybe once or twice an evening."
        case ..<0.7: return "Balanced. Roughly a cue every ten to fifteen minutes of real drift."
        default:     return "Eager. Useful while learning, tiring after a week."
        }
    }
}
