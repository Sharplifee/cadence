import AVFoundation
import CadenceCore
import SwiftUI

/// Where marked moments land. Without this screen the loop records into a void
/// — the clips existed on disk and nothing in the app could reach them.
struct ClipsView: View {
    @EnvironmentObject var clips: ClipReceiver
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                if clips.library.clips.isEmpty {
                    ContentUnavailableView {
                        Label("No marks yet", systemImage: "bookmark")
                    } description: {
                        Text("Start the loop on your watch and press Mark when something matters. The last two minutes get kept and everything else is thrown away.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if !clips.library.allCommitments.isEmpty { followUps }
                            ForEach(clips.library.clips) { clip in
                                clipCard(clip)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Marks")
            .onDisappear { player?.stop(); playingID = nil }
        }
    }

    /// The reason the loop exists, hoisted above the clips themselves.
    private var followUps: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Text("Follow-ups").font(.subheadline.weight(.medium))
                ForEach(Array(clips.library.allCommitments.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 10) {
                        Text(pair.commitment.kind.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color(for: pair.commitment.kind))
                            .frame(width: 92, alignment: .leading)
                        Text(pair.commitment.text).font(.caption)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func clipCard(_ clip: MarkedClip) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(clip.windowDescription)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    stageBadge(clip)
                }

                Text(clip.headline)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if clip.stage == .processed, !clip.commitments.isEmpty {
                    ForEach(clip.commitments) { c in
                        HStack(spacing: 8) {
                            Circle().fill(color(for: c.kind)).frame(width: 6, height: 6)
                            Text(c.kind.label).font(.caption2).foregroundStyle(color(for: c.kind))
                            Text(c.text).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if let e = clip.errorMessage {
                    Text(e).font(.caption2).foregroundStyle(Ink.runaway)
                }

                HStack(spacing: 14) {
                    if !clips.audioURLs(for: clip).isEmpty {
                        Button {
                            toggle(clip)
                        } label: {
                            Label(playingID == clip.id ? "Pause" : "Play",
                                  systemImage: playingID == clip.id ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.medium))
                        }
                    }
                    if clip.needsAttention {
                        Button("Retry") { Task { await clips.retry(clip.id) } }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Ink.drifting)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        if playingID == clip.id { player?.stop(); playingID = nil }
                        clips.delete(clip.id)
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                }
            }
        }
    }

    private func stageBadge(_ clip: MarkedClip) -> some View {
        let c: Color = clip.isComplete ? Ink.matched
                     : clip.needsAttention ? Ink.runaway : Ink.drifting
        return HStack(spacing: 5) {
            if clip.stage == .sending || clip.stage == .arrived {
                ProgressView().controlSize(.mini)
            }
            Text(clip.stage.label).font(.caption2.weight(.medium)).foregroundStyle(c)
        }
    }

    /// Segments play in order, so a two-minute clip made of four files plays as
    /// one thing rather than four taps.
    private func toggle(_ clip: MarkedClip) {
        if playingID == clip.id { player?.stop(); playingID = nil; return }
        let urls = clips.audioURLs(for: clip)
        guard let first = urls.first else { return }
        player = try? AVAudioPlayer(contentsOf: first)
        player?.play()
        playingID = clip.id
    }

    private func color(for k: Commitment.Kind) -> Color {
        switch k {
        case .promise:    return Ink.runaway
        case .offer:      return Ink.drifting
        case .request:    return Ink.them
        case .scheduling: return Ink.matched
        }
    }
}
