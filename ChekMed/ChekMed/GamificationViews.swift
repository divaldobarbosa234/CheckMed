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
        case .challengeComplete, .milestone, .backOnTrack: .complete
        default: .idle
        }
    }

    private var coachLine: String {
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

/// Compact day-status card. Navigation only — never confirms doses or presents Phil.
struct DailyMedicationJourneyCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let journey: DailyMedicationJourneySnapshot
    var streakDays: Int = 0
    var onFocusChallenge: (() -> Void)? = nil

    private var journeyAction: DailyMedicationJourney.Action? {
        DailyMedicationJourney.action(for: journey.state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PhilView(size: 56, mood: philMood, smiling: journey.state == .complete || journey.state == .inProgress || journey.state == .almostComplete)
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.t(.journeyHowToday))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.muted)
                        .textCase(.uppercase)
                    HStack(spacing: 6) {
                        Image(systemName: stateSymbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accent)
                        Text(stateTitle)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                    }
                    Text(stateMessage)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if journey.todayTotal > 0 {
                        progressBar
                        Text(session.t(.challengeProgress, journey.todayTaken, journey.todayTotal))
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                    }
                    if let next = journey.nextDose, journey.state != .complete, journey.state != .missed {
                        Text(session.t(.journeyNextMedicine, next.time, next.medicine))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.flowDot)
                    }
                    if streakDays > 0 {
                        Text("🔥 \(session.t(.streakCurrent, streakDays))")
                            .font(.system(.caption2, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                    }
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(.isStaticText)

            if let journeyAction, onFocusChallenge != nil {
                CheckMedButton(title: actionTitle(journeyAction), style: .secondary) {
                    #if DEBUG
                    print("[JOURNEY-DIAG] ACTION state=\(journey.state) action=\(journeyAction) destination=todays-challenge")
                    #endif
                    onFocusChallenge?()
                }
                .accessibilityLabel(actionTitle(journeyAction))
                .accessibilityHint(session.t(.journeyActionHint))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1.5)
        )
        .frame(minHeight: 120, alignment: .top)
    }

    private func actionTitle(_ action: DailyMedicationJourney.Action) -> String {
        switch action {
        case .viewChallenge: session.t(.journeyViewChallenge)
        case .continueChallenge: session.t(.journeyContinueChallenge)
        case .getBackOnTrack: session.t(.journeyGetBackOnTrack)
        }
    }

    private var philMood: CompanionMood {
        switch journey.state {
        case .complete: .complete
        case .missed: .idle
        default: .idle
        }
    }

    private var stateSymbol: String {
        switch journey.state {
        case .noTreatment: "doc.text.viewfinder"
        case .startingDay: "sunrise.fill"
        case .upcoming: "clock.fill"
        case .inProgress: "checkmark.circle.fill"
        case .missed: "heart.circle.fill"
        case .almostComplete: "flag.fill"
        case .complete: "star.circle.fill"
        }
    }

    private var accent: Color {
        switch journey.state {
        case .noTreatment: CheckMedTheme.muted
        case .startingDay: CheckMedTheme.flowDot
        case .upcoming: CheckMedTheme.current
        case .inProgress: CheckMedTheme.primaryShadow
        case .missed: CheckMedTheme.flowDot
        case .almostComplete: CheckMedTheme.primary
        case .complete: CheckMedTheme.primaryShadow
        }
    }

    private var stateTitle: String {
        switch journey.state {
        case .noTreatment: session.t(.journeyStateNone)
        case .startingDay: session.t(.journeyStateStarting)
        case .upcoming: session.t(.journeyStateUpcoming)
        case .inProgress: session.t(.journeyStateOnTrack)
        case .missed: session.t(.journeyStateMissed)
        case .almostComplete: session.t(.journeyStateAlmost)
        case .complete: session.t(.journeyStateComplete)
        }
    }

    private var stateMessage: String {
        switch journey.state {
        case .noTreatment: session.t(.journeyNoTreatment)
        case .startingDay: session.t(.journeyStarting)
        case .upcoming: session.t(.journeyNextComing)
        case .inProgress: session.t(.journeyOnTrack)
        case .missed:
            journey.missedCount <= 1
                ? session.t(.philMissedOne)
                : session.t(.philMissedSeveral, journey.missedCount)
        case .almostComplete: session.t(.journeyAlmostThere)
        case .complete: session.t(.journeyDayComplete)
        }
    }

    private var progressFraction: Double {
        guard journey.todayTotal > 0 else { return 0 }
        return Double(journey.todayTaken) / Double(journey.todayTotal)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CheckMedTheme.hairline)
                Capsule()
                    .fill(accent)
                    .frame(width: max(8, geo.size.width * CGFloat(progressFraction)))
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: journey.todayTaken)
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        let progress = journey.todayTotal > 0
            ? session.t(.journeyA11yProgress, journey.todayTaken, journey.todayTotal)
            : session.t(.journeyNoTreatment)
        return "\(session.t(.journeyHowToday)). \(stateTitle). \(progress). \(stateMessage)"
    }
}

