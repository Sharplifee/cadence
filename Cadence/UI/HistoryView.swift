import AVFoundation
import CadenceCore
import SwiftUI

struct HistoryView: View {
    @State private var sessions: [SessionSummary] = []
    private let store = SessionStore()

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No conversations yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Run one and it shows up here with a transcript and what to work on.")
                    }
                } else {
                    List {
                        Section {
                            TrendCard(sessions: sessions).listRowBackground(Color.clear)
                        }
                        Section {
                            ForEach(sessions, id: \.id) { s in
                                NavigationLink { SessionDetailView(summary: s) } label: {
                                    SessionRow(summary: s)
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { idx in
                                idx.map { sessions[$0].id }.forEach(store.delete)
                                sessions.remove(atOffsets: idx)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .onAppear { sessions = store.allSummaries() }
        }
    }
}

/// The only number that proves the app works: are you correcting more often
/// than you were a month ago.
struct TrendCard: View {
    let sessions: [SessionSummary]

    private var rate: Float? {
        let scored = sessions.compactMap { $0.correctionRate }
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Float(scored.count)
    }
    private var avgShare: Float {
        guard !sessions.isEmpty else { return 0.5 }
        return sessions.map(\.talkShare).reduce(0,+) / Float(sessions.count)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 24) {
                    Stat(value: rate.map { "\(Int($0 * 100))%" } ?? "—", label: "cues corrected")
                    Stat(value: "\(Int(avgShare * 100))%", label: "avg airtime")
                    Stat(value: "\(sessions.count)", label: "conversations")
                }
                Text("Corrected is the one to move. It means you felt a cue and closed the gap within thirty seconds.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct SessionRow: View {
    let summary: SessionSummary

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.displayTitle).font(.subheadline.weight(.medium))
                    Text("\(Int(summary.duration / 60)) min · \(Int(summary.talkShare * 100))% yours · \(summary.cues.count) cues")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if summary.hasAudio {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(.tertiary)
                }
                Circle()
                    .fill(Ink.strainColor(Double(abs(summary.talkShare - 0.5)) * 2.8))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

/// Where the learning happens: what to work on, then the transcript, then every
/// cue with the reason it fired and whether you closed the gap.
struct SessionDetailView: View {
    let summary: SessionSummary
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var tab = 0
    private let store = SessionStore()

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    statsCard
                    if summary.hasAudio { playbackCard }
                    Picker("", selection: $tab) {
                        Text(summary.isAmbient ? "Marks" : "What to work on").tag(0)
                        Text("Transcript").tag(1)
                        Text(summary.isAmbient ? "Timeline" : "Cues").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case 0: summary.isAmbient ? AnyView(marksSection) : AnyView(findingsSection)
                    case 1: transcriptSection
                    default: summary.isAmbient ? AnyView(timelineSection) : AnyView(cuesSection)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(summary.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player?.stop() }
    }

    private var statsCard: some View {
        Card {
            HStack {
                Stat(value: "\(Int(summary.duration / 60))m", label: "length")
                Spacer()
                Stat(value: "\(Int(summary.talkShare * 100))%", label: "your airtime")
                Spacer()
                Stat(value: "\(summary.interruptions)", label: "interruptions")
                Spacer()
                Stat(value: "\(summary.cues.count)", label: "cues")
            }
        }
    }

    private var playbackCard: some View {
        Card {
            HStack(spacing: 14) {
                Button {
                    if playing { player?.pause(); playing = false }
                    else {
                        if player == nil, let url = store.audioURL(for: summary.id) {
                            player = try? AVAudioPlayer(contentsOf: url)
                        }
                        player?.play(); playing = true
                    }
                } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(Ink.matched)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Listen back").font(.subheadline.weight(.medium))
                    Text("Stays on this phone. Nothing was uploaded.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    /// Bookmarks first — this is what an ambient recording is for.
    private var marksSection: some View {
        VStack(spacing: 12) {
            if summary.timeline.bookmarks.isEmpty {
                Card { Text("Nothing marked in this recording.")
                        .font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(summary.timeline.bookmarks) { m in
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "bookmark.fill").foregroundStyle(Ink.them)
                            Text(m.label).font(.subheadline.weight(.medium))
                            Spacer()
                            Button(timeString(m.t)) { seek(to: m.t) }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Ink.matched)
                        }
                        let ctx = summary.timeline.context(around: m)
                        if !ctx.isEmpty {
                            Text("Around it: " + ctx.map(\.label).joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            gapNotice
        }
    }

    private var timelineSection: some View {
        VStack(spacing: 8) {
            ForEach(summary.timeline.markers) { m in
                HStack {
                    Text(m.label).font(.caption)
                    Spacer()
                    Button(timeString(m.t)) { seek(to: m.t) }
                        .font(.caption2.monospacedDigit()).foregroundStyle(Ink.matched)
                }
                .padding(.horizontal, 4)
            }
            gapNotice
        }
    }

    /// Never let a hole in the recording look like silence.
    @ViewBuilder private var gapNotice: some View {
        let gaps = summary.timeline.audioGaps(upTo: summary.duration)
        if !gaps.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Missing audio").font(.subheadline.weight(.medium))
                        .foregroundStyle(Ink.drifting)
                    Text("\(Int(summary.timeline.gapSeconds(upTo: summary.duration) / 60)) min across \(gaps.count) period(s). Sound routed to headphones never reaches the microphone, so it is not in this recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func seek(to t: TimeInterval) {
        if player == nil, let url = store.audioURL(for: summary.id) {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        player?.currentTime = t
        player?.play()
        playing = true
    }

    /// What was actually agreed. This is the part you came back for.
    private var commitmentsSection: some View {
        let items = CommitmentExtractor.extract(from: summary.utterances)
        return VStack(spacing: 10) {
            if items.isEmpty {
                Card {
                    Text("Nothing was promised, offered or asked for in this conversation.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(items) { c in
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.kind.label.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color(for: c.kind))
                            Spacer()
                            Text(timeString(c.at))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(c.text).font(.subheadline)
                    }
                }
            }
        }
    }

    private func color(for k: Commitment.Kind) -> Color {
        switch k {
        case .promise:    return Ink.runaway
        case .offer:      return Ink.drifting
        case .request:    return Ink.them
        case .scheduling: return Ink.matched
        }
    }

    private var findingsSection: some View {
        VStack(spacing: 12) {
            if let ins = summary.insights {
                ForEach(Array(ins.findings.enumerated()), id: \.offset) { _, f in
                    Card { Text(f).font(.subheadline).foregroundStyle(.primary) }
                }
                Card {
                    HStack {
                        Stat(value: "\(Int(ins.yourWPM))", label: "your wpm")
                        Spacer()
                        Stat(value: "\(Int(ins.theirWPM))", label: "their wpm")
                        Spacer()
                        Stat(value: "\(ins.questionsAsked)", label: "questions")
                    }
                }
            } else {
                Card { Text("No analysis for this conversation.").foregroundStyle(.secondary) }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(spacing: 10) {
            if summary.utterances.isEmpty {
                Card {
                    Text("No transcript — speech recognition was unavailable for this conversation.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(summary.utterances) { u in
                HStack(alignment: .top, spacing: 10) {
                    if u.speaker == .me { Spacer(minLength: 40) }
                    VStack(alignment: u.speaker == .me ? .trailing : .leading, spacing: 4) {
                        Text(u.text).font(.subheadline)
                            .frame(maxWidth: .infinity,
                                   alignment: u.speaker == .me ? .trailing : .leading)
                        Text("\(u.speaker == .me ? "you" : "them") · \(timeString(u.start)) · \(Int(u.wpm)) wpm")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(u.speaker == .me ? Ink.matched.opacity(0.16) : Ink.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if u.speaker != .me { Spacer(minLength: 40) }
                }
            }
        }
    }

    private var cuesSection: some View {
        VStack(spacing: 12) {
            if summary.cues.isEmpty {
                Card { Text("No cues fired — you stayed in step the whole way.")
                        .font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(Array(summary.cues.enumerated()), id: \.offset) { _, cue in
                Card {
                    HStack(alignment: .top, spacing: 14) {
                        HapticGlyph(cue: cue.code).frame(width: 52, alignment: .leading).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cue.code.label).font(.subheadline.weight(.medium))
                            Text(reason(cue)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 3) {
                            Text(timeString(cue.t)).font(.caption2).foregroundStyle(.tertiary)
                            if let corrected = cue.corrected {
                                Image(systemName: corrected ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(corrected ? Ink.matched : Ink.runaway)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reason(_ c: CueEvent) -> String {
        let d = c.divergence
        switch c.code {
        case .slowDown:        return String(format: "%.0f%% faster than them", (d.rateRatio - 1) * 100)
        case .lowerVolume:     return String(format: "%.1f dB louder than them", d.loudnessDelta)
        case .yieldFloor:      return String(format: "you held %.0f%% of the airtime", d.talkShare * 100)
        case .stopOverlapping: return String(format: "%.1f interruptions per minute", d.interruptRate)
        default:               return ""
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.medium).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
