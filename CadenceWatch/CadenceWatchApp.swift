import CadenceCore
import SwiftUI

@main
struct CadenceWatchApp: App {
    @StateObject private var receiver = PhoneReceiver()
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(receiver)
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
                } else {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("off").font(.caption2).foregroundStyle(.secondary)
                }
                if receiver.lastCue != .none && receiver.active {
                    Text(receiver.lastCue.label)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center).padding(.top, 2)
                }
            }
        }
        .padding(6)
        // Tapping the ring starts or stops the whole thing, phone included.
        .onTapGesture { receiver.toggleSession() }
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
