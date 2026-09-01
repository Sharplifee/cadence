import AVFoundation
import CadenceCore
import SwiftUI

/// Three steps, in the order that makes sense: say what it does, get the mic,
/// learn your voice, learn the buzzes. Nothing optional, nothing skippable,
/// because a skipped enrollment produces a silently useless app.
struct OnboardingFlow: View {
    let onComplete: () -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            VStack {
                ProgressView(value: Double(step + 1), total: 4)
                    .tint(Ink.matched).padding(.horizontal, 40).padding(.top, 12)
                Spacer()
                switch step {
                case 0: WelcomeStep { step = 1 }
                case 1: PermissionStep { step = 2 }
                case 2: EnrollmentStep { step = 3 }
                default: VocabularyStep(onDone: onComplete)
                }
                Spacer()
            }
        }
    }
}

private struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 72)).foregroundStyle(Ink.matched)
            Text("Cadence").font(.largeTitle.weight(.semibold))
            Text("It listens to the conversation, works out how fast and loud the other person is, and taps your wrist when you have run ahead of them. Nobody else knows.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 34)
            PrimaryButton("Get started", action: next)
        }
    }
}

private struct PermissionStep: View {
    @EnvironmentObject var controller: SessionController
    let next: () -> Void
    @State private var denied = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "mic.circle").font(.system(size: 72)).foregroundStyle(Ink.them)
            Text("Microphone").font(.title2.weight(.semibold))
            Text("Everything is analysed on this phone. Audio is never uploaded — only the numbers, and only if you turn sync on later. Cadence also asks for a workout permission, which is the only way iOS can wake your watch app for you.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 34)
            if denied {
                Text("Microphone access was denied. Enable it in Settings to continue.")
                    .font(.caption).foregroundStyle(Ink.runaway).padding(.horizontal, 34)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton("Allow microphone") {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { denied = true; return }
                        Task {
                            // Launching the watch app from the phone goes
                            // through HealthKit, so ask now rather than at the
                            // start of the first real conversation.
                            await controller.prepareWatch()
                            next()
                        }
                    }
                }
            }
        }
    }
}

/// Thirty seconds of you talking, once, with something to actually read.
/// "Just talk" produces stilted two-word bursts and a profile that only matches
/// you when you are self-conscious — which is precisely when you do not need it.
private struct EnrollmentStep: View {
    @EnvironmentObject var controller: SessionController
    let next: () -> Void
    @State private var remaining = Int(EnrollmentScript.targetDuration)
    @State private var running = false
    @State private var timer: Timer?

    private var fraction: Double {
        1 - Double(remaining) / EnrollmentScript.targetDuration
    }
    private var currentLine: Int { EnrollmentScript.lineIndex(atFraction: fraction) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Ink.matched, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    Text("\(remaining)")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 3) {
                    Text(running ? "Keep reading" : "Read this out loud")
                        .font(.headline)
                    Text("Hold the phone where you normally carry it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(EnrollmentScript.lines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.system(size: 19, weight: i == currentLine && running ? .semibold : .regular))
                            .foregroundStyle(!running ? .primary
                                             : (i == currentLine ? .primary
                                                : (i < currentLine ? .tertiary : .secondary)))
                            .animation(.easeInOut(duration: 0.3), value: currentLine)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)

            if !running {
                PrimaryButton("Start reading") { begin() }
            } else {
                Text("This happens once.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func begin() {
        running = true
        try? controller.startEnrollment()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                controller.finishEnrollment()
                next()
            }
        }
    }
}

/// Teach the vocabulary before the first real conversation, and let the wrist
/// actually feel each pattern — reading them is not the same as knowing them.
private struct VocabularyStep: View {
    @EnvironmentObject var controller: SessionController
    let onDone: () -> Void
    private let cues: [CueCode] = [.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping]

    var body: some View {
        VStack(spacing: 18) {
            Text("Four taps to learn").font(.title2.weight(.semibold))
            Text("Tap each one to feel it on your watch.")
                .font(.footnote).foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(cues, id: \.rawValue) { cue in
                    Button { controller.preview(cue) } label: {
                        HStack(spacing: 14) {
                            HapticGlyph(cue: cue).frame(width: 46, alignment: .leading)
                            Text(cue.label).font(.subheadline)
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            PrimaryButton("I'm ready", action: onDone)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        .background(Ink.matched, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(Ink.bg)
        .padding(.horizontal, 40)
    }
}