struct TodaysChallengeCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    var highlightedDoseId: String? = nil
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
                if snapshot.lines.contains(where: \.isTakenLate) {
                    Text(session.t(.homeTakenLateHint))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.flowDot)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                progressBar
            }
            if snapshot.hasScheduledDoses, !snapshot.isComplete {
                ForEach(snapshot.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            guard !line.isTaken else { return }
                            onConfirmDose?(line.id)
                        } label: {
                            Image(systemName: line.isTaken ? "checkmark.circle.fill" : (line.isMissed ? "minus.circle" : "circle"))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(line.isTaken ? CheckMedTheme.primaryShadow : (line.isMissed ? CheckMedTheme.muted : CheckMedTheme.flowDot))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .disabled(line.isTaken || onConfirmDose == nil)
                        .accessibilityLabel(session.t(.taken))
                        .accessibilityHint(line.isTaken ? "" : session.t(line.isMissed ? .missedTookItLater : .taken))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.medicine)
                                .font(.system(.body, design: .rounded).weight(.heavy))
                            Text("\(line.time) · \(line.detail)")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(CheckMedTheme.muted)
                            if line.isTakenLate {
                                Text(session.t(.homeTakenLateHint))
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(CheckMedTheme.flowDot)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .background {
                        if line.id == highlightedDoseId {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(CheckMedTheme.mintWash)
                        }
                    }
                    .id(line.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(line.medicine), \(line.time), \(line.detail), \(line.isTakenLate ? session.t(.homeTakenLate) : (line.isTaken ? session.t(.taken) : (line.isMissed ? session.t(.skipped) : session.t(.homeStatusPending))))")
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

/// Read-only Dashboard weekly card. Day statuses come from canonical DoseLogs; streak from `AdherenceSnapshot`.
struct WeeklyAdherenceCard: View {
    @Environment(SessionStore.self) private var session
    let stats: AdherenceSnapshot
    var weekly: DoseLoop.WeeklyMedicationProgressSnapshot = .empty
    let snapshot: GamificationSnapshot
    let hasUpcomingDose: Bool
    var onTreatments: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.t(.weeklyYourWeek))
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
                .accessibilityLabel(session.t(.streakCurrent, stats.streakDays))
            }

            if !weekly.days.isEmpty {
                weeklyDayRow
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(CheckMedTheme.hairline, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: weekFraction)
                        .stroke(CheckMedTheme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(percentLabel)
                        .font(.system(.title2, design: .rounded).weight(.black))
                }
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    if weekly.applicableDays > 0 {
                        Text(session.t(.weeklyDaysComplete, weekly.completedDays, weekly.applicableDays))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        if let percent = displayedPercent {
                            Text(session.t(.weeklyAdherencePercent, percent))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    } else {
                        Text(session.t(.progressDosesTaken, stats.weekTaken, stats.weekPlanned))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    }
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
        .accessibilityLabel(session.t(.weeklyYourWeek))
        .accessibilityValue(accessibilitySummary)
    }

    private var weeklyDayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekly.days.enumerated()), id: \.offset) { _, day in
                weeklyDayCell(day)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func weeklyDayCell(_ day: DoseLoop.WeeklyDaySnapshot) -> some View {
        VStack(spacing: 6) {
            Text(weekdayLabel(for: day.weekdayIndex))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(day.isToday ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
            Text(symbol(for: day.status))
                .font(.system(.body, design: .rounded).weight(.black))
                .foregroundStyle(symbolColor(for: day.status))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(day.isToday ? CheckMedTheme.mintWash : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day))
    }

    private func weekdayLabel(for mondayIndex: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = session.locale.foundationLocale
        let names = cal.shortWeekdaySymbols
        guard names.count == 7 else { return "" }
        let ordered = Array(names[1...6]) + [names[0]]
        guard mondayIndex >= 0, mondayIndex < ordered.count else { return "" }
        return ordered[mondayIndex]
    }

    private func weekdayName(for mondayIndex: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = session.locale.foundationLocale
        let names = cal.weekdaySymbols
        guard names.count == 7 else { return "" }
        let ordered = Array(names[1...6]) + [names[0]]
        guard mondayIndex >= 0, mondayIndex < ordered.count else { return "" }
        return ordered[mondayIndex]
    }

    private func symbol(for status: DoseLoop.WeeklyDayStatus) -> String {
        switch status {
        case .complete: "✓"
        case .incomplete: "!"
        case .future: "•"
        case .notApplicable, .noScheduledDoses: "—"
        }
    }

    private func symbolColor(for status: DoseLoop.WeeklyDayStatus) -> Color {
        switch status {
        case .complete: CheckMedTheme.primaryShadow
        case .incomplete: CheckMedTheme.danger
        case .future: CheckMedTheme.muted
        case .notApplicable, .noScheduledDoses: CheckMedTheme.hairline
        }
    }

    private func statusPhrase(_ day: DoseLoop.WeeklyDaySnapshot) -> String {
        switch day.status {
        case .complete: session.t(.weeklyDayComplete)
        case .incomplete: session.t(.weeklyDayMissed)
        case .future: session.t(.weeklyDayUpcoming)
        case .notApplicable: session.t(.weeklyDayNotApplicable)
        case .noScheduledDoses: session.t(.weeklyDayNoDoses)
        }
    }

    private func dayAccessibilityLabel(_ day: DoseLoop.WeeklyDaySnapshot) -> String {
        var parts = [weekdayName(for: day.weekdayIndex)]
        if day.isToday {
            parts.append(session.t(.weeklyDayToday))
            if day.scheduledCount > 0 {
                parts.append(session.t(.weeklyDayDosesCompleted, day.completedCount, day.scheduledCount))
            }
        }
        parts.append(statusPhrase(day))
        return parts.joined(separator: ", ")
    }

    private var displayedPercent: Int? {
        weekly.adherencePercentage ?? stats.weekPercent
    }

    private var percentLabel: String {
        guard let percent = displayedPercent else { return "—" }
        return "\(percent)%"
    }

    private var accessibilitySummary: String {
        if weekly.applicableDays > 0 {
            var parts = [session.t(.weeklyDaysComplete, weekly.completedDays, weekly.applicableDays)]
            if let percent = displayedPercent {
                parts.append(session.t(.weeklyAdherencePercent, percent))
            }
            parts.append(session.t(.streakCurrent, stats.streakDays))
            return parts.joined(separator: ", ")
        }
        return session.t(.progressDosesTaken, stats.weekTaken, stats.weekPlanned)
    }

    private var weekFraction: CGFloat {
        guard let percent = displayedPercent else { return 0 }
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
        case .firstDay: session.t(.philFirstDay)
        case .tookFirst: session.t(.philDoseFirst)
        case .tookOnTrack: session.t(.philDoseOnTrack)
        case .tookKeepGoing: session.t(.philDoseKeepGoing)
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
        case .firstDay: session.t(.philDoseFirst)
        case .tookFirst: session.t(.streakKeepGoing)
        case .tookOnTrack: session.t(.philDoseKeepGoing)
        case .tookKeepGoing: session.t(.streakKeepGoing)
        case .dayComplete: session.t(.philChallengeComplete)
        case .milestone(1): session.t(.streakKeepGoing)
        case .milestone(3), .milestone(7): session.t(.challengeStayedOnTrack)
        case .milestone: session.t(.streakKeepGoing)
        case .needsAttention: session.t(.journeyGetBackOnTrack)
        case .backOnTrack: session.t(.streakKeepGoing)
        }
    }

    private var bannerMood: CompanionMood {
        switch event {
        case .needsAttention: .idle
        case .tookFirst, .tookOnTrack, .tookKeepGoing, .firstDay: .complete
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

/// Read-only Your Progress gallery. Does not award grants or write RewardGrant.
struct AchievementGallerySection: View {
    @Environment(SessionStore.self) private var session
    let items: [RewardCatalog.AchievementGalleryItem]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.t(.achievementsTitle))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { item in
                    AchievementGalleryTile(item: item)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.achievementsTitle))
    }
}

private struct AchievementGalleryTile: View {
    @Environment(SessionStore.self) private var session
    let item: RewardCatalog.AchievementGalleryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                badge
                Spacer(minLength: 0)
                Image(systemName: item.isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(item.isUnlocked ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    .accessibilityHidden(true)
            }
            Text(session.t(titleKey))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink.opacity(item.isUnlocked ? 1 : 0.78))
                .fixedSize(horizontal: false, vertical: true)
            Text(session.t(bodyKey))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(statusLine)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(item.isUnlocked ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    item.isUnlocked ? CheckMedTheme.primary.opacity(0.55) : CheckMedTheme.hairline,
                    lineWidth: item.isUnlocked ? 2 : 1.5
                )
        )
        .opacity(item.isUnlocked ? 1 : 0.88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.isUnlocked ? CheckMedTheme.belly : CheckMedTheme.background)
            Image(systemName: RewardCatalog.gallerySymbolName(for: item.achievement))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(item.isUnlocked ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 40, height: 40)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var statusLine: String {
        if item.isUnlocked, let unlockedAt = item.unlockedAt {
            return session.t(.achievementUnlockedOn, unlockedDateText(unlockedAt))
        }
        return session.t(item.isUnlocked ? .achievementUnlocked : .achievementLocked)
    }

    private var accessibilitySummary: String {
        let name = session.t(titleKey)
        let state = session.t(item.isUnlocked ? .achievementUnlocked : .achievementLocked)
        let detail = session.t(bodyKey)
        if item.isUnlocked, let unlockedAt = item.unlockedAt {
            return "\(name). \(state). \(detail). \(session.t(.achievementUnlockedOn, unlockedDateText(unlockedAt)))"
        }
        return "\(name). \(state). \(detail)"
    }

    private func unlockedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = session.locale.foundationLocale
        formatter.calendar = session.foundationCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var titleKey: L10n.Key {
        switch item.achievement {
        case .firstDose: .achievementTitleFirstDose
        case .firstDay: .achievementTitleFirstDay
        case .firstRecovery: .achievementTitleFirstRecovery
        case .firstTreatmentComplete: .achievementTitleFirstTreatment
        case .streak1: .achievementTitleStreak1
        case .streak3: .achievementTitleStreak3
        case .streak7: .achievementTitleStreak7
        case .streak14: .achievementTitleStreak14
        case .streak30: .achievementTitleStreak30
        case .streak90: .achievementTitleStreak90
        }
    }

    private var bodyKey: L10n.Key {
        switch item.achievement {
        case .firstDose: .achievementBodyFirstDose
        case .firstDay: .achievementBodyFirstDay
        case .firstRecovery: .achievementBodyFirstRecovery
        case .firstTreatmentComplete: .achievementBodyFirstTreatment
        case .streak1: .achievementBodyStreak1
        case .streak3: .achievementBodyStreak3
        case .streak7: .achievementBodyStreak7
        case .streak14: .achievementBodyStreak14
        case .streak30: .achievementBodyStreak30
        case .streak90: .achievementBodyStreak90
        }
    }
}
