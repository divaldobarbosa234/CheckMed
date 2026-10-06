import SwiftUI

/// Home vs Progress occupancy. Read-only classification from existing Journey Tree + today's schedule.
enum HomePlanPresentation: Equatable {
    case restoring
    case noTreatment
    case completed
    case futureOnly
    case activeQuietDay
    case activeToday
}

enum HomePlanPresentationMapper {
    static func occupancy(
        planReady: Bool,
        tree: CheckMedStore.JourneyTreeSnapshot,
        hasScheduledToday: Bool
    ) -> HomePlanPresentation {
        guard planReady else { return .restoring }
        if !tree.current.isEmpty {
            return hasScheduledToday ? .activeToday : .activeQuietDay
        }
        if !tree.future.isEmpty { return .futureOnly }
        if !tree.past.isEmpty { return .completed }
        return .noTreatment
    }
}

/// Compact week orientation. Uses canonical weekly snapshots when present; otherwise calendar days only.
struct ConnyWeekStrip: View {
    @Environment(SessionStore.self) private var session
    let days: [DoseLoop.WeeklyDaySnapshot]
    var emphasizesToday: Bool = true
    var onSelectDay: ((DoseLoop.WeeklyDaySnapshot) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Button {
                    onSelectDay?(day)
                } label: {
                    VStack(spacing: 4) {
                        Text(weekdayLabel(day.date))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text(dayNumber(day.date))
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    }
                    .foregroundStyle(day.isToday && emphasizesToday ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(day.isToday && emphasizesToday ? CheckMedTheme.flowDot : CheckMedTheme.surface)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weeklyA11y(day))
                .disabled(onSelectDay == nil)
            }
        }
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = session.locale.foundationLocale
        formatter.calendar = session.foundationCalendar
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let day = session.foundationCalendar.component(.day, from: date)
        return "\(day)"
    }

    private func weeklyA11y(_ day: DoseLoop.WeeklyDaySnapshot) -> String {
        let stamp = weekdayLabel(day.date) + " " + dayNumber(day.date)
        if day.isToday { return "\(stamp). \(session.t(.weeklyDayToday))" }
        return stamp
    }

    static func days(
        from weekly: DoseLoop.WeeklyMedicationProgressSnapshot,
        calendar: Calendar,
        now: Date = Date()
    ) -> [DoseLoop.WeeklyDaySnapshot] {
        if weekly.days.count == 7 { return weekly.days }
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset -> DoseLoop.WeeklyDaySnapshot? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DoseLoop.WeeklyDaySnapshot(
                date: date,
                weekdayIndex: calendar.component(.weekday, from: date),
                status: .noScheduledDoses,
                scheduledCount: 0,
                takenCount: 0,
                takenLateCount: 0,
                missedCount: 0,
                completedCount: 0,
                isToday: calendar.isDateInToday(date)
            )
        }
    }
}

