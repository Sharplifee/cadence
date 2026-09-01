import CadenceCore
import SwiftUI

/// The in-conversation screen. Two jobs: be readable in a one-second glance
/// under a table, and prove it is actually working — a silent app you have to
/// trust is an app you stop using.
struct LiveView: View {
    @EnvironmentObject var controller: SessionController
    @State private var error: String?
    @State private var showTranscript = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        MatchRing(divergence: controller.divergence,
                                  running: controller.isRunning)
                        if controller.isRunning {
                            listeningProof
                            balances
                            if controller.transcribing { transcriptPeek }
                        } else {
                            titleField
                        }
                        cueStrip
                        controls
                        if let w = controller.warning { note(w, Ink.drifting) }
                        if let error { note(error, Ink.runaway) }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Self Attune")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(controller.isRunning ? controller.divergence.headline : "Ready")
                .font(.title2.weight(.semibold))
            Text(controller.isRunning
                 ? timeString(controller.elapsed)
                 : "Start when the conversation does. Your watch comes up on its own.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var titleField: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who is this with?").font(.caption).foregroundStyle(.secondary)
                TextField("optional — e.g. coffee with Dylan",
                          text: $controller.sessionTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
            }
        }
    }

    /// Live level and speaker attribution. This is the single most useful thing
    /// on the screen while you are learning to trust the app: if it thinks they
    /// are you, you will see it here instead of wondering why nothing buzzes.
    private var listeningProof: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hearing").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(speakerLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speakerColor)
                }
                LevelMeter(dbfs: controller.level, color: speakerColor)
                if controller.divergence.confidence < 0.5 {
                    Text("Still learning this conversation — cues stay quiet until both voices have been heard.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var speakerLabel: String {
        switch controller.currentSpeaker {
        case .me: return "you"
        case .them: return "them"
        case .overlap: return "both"
        case .silence: return "quiet"
        }
    }

    private var speakerColor: Color {
        switch controller.currentSpeaker {
        case .me: return Ink.matched
        case .them: return Ink.them
        case .overlap: return Ink.runaway
        case .silence: return .secondary
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

    private var transcriptPeek: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcript").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(controller.utterances.count) lines")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(controller.liveText.isEmpty ? "listening…" : controller.liveText)
                    .font(.footnote)
                    .foregroundStyle(controller.liveText.isEmpty ? .tertiary : .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.default, value: controller.liveText)
            }
        }
    }

    private var cueStrip: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("What a buzz means").font(.caption).foregroundStyle(.secondary)
                ForEach([CueCode.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping], id: \.rawValue) { cue in
                    HStack(spacing: 12) {
                        HapticGlyph(cue: cue).frame(width: 52, alignment: .leading)
                        Text(cue.label).font(.subheadline)
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
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .background(controller.isRunning ? Ink.runaway.opacity(0.9) : Ink.matched,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Ink.bg)

            Toggle("Metronome mode", isOn: Binding(
                get: { controller.metronomeEnabled },
                set: { controller.metronomeEnabled = $0; controller.persistSettings() }))
            .font(.subheadline).padding(.horizontal, 4)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// dBFS mapped onto a bar. Speech sits roughly -40 to -10, so the scale is
/// clamped there rather than showing 100 dB of range nobody uses.
struct LevelMeter: View {
    let dbfs: Float
    let color: Color

    private var fraction: Double {
        Double(min(max((dbfs + 50) / 40, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                Capsule().fill(color.opacity(0.85))
                    .frame(width: geo.size.width * fraction)
                    .animation(.easeOut(duration: 0.12), value: fraction)
            }
        }
        .frame(height: 10)
    }
}

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
            }
        }
        .frame(width: 250, height: 250)
        .padding(.vertical, 8)
    }
}

/// A visual stand-in for the haptic rhythm, drawn from the same CuePattern the
/// haptics use — so the picture and the buzz can never drift apart.
struct HapticGlyph: View {
    let cue: CueCode
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(CuePattern.pattern(for: cue).pulses.enumerated()), id: \.offset) { _, p in
                Capsule().fill(.white.opacity(0.75))
                    .frame(width: max(6, p.on * 38), height: 7)
            }
        }
    }
}
