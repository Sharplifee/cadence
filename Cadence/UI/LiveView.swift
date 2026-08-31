import CadenceCore
import SwiftUI

/// The in-conversation screen. Designed to be understood face-down on a table
/// with a one-second glance, and to never require reading.
struct LiveView: View {
    @EnvironmentObject var controller: SessionController
    @State private var error: String?

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    header
                    MatchRing(divergence: controller.divergence,
                              running: controller.isRunning)
                    if controller.isRunning { balances }
                    cueStrip
                    controls
                    if let error {
                        Text(error).font(.caption).foregroundStyle(Ink.runaway)
                    }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(controller.isRunning ? controller.divergence.headline : "Ready")
                .font(.title2.weight(.semibold))
            Text(controller.isRunning ? timeString(controller.elapsed) : "Tap start when the conversation begins")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var balances: some View {
        Card {
            VStack(spacing: 22) {
                BalanceBar(title: "Airtime",
                           value: Double(controller.divergence.talkShare - 0.5) * 2,
                           leftLabel: "them", rightLabel: "you")
                BalanceBar(title: "Pace",
                           value: Double(controller.divergence.rateRatio - 1) * 2,
                           leftLabel: "slower", rightLabel: "faster")
                BalanceBar(title: "Volume",
                           value: Double(controller.divergence.loudnessDelta / 10),
                           leftLabel: "quieter", rightLabel: "louder")
            }
        }
    }

    /// The vocabulary, always visible while running, so the meaning of a buzz
    /// is one glance away until it becomes muscle memory.
    private var cueStrip: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("What a buzz means").font(.caption).foregroundStyle(.secondary)
                ForEach([CueCode.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping], id: \.rawValue) { cue in
                    HStack(spacing: 12) {
                        HapticGlyph(cue: cue)
                            .frame(width: 46, alignment: .leading)
                        Text(cue.label)
                            .font(.subheadline)
                            .foregroundStyle(controller.lastCue == cue ? Ink.drifting : .primary)
                        Spacer()
                        if controller.lastCue == cue {
                            Text("last").font(.caption2).foregroundStyle(Ink.drifting)
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                do {
                    if controller.isRunning { controller.stop() } else { try controller.start() }
                    error = nil
                } catch { self.error = error.localizedDescription }
            } label: {
                Text(controller.isRunning ? "End conversation" : "Start listening")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(controller.isRunning ? Ink.runaway.opacity(0.9) : Ink.matched,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Ink.bg)

            Toggle("Metronome mode", isOn: Binding(
                get: { controller.metronomeEnabled },
                set: { controller.metronomeEnabled = $0 }))
            .font(.subheadline)
            .padding(.horizontal, 4)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// The ring is the whole interface. Full and green means you are matched; it
/// opens and warms as you pull away from them.
struct MatchRing: View {
    let divergence: Divergence
    let running: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.06, 1 - divergence.strain * 0.8))
                .stroke(Ink.strainColor(divergence.strain),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: divergence.strain)
            VStack(spacing: 2) {
                Text("\(Int((running ? divergence.talkShare : 0.5) * 100))")
                    .font(.system(size: 62, weight: .medium, design: .rounded))
                    .contentTransition(.numericText())
                Text("% of the talking").font(.caption2).foregroundStyle(.secondary)
                if divergence.confidence < 0.5 && running {
                    Text("low confidence").font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
                }
            }
        }
        .frame(width: 250, height: 250)
        .padding(.vertical, 8)
    }
}

/// A visual stand-in for the haptic rhythm, so the pattern can be learned by
/// eye before it has to be recognised by wrist.
struct HapticGlyph: View {
    let cue: CueCode

    private var dots: (count: Int, spacing: CGFloat, wide: Bool) {
        switch cue {
        case .slowDown:        return (2, 9, false)
        case .lowerVolume:     return (1, 0, true)
        case .yieldFloor:      return (3, 4, false)
        case .stopOverlapping: return (2, 3, false)
        default:               return (1, 0, false)
        }
    }

    var body: some View {
        HStack(spacing: dots.spacing) {
            ForEach(0..<dots.count, id: \.self) { _ in
                Capsule()
                    .fill(.white.opacity(0.75))
                    .frame(width: dots.wide ? 26 : 7, height: 7)
            }
        }
    }
}