struct HomeTodayProgressCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    var highlightedDoseId: String? = nil
    var onConfirmDose: ((String) -> Void)? = nil
    var onMissed: (() -> Void)? = nil

    private var fraction: CGFloat {
        guard snapshot.requiredCount > 0 else { return 0 }
        return CGFloat(snapshot.takenCount) / CGFloat(snapshot.requiredCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.t(.homeTodayTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                Text(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(CheckMedTheme.hairline, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(CheckMedTheme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(.title2, design: .rounded).weight(.black))
                        Text(session.t(.homeDosesOfTotal, snapshot.takenCount, snapshot.requiredCount))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 88)
                }
                .frame(width: 108, height: 108)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.lines) { line in
                        doseRow(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
    }

    private func doseRow(_ line: ChallengeDoseLine) -> some View {
        Button {
            if line.isMissed {
                onMissed?()
                return
            }
            guard !line.isTaken else { return }
            onConfirmDose?(line.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: rowSymbol(line))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(rowTint(line))
                    .frame(width: 22)
                Text(line.time)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 44, alignment: .leading)
                Text(line.medicine)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background {
                if line.id == highlightedDoseId {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CheckMedTheme.mintWash)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(line.isTaken && !line.isMissed)
        .id(line.id)
        .accessibilityLabel("\(line.medicine), \(line.time), \(line.detail), \(statusLabel(line))")
    }

    private func rowSymbol(_ line: ChallengeDoseLine) -> String {
        if line.isTaken { return "checkmark.circle.fill" }
        if line.isMissed { return "minus.circle.fill" }
        return "clock.fill"
    }

    private func rowTint(_ line: ChallengeDoseLine) -> Color {
        if line.isTaken { return CheckMedTheme.primaryShadow }
        if line.isMissed { return CheckMedTheme.danger }
        return CheckMedTheme.flowDot
    }

    private func statusLabel(_ line: ChallengeDoseLine) -> String {
        if line.isTakenLate { return session.t(.homeTakenLate) }
        if line.isTaken { return session.t(.taken) }
        if line.isMissed { return session.t(.skipped) }
        return session.t(.homeStatusPending)
    }
}

struct HomeNextDoseCard: View {
    @Environment(SessionStore.self) private var session
    let line: ChallengeDoseLine
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckMedTheme.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(CheckMedTheme.flowDot, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.homeNextDose))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    Text(line.time)
                        .font(.system(.title3, design: .rounded).weight(.black))
                    Text("\(line.medicine) · \(line.detail)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HomeCapsuleMark()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.blueWash.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Decorative two-tone medicine capsule — not achievement artwork, not a toggle.
private struct HomeCapsuleMark: View {
    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 36, height: 18)
            .overlay {
                HStack(spacing: 0) {
                    CheckMedTheme.flowDot
                    Color.white
                }
                .clipShape(Capsule())
            }
            .overlay(
                Capsule().stroke(CheckMedTheme.flowDot.opacity(0.35), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

struct HomeEncouragementCard: View {
    @Environment(SessionStore.self) private var session
    let snapshot: GamificationSnapshot
    var remaining: Int
    var onOpen: (() -> Void)? = nil

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                PhilDoctor2DImage(size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(bodyLine)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [CheckMedTheme.lavenderWash, CheckMedTheme.blueWash],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }

    private var headline: String {
        if snapshot.coach == .needsAttention { return session.t(.philBackOnTrack) }
        if snapshot.isComplete { return session.t(.youDidIt) }
        return session.t(.homeYoureDoingWell)
    }

    private var bodyLine: String {
        if snapshot.coach == .needsAttention {
            return snapshot.skippedCount <= 1
                ? session.t(.philMissedOne)
                : session.t(.philMissedSeveral, snapshot.skippedCount)
        }
        if snapshot.isComplete { return session.t(.philDayDosesComplete) }
        if remaining == 1 { return session.t(.philDoingWellOne) }
        if remaining > 1 { return session.t(.philDoingWellMany, remaining) }
        return session.t(.philReadyNext)
    }
}

struct HomePrimaryActionsRow: View {
    @Environment(SessionStore.self) private var session
    var onScan: () -> Void
    var onCalendar: () -> Void
    var onProgress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.homePrimaryActions))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            HStack(spacing: 10) {
                tile(title: session.t(.homeScan), icon: "camera.fill", wash: CheckMedTheme.mintWash, tint: Color(hex: 0x5FA86B), action: onScan)
                tile(title: session.t(.progressCalendar), icon: "calendar", wash: CheckMedTheme.lavenderWash, tint: Color(hex: 0x9B7ED9), action: onCalendar)
                tile(title: session.t(.myProgress), icon: "chart.bar.fill", wash: CheckMedTheme.sunshineWash, tint: CheckMedTheme.current, action: onProgress)
            }
        }
    }

    private func tile(title: String, icon: String, wash: Color, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack {
                    Text(title)
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(wash.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct HomeStatusCard: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let bodyText: String
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PhilDoctor2DImage(size: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    Text(bodyText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            CheckMedButton(title: primaryTitle, action: primaryAction)
            if let secondaryTitle, let secondaryAction {
                CheckMedButton(title: secondaryTitle, style: .secondary, action: secondaryAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
    }
}
