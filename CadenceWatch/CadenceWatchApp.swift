import CadenceCore
import SwiftUI

@main
struct CadenceWatchApp: App {
    @StateObject private var receiver = PhoneReceiver()
    @StateObject private var loop = WatchAmbientRecorder()
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(receiver)
                .environmentObject(loop)
                .task { await receiver.runtime.requestAuthorization() }
        }
    }
}

/// Two pages: a glanceable ring, and the vocabulary for the first fortnight
/// before it becomes habit. The flash overlay sits above both.
struct WatchRootView: View {
    @EnvironmentObject var receiver: PhoneReceiver

    var body: some View {
        ZStack {
            TabView {
                WatchLoopView()
                WatchLiveView()
                WatchLegendView()
                WatchHelpView()
            }
            .tabViewStyle(.verticalPage)

            // The watch has no torch, so the screen is the light. Full white,
            // ignoring safe areas, is the only thing bright enough to register
            // in peripheral vision under a cuff.
            if receiver.cuePlayer.flashOn {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.04), value: receiver.cuePlayer.flashOn)
    }
}

struct WatchLiveView: View {
    @EnvironmentObject var receiver: PhoneReceiver

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.06, 1 - receiver.strain * 0.8))
                .stroke(strainColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: receiver.strain)
            VStack(spacing: 1) {
                if receiver.active {
                    Text("\(Int(receiver.talkShare * 100))")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                    Text("% yours").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if receiver.pending {
                    ProgressView().controlSize(.small)
                    Text("starting").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("tap to start").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if receiver.active && receiver.markCount > 0 {
                    Text("\(receiver.markCount) marked")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if receiver.lastCue != .none && receiver.active {
                    Text(receiver.lastCue.label)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center).padding(.top, 2)
                }
            }
        }
        .padding(6)
        // Tap marks the moment while running; long press starts or ends it.
        // Marking is the frequent action, so it gets the easy gesture.
        .onTapGesture {
            if receiver.active { receiver.markMoment() } else { receiver.toggleSession() }
        }
        .onLongPressGesture(minimumDuration: 0.6) { receiver.toggleSession() }
    }

    private var strainColor: Color {
        receiver.strain < 0.45 ? .green : (receiver.strain < 0.75 ? .orange : .red)
    }
}

struct WatchLegendView: View {
    @EnvironmentObject var receiver: PhoneReceiver
    private let cues: [CueCode] = [.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping]

    var body: some View {
        List {
            ForEach(cues, id: \.rawValue) { cue in
                Button {
                    receiver.cuePlayer.play(cue, channels: .haptic, tier: 1)
                } label: {
                    HStack(spacing: 10) {
                        WatchGlyph(cue: cue)
                        Text(cue.label).font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.carousel)
    }
}

struct WatchGlyph: View {
    let cue: CueCode
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(CuePattern.pattern(for: cue).pulses.enumerated()), id: \.offset) { _, p in
                Capsule().fill(.white.opacity(0.8))
                    .frame(width: max(4, p.on * 28), height: 5)
            }
        }
        .frame(width: 40, alignment: .leading)
    }
}

/// The wrist needs to answer "what do I do now" without the phone.
struct WatchHelpView: View {
    @EnvironmentObject var receiver: PhoneReceiver
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap the ring").font(.system(size: 14, weight: .semibold))
                Text("Starts or ends the conversation on both devices.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text("The ring").font(.system(size: 14, weight: .semibold))
                Text("Full and green means you are matched to them. It opens and warms as you pull ahead.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text("If it buzzes twice").font(.system(size: 14, weight: .semibold))
                Text("Slow down. Once long: quieter. Three quick: let them talk. Sharp double: you cut them off.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// The always-on loop. It lives on the wrist because the Watch has its own
/// audio session — the phone stays free for voice memos, calls and every other
/// audio app without either one fighting the other.
struct WatchLoopView: View {
    @EnvironmentObject var loop: WatchAmbientRecorder

    private var countdown: String {
        let total = TimeInterval(loop.segmentMinutes) * 60
        let left = max(0, total - loop.currentSegmentElapsed)
        return String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(loop.isLooping ? .green : .gray)
                    .frame(width: 7, height: 7)
                Text(loop.isLooping ? "Looping" : "Loop off")
                    .font(.system(size: 13, weight: .medium))
            }

            Text(loop.isLooping ? countdown : "—")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(loop.isLooping ? "until next send" : "\(loop.segmentMinutes) min loops")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            if loop.isLooping {
                Button {
                    _ = loop.markMoment()
                } label: {
                    Label("Mark", systemImage: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(.blue)
            }

            Button(loop.isLooping ? "Stop" : "Start loop") {
                loop.isLooping ? loop.stopLoop() : loop.startLoop()
            }
            .font(.system(size: 12))
            .tint(loop.isLooping ? .red : .green)

            Text("\(loop.segmentsSent) sent · \(loop.savedClips) marked")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            if let e = loop.lastError {
                Text(e).font(.system(size: 9)).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }
}
