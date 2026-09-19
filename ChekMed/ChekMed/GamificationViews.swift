import SwiftUI

struct GamificationStreakCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    var journey: DailyMedicationJourneySnapshot? = nil

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
        case .challengeComplete, .milestone, .backOnTrack: .complete
        default: .idle
        }
    }

    private var coachLine: String {
        if let journey {
            switch journey.state {
            case .noTreatment:
                return session.t(.journeyAllSet)
            case .startingDay:
                return session.t(.journeyReadyToday)
            case .upcoming:
                return session.t(.journeyNextComing)
            case .inProgress:
                return session.t(.journeyProgressToday, journey.todayTaken, journey.todayTotal)
            case .missed:
                return missedSupportLine
            case .almostComplete:
                return session.t(.journeyOneMore)
            case .complete:
                return session.t(.journeyDayComplete)
            }
        }
        switch snapshot.coach {
        case .upcoming:
            return session.t(.philReadyNext)
        case .inProgress(let remaining):
            return remaining == 1 ? session.t(.philDoingWellOne) : session.t(.philDoingWellMany, remaining)
        case .challengeComplete, .milestone:
            return session.t(.philDayDosesComplete)
        case .needsAttention:
            return missedSupportLine
        case .backOnTrack:
            return session.t(.philBackOnTrack)
        case .firstDay:
            return snapshot.hasScheduledDoses ? session.t(.philReadyNext) : session.t(.philFirstDay)
        case .idle:
            if snapshot.isComplete {
                return session.t(.philDayDosesComplete)
            }
            if snapshot.remainingCount > 0, snapshot.takenCount == 0 {
                return session.t(.philReadyNext)
            }
            if snapshot.remainingCount > 0 {
                return snapshot.remainingCount == 1
                    ? session.t(.philDoingWellOne)
                    : session.t(.philDoingWellMany, snapshot.remainingCount)
            }
            return session.t(.streakKeepGoing)
        }
    }

    private var missedSupportLine: String {
        snapshot.skippedCount <= 1
            ? session.t(.philMissedOne)
            : session.t(.philMissedSeveral, snapshot.skippedCount)
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
            }
            if snapshot.hasScheduledDoses, !snapshot.isComplete {
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
                    Text(missedSupportLine)
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
        .frame(minHeight: reservedHeight, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.challengeTitle))
        .accessibilityValue(snapshot.hasScheduledDoses ? session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount) : session.t(.challengeNoDosesToday))
    }

    /// Keep this card’s slot even when path nodes have not arrived yet, so the
    /// week section cannot jump into the Challenge position.
    private var reservedHeight: CGFloat {
        let header: CGFloat = 108
        guard snapshot.hasScheduledDoses else { return header }
        if snapshot.isComplete { return 148 }
        let rows = max(snapshot.lines.count, snapshot.requiredCount)
        return header + CGFloat(rows) * 46
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

    private var missedSupportLine: String {
        snapshot.skippedCount <= 1
            ? session.t(.philMissedOne)
            : session.t(.philMissedSeveral, snapshot.skippedCount)
    }
}

/// Read-only Dashboard/Progress card. Values come from an existing `AdherenceSnapshot`.
struct WeeklyAdherenceCard: View {
    @Environment(SessionStore.self) private var session
    let stats: AdherenceSnapshot
    let snapshot: GamificationSnapshot
    let hasUpcomingDose: Bool
    var onTreatments: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.t(.progressWeekTitle))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Text(session.t(.progressKeepGoing))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("🔥")
                    Text(session.t(.streakCurrent, stats.streakDays))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CheckMedTheme.belly, in: Capsule())
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(CheckMedTheme.hairline, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: weekFraction)
                        .stroke(CheckMedTheme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(stats.weekPercent ?? 0)%")
                        .font(.system(.title2, design: .rounded).weight(.black))
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.t(.progressDosesTaken, stats.weekTaken, stats.weekPlanned))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    HStack(spacing: 6) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(hasUpcomingDose ? session.t(.progressNextSoon) : session.t(.todayNothing))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                    }
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CheckMedTheme.mintWash, in: Capsule())
                }

                Spacer(minLength: 0)
                Button {
                    onTreatments?()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "pills.fill")
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                        Text("\(stats.treatmentCount)")
                            .font(.system(.title3, design: .rounded).weight(.black))
                        Text(session.t(.progressTreatmentsLabel))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(10)
                    .frame(width: 86)
                    .background(CheckMedTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(onTreatments == nil)
            }

            if stats.treatmentCount > 0 {
                Divider().overlay(CheckMedTheme.hairline)
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.t(.progressTreatmentsHeader))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .textCase(.uppercase)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                        Text(session.t(.progressTreatmentStarted))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    }
                    HStack(spacing: 6) {
                        Text("🔥")
                        Text(session.t(.streakCurrent, stats.streakDays))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    }
                    Text(stats.longestStreakDays == 1
                         ? session.t(.streakLongestOne)
                         : session.t(.streakLongest, stats.longestStreakDays))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.t(.milestonesTitle))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .textCase(.uppercase)
                    ForEach(Gamification.milestoneDays, id: \.self) { day in
                        let reached = stats.streakDays >= day
                        let focusDay = Gamification.milestoneDays.last { stats.streakDays >= $0 } ?? Gamification.milestoneDays.first { $0 > stats.streakDays }
                        HStack(spacing: 8) {
                            Image(systemName: reached ? "checkmark.circle.fill" : "lock.fill")
                                .foregroundStyle(reached ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                                .accessibilityHidden(true)
                            Text(GamificationMilestoneCopy.title(day, session: session))
                                .font(.system(.subheadline, design: .rounded).weight(day == focusDay ? .black : .semibold))
                            Spacer()
                        }
                        .accessibilityLabel("\(GamificationMilestoneCopy.title(day, session: session)), \(reached ? session.t(.taken) : session.t(.homeStatusUpcoming))")
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
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.progressWeekTitle))
        .accessibilityValue(session.t(.progressDosesTaken, stats.weekTaken, stats.weekPlanned))
    }

    private var weekFraction: CGFloat {
        guard let percent = stats.weekPercent else { return 0 }
        return CGFloat(percent) / 100
    }
}

