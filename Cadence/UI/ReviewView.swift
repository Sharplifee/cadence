import CadenceCore
import SwiftUI

/// The list the loop exists to produce: everything heard, each one a yes or no,
/// and one button that puts the yeses on your calendar.
struct ReviewView: View {
    @EnvironmentObject var clips: ClipReceiver
    @State private var writer = CalendarWriter()
    @State private var status: String?
    @State private var working = false

    private var undecided: [ActionItem] { clips.queue.undecided }
    private var ready: [ActionItem] { clips.queue.readyForCalendar }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                if clips.queue.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing heard yet", systemImage: "checklist")
                    } description: {
                        Text("Start the loop on your watch. Every five minutes it sends what it heard, and anything that sounds like a commitment, an ask or a time shows up here.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(clips.queue.items) { item in row(item) }
                        }
                        .padding(20)
                        .padding(.bottom, 80)
                    }
                }

                if !ready.isEmpty {
                    VStack {
                        Spacer()
                        addButton
                    }
                }
            }
            .navigationTitle("Heard")
            .task { _ = await writer.requestAccess() }
        }
    }

    private func row(_ item: ActionItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.kind.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color(for: item.kind))
                    Spacer()
                    if item.isOnCalendar {
                        Label("on calendar", systemImage: "calendar.badge.checkmark")
                            .font(.caption2).foregroundStyle(Ink.matched)
                    }
                }

                Text(item.text).font(.subheadline)

                if let due = item.dueAt {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(due.formatted(date: .abbreviated,
                                           time: item.hasExplicitTime ? .shortened : .omitted))
                        if !item.hasExplicitTime {
                            Text("· time not stated").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption).foregroundStyle(Ink.them)
                } else {
                    Text("No date heard — this one is just a note.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                if !item.isOnCalendar {
                    HStack(spacing: 10) {
                        choice("Yes", on: item.accepted == true, tint: Ink.matched) {
                            clips.setAccepted(item.id, item.accepted == true ? nil : true)
                        }
                        choice("No", on: item.accepted == false, tint: Ink.runaway) {
                            clips.setAccepted(item.id, item.accepted == false ? nil : false)
                        }
                        Spacer()
                        Text(item.capturedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func choice(_ label: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(on ? tint : Ink.bg, in: Capsule())
                .foregroundStyle(on ? Ink.bg : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        VStack(spacing: 6) {
            Button {
                Task { await addAll() }
            } label: {
                HStack {
                    if working { ProgressView().controlSize(.small) }
                    Text(working ? "Adding…" : "Add \(ready.count) to calendar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .disabled(working)
            .background(Ink.matched, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Ink.bg)

            if let status {
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func addAll() async {
        working = true
        defer { working = false }
        var authorized = writer.isAuthorized
        if !authorized { authorized = await writer.requestAccess() }
        guard authorized else {
            status = "Calendar access is off. Turn it on in iOS Settings, Self Attune."
            return
        }
        var added = 0
        for item in ready {
            do {
                let id = try writer.add(item)
                clips.markOnCalendar(item.id, eventID: id)
                added += 1
            } catch {
                status = error.localizedDescription
            }
        }
        if added > 0 { status = "Added \(added) to your calendar." }
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
