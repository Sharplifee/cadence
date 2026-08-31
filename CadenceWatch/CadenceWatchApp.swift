import CadenceCore
import SwiftUI

@main
struct CadenceWatchApp: App {
    @StateObject private var receiver = PhoneReceiver()
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(receiver)
        }
    }
}

/// Two pages. The first is a glanceable ring you can read through a shirt cuff;
/// the second is the vocabulary, for the first fortnight before it is habit.
struct WatchRootView: View {
    @EnvironmentObject var receiver: PhoneReceiver
    var body: some View {
        TabView {
            WatchLiveView()
            WatchLegendView()
        }
        .tabViewStyle(.verticalPage)
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
                        .multilineTextAlignment(.center)
                        .padding(.top, 3)
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
    private let cues: [CueCode] = [.slowDown, .lowerVolume, .yieldFloor, .stopOverlapping]

    var body: some View {
        List {
            ForEach(cues, id: \.rawValue) { cue in
                HStack(spacing: 10) {
                    WatchGlyph(cue: cue)
                    Text(cue.label).font(.system(size: 13))
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.carousel)
    }
}

struct WatchGlyph: View {
    let cue: CueCode
    private var shape: (count: Int, spacing: CGFloat, wide: Bool) {
        switch cue {
        case .slowDown:        return (2, 7, false)
        case .lowerVolume:     return (1, 0, true)
        case .yieldFloor:      return (3, 3, false)
        case .stopOverlapping: return (2, 2, false)
        default:               return (1, 0, false)
        }
    }
    var body: some View {
        HStack(spacing: shape.spacing) {
            ForEach(0..<shape.count, id: \.self) { _ in
                Capsule().fill(.white.opacity(0.8))
                    .frame(width: shape.wide ? 20 : 5, height: 5)
            }
        }
        .frame(width: 34, alignment: .leading)
    }
}