enum GamificationMilestoneCopy {
    static func title(_ day: Int, session: SessionStore) -> String {
        switch day {
        case 1: session.t(.milestoneStarted)
        case 3: session.t(.milestone3Days)
        case 7: session.t(.milestoneWeek)
        case 14: session.t(.milestoneTwoWeeks)
        case 21: session.t(.milestoneThreeWeeks)
        case 30: session.t(.milestone30)
        case 60: session.t(.milestone60)
        case 90: session.t(.milestone90)
        default: session.t(.philMilestoneDay, day)
        }
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
            Text(snapshot.longestStreak == 1
                 ? session.t(.streakLongestOne)
                 : session.t(.streakLongest, snapshot.longestStreak))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            Text(session.t(.milestonesTitle))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .textCase(.uppercase)
            ForEach(Gamification.milestoneDays, id: \.self) { day in
                let reached = snapshot.reachedMilestones.contains(day)
                let focus = snapshot.reachedMilestones.last ?? snapshot.nextMilestone
                let current = day == focus
                HStack(spacing: 8) {
                    Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(reached ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    Text(GamificationMilestoneCopy.title(day, session: session))
                        .font(.system(.body, design: .rounded).weight(current ? .black : .bold))
                        .foregroundStyle(current ? CheckMedTheme.ink : CheckMedTheme.ink.opacity(reached ? 1 : 0.72))
                    Spacer()
                }
                .accessibilityLabel("\(GamificationMilestoneCopy.title(day, session: session)), \(reached ? session.t(.taken) : session.t(.homeStatusUpcoming))")
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
    var missedCount: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PhilView(size: eventScale, mood: bannerMood, smiling: true)
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
        case .tookFirst, .tookOnTrack, .tookKeepGoing: session.t(.philDoseTaken)
        case .dayComplete: session.t(.philDayDosesComplete)
        case .milestone(let day):
            switch day {
            case 1: session.t(.philMilestone1)
            case 3: session.t(.philMilestone3)
            case 7: session.t(.philMilestone7)
            default: session.t(.philMilestoneDay, day)
            }
        case .needsAttention:
            missedCount <= 1 ? session.t(.philMissedOne) : session.t(.philMissedSeveral, missedCount)
        case .backOnTrack: session.t(.philBackOnTrack)
        }
    }

    private var subtitle: String {
        switch event {
        case .tookFirst, .tookOnTrack, .tookKeepGoing: session.t(.streakKeepGoing)
        case .dayComplete: session.t(.philChallengeComplete)
        case .milestone(1): session.t(.streakKeepGoing)
        case .milestone(3), .milestone(7): session.t(.challengeStayedOnTrack)
        case .milestone: session.t(.streakKeepGoing)
        case .needsAttention: session.t(.philBackOnTrack)
        case .backOnTrack: session.t(.streakKeepGoing)
        }
    }

    private var bannerMood: CompanionMood {
        switch event {
        case .needsAttention: .idle
        case .tookFirst, .tookOnTrack, .tookKeepGoing: .complete
        default: .complete
        }
    }

    private var eventScale: CGFloat {
        switch event {
        case .dayComplete, .milestone: 64
        default: 56
        }
    }
}
