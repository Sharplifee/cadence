import CadenceCore
import SwiftUI

/// One accent that moves with how far out of sync you are, dark by default.
/// This gets glanced at under a table mid-conversation — it has to be readable
/// in a quarter of a second and boring the rest of the time.
enum Ink {
    static let bg        = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let surface   = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let matched   = Color(red: 0.30, green: 0.82, blue: 0.60)
    static let drifting  = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let runaway   = Color(red: 0.96, green: 0.38, blue: 0.36)
    static let them      = Color(red: 0.45, green: 0.62, blue: 0.95)

    static func strainColor(_ s: Double) -> Color {
        s < 0.45 ? matched : (s < 0.75 ? drifting : runaway)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A labelled bar centred on "matched", so drift reads as distance from centre
/// rather than as a number you have to interpret.
struct BalanceBar: View {
    let title: String
    let value: Double        // -1 ... 1, 0 = matched
    let leftLabel: String
    let rightLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                let clamped = min(max(value, -1), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08)).frame(height: 8)
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                        .offset(x: w / 2)
                    Circle()
                        .fill(Ink.strainColor(abs(clamped)))
                        .frame(width: 16, height: 16)
                        .offset(x: (w / 2) + (w / 2 - 8) * clamped - 8)
                        .animation(.easeOut(duration: 0.4), value: clamped)
                }
            }
            .frame(height: 18)
            HStack {
                Text(leftLabel); Spacer(); Text(rightLabel)
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
