import SwiftUI

struct PathNodeView: View {
    let node: DoseNode
    var offset: CGFloat
    var showConnector: Bool
    var onTake: () -> Void
    var onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(ringColor, lineWidth: 6)
                        .background(Circle().fill(node.status == .current ? CheckMedTheme.current : CheckMedTheme.surface))
                    Text(glyph)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(node.status == .current ? Color.white : CheckMedTheme.primary)
                }
                .frame(width: 58, height: 58)
                if showConnector {
                    Capsule()
                        .fill(CheckMedTheme.locked)
                        .frame(width: 6, height: 28)
                }
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(node.time)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .textCase(.uppercase)
                Text(node.medicine)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                if node.status == .current {
                    HStack {
                        Button("Taken", action: onTake)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(CheckMedTheme.primary, in: Capsule())
                        Button("Skip", action: onSkip)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(CheckMedTheme.ink, lineWidth: 2))
                    }
                    .padding(.top, 4)
                } else {
                    Text(statusLabel)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
            )
        }
        .padding(.leading, offset)
    }

    private var ringColor: Color {
        switch node.status {
        case .done: CheckMedTheme.primary
        case .current: CheckMedTheme.current
        case .skipped: CheckMedTheme.skip
        case .locked: CheckMedTheme.locked
        }
    }

    private var glyph: String {
        switch node.status {
        case .done: "✓"
        case .skipped: "–"
        case .current: "!"
        case .locked: ""
        }
    }

    private var statusLabel: String {
        switch node.status {
        case .done: "Logged"
        case .skipped: "Skipped"
        case .locked: "Locked"
        case .current: ""
        }
    }
}
