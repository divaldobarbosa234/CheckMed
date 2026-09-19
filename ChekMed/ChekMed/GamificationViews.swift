import SwiftUI

struct GamificationStreakCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PhilView(size: 72, mood: philMood, smiling: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(session.t(.streakCurrent, snapshot.currentStreak))
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundStyle(CheckMedTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(coachLine)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.t(.streakCurrent, snapshot.currentStreak)). \(coachLine)")
    }

    private var philMood: CompanionMood {
        switch snapshot.coach {
        case .challengeComplete, .milestone, .backOnTrack: .celebrate
        case .needsAttention: .sad
        default: snapshot.isComplete ? .complete : .idle
        }
    }

    private var coachLine: String {
        switch snapshot.coach {
        case .firstDay:
            return session.t(.philFirstDay)
        case .inProgress(let remaining):
            return remaining == 1 ? session.t(.challengeOneToGo) : session.t(.challengeManyToGo, remaining)
        case .challengeComplete:
            return session.t(.philChallengeComplete)
        case .needsAttention:
            return session.t(.philMissedOne)
        case .backOnTrack:
            return session.t(.philBackOnTrack)
        case .milestone(let days):
            return session.t(.philMilestoneDay, days)
        case .idle:
            if snapshot.isComplete {
                return session.t(.challengeStayedOnTrack)
            }
            if snapshot.currentStreak > 0 {
                return session.t(.streakKeepGoing)
            }
            return session.t(.philFirstDay)
        }
    }
}

struct TodaysChallengeCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    var onConfirmDose: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.t(.challengeTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                if snapshot.hasScheduledDoses {
                    Text(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                }
            }
            if !snapshot.hasScheduledDoses {
                Text(session.t(.challengeNoDosesToday))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else if snapshot.isComplete {
                Text(session.t(.challengeCompleteTitle))
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                Text(session.t(.challengeStayedOnTrack))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                progressBar
                ForEach(snapshot.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            guard !line.isTaken, !line.isMissed else { return }
                            onConfirmDose?(line.id)
                        } label: {
                            Image(systemName: line.isTaken ? "checkmark.circle.fill" : (line.isMissed ? "minus.circle" : "circle"))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(line.isTaken ? CheckMedTheme.primaryShadow : (line.isMissed ? CheckMedTheme.muted : CheckMedTheme.flowDot))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .disabled(line.isTaken || line.isMissed || onConfirmDose == nil)
                        .accessibilityLabel(session.t(.taken))
                        .accessibilityHint(line.isTaken || line.isMissed ? "" : session.t(.taken))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.medicine)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                            Text("\(line.time) · \(line.detail)")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(line.medicine), \(line.time), \(line.detail), \(line.isTaken ? session.t(.taken) : (line.isMissed ? session.t(.skipped) : session.t(.homeStatusPending)))")
                }
                if snapshot.remainingCount > 0, !snapshot.needsAttention {
                    Text(snapshot.remainingCount == 1 ? session.t(.challengeOneToGo) : session.t(.challengeManyToGo, snapshot.remainingCount))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                } else if snapshot.needsAttention {
                    Text(session.t(.philMissedOne))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.challengeTitle))
        .accessibilityValue(snapshot.hasScheduledDoses ? session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount) : session.t(.challengeNoDosesToday))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CheckMedTheme.hairline)
                Capsule()
                    .fill(CheckMedTheme.primary)
                    .frame(width: max(8, geo.size.width * CGFloat(snapshot.progressFraction)))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct JourneyGamificationCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    let history: [(day: Int, kind: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.t(.streakCurrent, snapshot.currentStreak))
                .font(.system(.title3, design: .rounded).weight(.black))
            Text(session.t(.streakLongest, snapshot.longestStreak))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(session.t(.milestonesTitle))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .textCase(.uppercase)
            ForEach(Gamification.milestoneDays, id: \.self) { day in
                HStack(spacing: 8) {
                    Image(systemName: snapshot.reachedMilestones.contains(day) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(snapshot.reachedMilestones.contains(day) ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    Text(milestoneTitle(day))
                        .font(.system(.body, design: .rounded).weight(.bold))
                    Spacer()
                }
                .accessibilityLabel("\(milestoneTitle(day)), \(snapshot.reachedMilestones.contains(day) ? session.t(.taken) : session.t(.homeStatusUpcoming))")
            }
            if !history.isEmpty {
                Text(session.t(.dailyHistoryTitle))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                    .textCase(.uppercase)
                HStack(spacing: 6) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, cell in
                        Circle()
                            .fill(historyColor(cell.kind))
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("\(cell.day), \(cell.kind)")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func milestoneTitle(_ day: Int) -> String {
        switch day {
        case 1: session.t(.milestoneStarted)
        case 3: session.t(.milestone3Days)
        case 7: session.t(.milestoneWeek)
        case 14: session.t(.milestoneTwoWeeks)
        case 21: session.t(.milestoneHabit)
        case 30: session.t(.milestone30)
        case 60: session.t(.milestone60)
        case 90: session.t(.milestone90)
        default: session.t(.philMilestoneDay, day)
        }
    }

    private func historyColor(_ kind: String) -> Color {
        switch kind {
        case "done": CheckMedTheme.primary
        case "miss": CheckMedTheme.muted.opacity(0.45)
        case "today": CheckMedTheme.flowDot
        default: CheckMedTheme.hairline
        }
    }
}

struct GamificationCelebrateBanner: View {
    @Environment(SessionStore.self) private var session
    let event: GameCelebrate
    let streak: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PhilView(size: 56, mood: .celebrate, smiling: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Text(subtitle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private var title: String {
        switch event {
        case .took(let name): session.t(.philNiceTook, name)
        case .dayComplete: session.t(.challengeCompleteTitle)
        case .milestone(let day): session.t(.philMilestoneDay, day)
        case .needsAttention: session.t(.philMissedOne)
        case .backOnTrack: session.t(.philBackOnTrack)
        }
    }

    private var subtitle: String {
        switch event {
        case .took: session.t(.streakKeepGoing)
        case .dayComplete: session.t(.challengeStayedOnTrack)
        case .milestone: session.t(.streakKeepGoing)
        case .needsAttention: session.t(.philBackOnTrack)
        case .backOnTrack: session.t(.streakKeepGoing)
        }
    }
}
