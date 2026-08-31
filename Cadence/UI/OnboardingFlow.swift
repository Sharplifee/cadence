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
    let next: () -> Void
    @State private var denied = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "mic.circle").font(.system(size: 72)).foregroundStyle(Ink.them)
            Text("Microphone").font(.title2.weight(.semibold))
            Text("Everything is analysed on this phone. Audio is never uploaded — only the numbers, and only if you turn sync on later.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 34)
            if denied {
                Text("Microphone access was denied. Enable it in Settings to continue.")
                    .font(.caption).foregroundStyle(Ink.runaway).padding(.horizontal, 34)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton("Allow microphone") {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async { granted ? next() : (denied = true) }
                }
            }
        }
    }
}

/// Sixty seconds of you talking, once. Everything downstream depends on it,
/// so it gets its own screen and an explicit reason.
private struct EnrollmentStep: View {
    @EnvironmentObject var controller: SessionController
    let next: () -> Void
    @State private var remaining = 60
    @State private var running = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: 1 - Double(remaining) / 60)
                    .stroke(Ink.matched, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Text("\(remaining)")
                    .font(.system(size: 54, weight: .light, design: .rounded))
            }
            .frame(width: 180, height: 180)

            Text("Read anything out loud").font(.title3.weight(.semibold))
            Text("Hold the phone the way you normally carry it — pocket, hand, on the table. Where it sits is part of what it learns, so be honest about it.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).padding(.horizontal, 34)

            if !running {
                PrimaryButton("Start reading") { begin() }
            } else {
                Text("Keep talking…").font(.footnote).foregroundStyle(.tertiary)
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
