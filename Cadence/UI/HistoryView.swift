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
                    ContentUnavailableView("No conversations yet",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Run one and it will show up here."))
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            TrendCard(sessions: sessions)
                            ForEach(sessions, id: \.id) { s in
                                NavigationLink { SessionDetailView(summary: s) } label: {
                                    SessionRow(summary: s)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
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

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("You corrected after").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rate.map { "\(Int($0 * 100))%" } ?? "—")
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                    Text("of cues").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Across \(sessions.count) conversations. This is the number worth moving.")
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
                    Text(summary.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.subheadline.weight(.medium))
                    Text("\(Int(summary.duration / 60)) min · \(Int(summary.talkShare * 100))% yours · \(summary.cues.count) cues")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(Ink.strainColor(Double(abs(summary.talkShare - 0.5)) * 2.8))
                    .frame(width: 10, height: 10)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Where the learning actually happens — every cue, what triggered it, and
/// whether you closed the gap in the thirty seconds after.
struct SessionDetailView: View {
    let summary: SessionSummary

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        HStack {
                            Stat(value: "\(Int(summary.duration / 60))m", label: "length")
                            Spacer()
                            Stat(value: "\(Int(summary.talkShare * 100))%", label: "your airtime")
                            Spacer()
                            Stat(value: "\(summary.interruptions)", label: "interruptions")
                        }
                    }
                    ForEach(Array(summary.cues.enumerated()), id: \.offset) { _, cue in
                        Card {
                            HStack(alignment: .top, spacing: 14) {
                                HapticGlyph(cue: cue.code).frame(width: 46, alignment: .leading).padding(.top, 5)
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
                .padding(20)
            }
        }
        .navigationTitle(summary.startedAt.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
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
