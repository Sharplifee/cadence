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
            VStack(spacing: 2) {
                Image(systemName: receiver.active ? "waveform" : "waveform.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(receiver.active ? strainColor : .secondary)
                Text(receiver.active ? "listening" : "off")
                    .font(.caption2).foregroundStyle(.secondary)
                if receiver.lastCue != .none && receiver.active {
                    Text(receiver.lastCue.label)
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center).padding(.top, 3)
                }
            }
        }
        .padding(6)
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
