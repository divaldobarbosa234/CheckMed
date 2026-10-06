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
        HStack(spacing: 2) {
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
                    .frame(maxWidth: .infinity, minHeight: 58)
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
        .padding(4)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.05), radius: 10, y: 4)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.t(.homeTodayTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                Text(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            HStack(alignment: .center, spacing: 10) {
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
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(session.t(.challengeProgress, snapshot.takenCount, snapshot.requiredCount))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.lines) { line in
                        doseRow(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
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
                    .frame(width: 18)
                Text(line.time)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 40, alignment: .leading)
                Text(line.medicine)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CheckMedTheme.onPrimary)
                    .frame(width: 46, height: 46)
                    .background(CheckMedTheme.flowDot, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.homeNextDose))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.time)
                            .font(.system(.title3, design: .rounded).weight(.black))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(line.medicine)
                            Text(line.detail)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                HomeCapsuleMark()
                    .frame(width: 62, height: 62)
                    .background(CheckMedTheme.flowDot.opacity(0.08), in: Circle())
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 90)
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
        HStack(spacing: 0) {
            CheckMedTheme.flowDot
            Color.white
        }
        .frame(width: 42, height: 20)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(CheckMedTheme.flowDot.opacity(0.35), lineWidth: 1))
        .rotationEffect(.degrees(-45))
        .shadow(color: CheckMedTheme.flowDot.opacity(0.2), radius: 4, y: 2)
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
            HStack(alignment: .center, spacing: 10) {
                PhilDoctor2DImage(size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(bodyLine)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 88)
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
        if snapshot.coach == .needsAttention { return session.t(.homeCooperCheer) }
        if snapshot.isComplete { return session.t(.youDidIt) }
        return session.t(.homeYoureDoingWell)
    }

    private var bodyLine: String {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(session.t(.homePrimaryActions))
                .font(.system(.headline, design: .rounded).weight(.heavy))
            HStack(spacing: 8) {
                tile(title: session.t(.homeScan), icon: "camera.fill", wash: CheckMedTheme.mintWash, tint: Color(hex: 0x5FA86B), action: onScan)
                tile(title: session.t(.progressCalendar), icon: "calendar", wash: CheckMedTheme.lavenderWash, tint: Color(hex: 0x9B7ED9), action: onCalendar)
                tile(title: session.t(.myProgress), icon: "chart.bar.fill", wash: CheckMedTheme.sunshineWash, tint: CheckMedTheme.current, action: onProgress)
            }
        }
    }

    private func tile(title: String, icon: String, wash: Color, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .background(wash.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(10)
            }
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
