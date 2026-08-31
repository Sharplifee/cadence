import CadenceCore
import SwiftUI

/// One slider, not eleven. Sensitivity moves every threshold together, because
/// nobody can reason about "interruptions per minute" as a number — they can
/// only tell you it buzzes too much or not enough.
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
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sensitivity").font(.subheadline.weight(.medium))
                                Slider(value: $sensitivity, in: 0...1)
                                    .onChange(of: sensitivity) { _, v in controller.applySensitivity(v) }
                                HStack {
                                    Text("rarely"); Spacer(); Text("often")
                                }
                                .font(.caption2).foregroundStyle(.tertiary)
                                Text(describe(sensitivity))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Feel the cues").font(.subheadline.weight(.medium))
                                ForEach([CueCode.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping], id: \.rawValue) { cue in
                                    Button { controller.preview(cue) } label: {
                                        HStack {
                                            HapticGlyph(cue: cue).frame(width: 46, alignment: .leading)
                                            Text(cue.label).font(.subheadline)
                                            Spacer()
                                            Image(systemName: "play.circle").foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Upload metrics", isOn: $syncEnabled)
                                    .font(.subheadline)
                                Text("Numbers only — never audio. Audio never leaves this phone under any setting.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your voice profile").font(.subheadline.weight(.medium))
                                Text("Redo this if separation gets unreliable — a new phone case, a different pocket, or a bad cold all change it.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Re-record voice profile") { hasEnrolled = false }
                                    .font(.subheadline).foregroundStyle(Ink.drifting)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func describe(_ s: Double) -> String {
        switch s {
        case ..<0.3:  return "Only when you are clearly running away. Maybe once or twice an evening."
        case ..<0.7:  return "Balanced. Roughly a cue every ten to fifteen minutes of real drift."
        default:      return "Eager. Useful while learning, tiring after a week."
        }
    }
}
