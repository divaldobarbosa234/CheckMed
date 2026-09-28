import SwiftUI

/// Read-only Current / Upcoming / Past treatment tree.
/// Does not persist, seed DoseLogs, or commit onboarding.
struct JourneyTreeScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments

    private var tree: CheckMedStore.JourneyTreeSnapshot {
        treatments.journeyTreeSnapshot()
    }

    var body: some View {
        let snapshot = tree
        ScreenScaffold(
            title: session.t(.journeyTreeTitle),
            philSize: 64,
            bubble: session.t(.journeyTreeBubble)
        ) {
            if snapshot.isEmpty {
                Text(session.t(.journeyTreeEmptyAll))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                section(
                    title: session.t(.journeySectionCurrent),
                    branches: snapshot.current,
                    empty: session.t(.journeyTreeEmptyCurrent),
                    kind: .current
                )
                if !snapshot.future.isEmpty {
                    section(
                        title: session.t(.journeySectionUpcoming),
                        branches: snapshot.future,
                        empty: session.t(.journeyTreeEmptyUpcoming),
                        kind: .future
                    )
                }
                if !snapshot.past.isEmpty {
                    section(
                        title: session.t(.journeySectionPast),
                        branches: snapshot.past,
                        empty: session.t(.journeyTreeEmptyPast),
                        kind: .past
                    )
                }
            }
            CheckMedButton(title: session.t(.journeyOpenReport), style: .secondary) {
                go(.journeyReport)
            }
            CheckMedButton(title: session.t(.progressTitle), style: .ghost) {
                go(.progressDashboard)
            }
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        branches: [CheckMedStore.JourneyTreeBranch],
        empty: String,
        kind: TreatmentJourneyKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .textCase(.uppercase)
            if branches.isEmpty {
                Text(empty)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(.vertical, 4)
            } else {
                ForEach(branches) { branch in
                    treatmentCard(branch, kind: kind)
                }
            }
        }
    }

    private func treatmentCard(_ branch: CheckMedStore.JourneyTreeBranch, kind: TreatmentJourneyKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(branch.medicineNames.joined(separator: " · "))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                Spacer(minLength: 8)
                Text(kindLabel(kind))
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(kindAccent(kind))
            }
            Text(dateLine(branch, kind: kind))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(branch.medicineNames.enumerated()), id: \.offset) { _, name in
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(kindAccent(kind).opacity(0.85))
                            .frame(width: 7, height: 7)
                        Text(name)
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.ink)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func kindLabel(_ kind: TreatmentJourneyKind) -> String {
        switch kind {
        case .current: session.t(.treatmentStatusActive)
        case .future: session.t(.journeySectionUpcoming)
        case .past: session.t(.treatmentStatusCompleted)
        }
    }

    private func kindAccent(_ kind: TreatmentJourneyKind) -> Color {
        switch kind {
        case .current: CheckMedTheme.primaryShadow
        case .future: CheckMedTheme.flowDot
        case .past: CheckMedTheme.muted
        }
    }

    private func dateLine(_ branch: CheckMedStore.JourneyTreeBranch, kind: TreatmentJourneyKind) -> String {
        let start = formatted(branch.startDate)
        if kind == .future {
            return "\(session.t(.durationStart)) \(start)"
        }
        if let end = branch.endDate {
            return "\(start) – \(formatted(end))"
        }
        return "\(session.t(.progressTreatmentStarted)) · \(start)"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = session.foundationCalendar
        formatter.locale = session.locale.foundationLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMy")
        return formatter.string(from: date)
    }
}
