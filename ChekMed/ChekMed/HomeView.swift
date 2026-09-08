import SwiftUI

private enum HomeDailyMood: String, CaseIterable, Identifiable {
    case great, good, okay, notGreat, bad

    var id: String { rawValue }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .great: session.t(.homeMoodGreat)
        case .good: session.t(.homeMoodGood)
        case .okay: session.t(.homeMoodOkay)
        case .notGreat: session.t(.homeMoodNotGreat)
        case .bad: session.t(.homeMoodBad)
        }
    }

    var symbol: String {
        switch self {
        case .great: "😄"
        case .good: "🙂"
        case .okay: "😐"
        case .notGreat: "🙁"
        case .bad: "😣"
        }
    }

    var tint: Color {
        switch self {
        case .great: Color(hex: 0x5FA86B)
        case .good: Color(hex: 0x8FBF7A)
        case .okay: CheckMedTheme.primary
        case .notGreat: CheckMedTheme.current
        case .bad: CheckMedTheme.danger
        }
    }

    var wash: Color { tint.opacity(0.18) }
}

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @Environment(CheckMedStore.self) private var treatments
    @State private var navPath = NavigationPath()
    @State private var dailyMood: HomeDailyMood?

    private var greetingWord: String {
        let hour = session.foundationCalendar.component(.hour, from: Date())
        switch hour {
        case 5..<12: return session.t(.homeMorning)
        case 12..<18: return session.t(.homeAfternoon)
        default: return session.t(.homeEvening)
        }
    }

    private var greetingName: String {
        let raw = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        if raw.isEmpty || lowered == "there" || lowered == "friend" {
            return session.t(.homeFriendName)
        }
        return raw.split(separator: " ").first.map(String.init) ?? raw
    }

    private var todayStamp: String {
        let comps = session.foundationCalendar.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private var remainingCount: Int {
        path.nodes.filter { $0.status == .current || $0.status == .locked }.count
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    moodCard
                    medicationsCard
                    if let days = treatments.daysUntilNextRevision(calendar: session.foundationCalendar), days >= 0 {
                        revisionCard(days: days)
                    }
                    quoteBanner
                    CheckMedButton(title: session.t(.homeScan)) {
                        navPath.append(AppRoute.addPrescription)
                    }
                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(navPath.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route, path: $navPath)
            }
            .onAppear {
                path.reload()
                dailyMood = HomeDailyMood(rawValue: UserDefaults.standard.string(forKey: moodKey) ?? "")
            }
            .sheet(item: feelingItem) { item in
                FeelingCheckInSheet(logId: item.logId, medicine: item.medicine)
            }
            .task {
                guard !session.needsUnfinishedPlan(treatments: treatments) else { return }
                guard session.shouldOfferOnboardingPaywall, !entitlements.isSuper else { return }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard !Task.isCancelled else { return }
                guard !session.needsUnfinishedPlan(treatments: treatments) else { return }
                guard session.shouldOfferOnboardingPaywall, !entitlements.isSuper else { return }
                session.markOnboardingPaywallOffered()
                entitlements.presentPaywall()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(session.t(.homeGreetingFormat, greetingWord, greetingName))
                        .font(.system(.title, design: .rounded).weight(.black))
                        .foregroundStyle(CheckMedTheme.ink)
                    Spacer(minLength: 8)
                    Button {
                        navPath.append(AppRoute.settings)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .frame(width: 36, height: 36)
                            .background(CheckMedTheme.surface, in: Circle())
                            .overlay(Circle().stroke(CheckMedTheme.hairline, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.t(.profileSettings))
                }
                Rectangle()
                    .fill(CheckMedTheme.primary)
                    .frame(width: 44, height: 4)
                    .clipShape(Capsule())
                Text(session.t(.homeFeelAsk))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Text(session.t(.homeFeelTogether))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                if family.isViewingExtra, let extra = family.extra {
                    Text(session.t(.familyLookingAt, extra.name))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.superAccent)
                }
            }
            PhilDoctor2DImage(size: 92)
        }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                Text(session.t(.homeFeelAsk))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(HomeDailyMood.allCases) { mood in
                    Button {
                        dailyMood = mood
                        UserDefaults.standard.set(mood.rawValue, forKey: moodKey)
                    } label: {
                        VStack(spacing: 6) {
                            Text(mood.symbol)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(mood.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(dailyMood == mood ? mood.tint : Color.clear, lineWidth: 2.5)
                                )
                            Text(mood.title(session))
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.title(session))
                    .accessibilityAddTraits(dailyMood == mood ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private var medicationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CheckMedTheme.flowDot)
                    .frame(width: 32, height: 32)
                    .background(CheckMedTheme.philFlowCanvas, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.homeTodaysMeds))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    if path.nodes.isEmpty {
                        Text(session.t(.todayNothing))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    } else {
                        Text(session.t(.homeScheduledRemaining, path.nodes.count, remainingCount))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                }
                Spacer()
                Button {
                    navPath.append(AppRoute.treatmentOverview)
                } label: {
                    HStack(spacing: 2) {
                        Text(session.t(.homeViewAll))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.flowDot)
                }
                .buttonStyle(.plain)
            }
            if path.nodes.isEmpty {
                Text(session.t(.homeBubbleEmpty))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                ForEach(path.nodes) { node in
                    doseRow(node)
                }
            }
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func doseRow(_ node: DoseNode) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(statusBar(node.status))
                .frame(width: 5, height: 44)
            Text(node.time)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .frame(width: 48, alignment: .leading)
            Image(systemName: "pills.fill")
                .foregroundStyle(CheckMedTheme.flowDot)
                .frame(width: 36, height: 36)
                .background(CheckMedTheme.philFlowCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.medicine)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                if !node.detail.isEmpty {
                    Text(node.detail)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            statusChip(node)
        }
        .padding(.vertical, 4)
    }

    private func statusChip(_ node: DoseNode) -> some View {
        let label: String
        let icon: String
        let tint: Color
        switch node.status {
        case .done:
            label = session.t(.taken)
            icon = "checkmark"
            tint = Color(hex: 0x5FA86B)
        case .skipped:
            label = session.t(.skipped)
            icon = "minus"
            tint = CheckMedTheme.muted
        case .current:
            label = session.t(.homeStatusNext)
            icon = "clock.fill"
            tint = CheckMedTheme.flowDot
        case .locked:
            label = session.t(.locked)
            icon = "lock.fill"
            tint = CheckMedTheme.muted
        }
        return Button {
            if node.status == .current { path.takeCurrent() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
            }
            .foregroundStyle(node.status == .done ? Color.white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (node.status == .done ? tint : tint.opacity(0.16)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(node.status != .current)
        .accessibilityLabel(label)
    }

    private func statusBar(_ status: PathStatus) -> Color {
        switch status {
        case .done: Color(hex: 0x5FA86B)
        case .current: CheckMedTheme.flowDot
        case .skipped: CheckMedTheme.skip
        case .locked: CheckMedTheme.locked
        }
    }

    private func revisionCard(days: Int) -> some View {
        Button {
            navPath.append(AppRoute.treatmentOverview)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(CheckMedTheme.flowDot)
                    .frame(width: 36, height: 36)
                    .background(CheckMedTheme.philFlowCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.homeNextRevision))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    Text(session.t(.homeInDays, days))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(14)
            .background(CheckMedTheme.philFlowCanvas.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quoteBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            PhilView(size: 64, mood: path.displayMood, smiling: true)
            Text(session.t(.homePhilQuote))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Image(systemName: "heart.fill")
                .foregroundStyle(CheckMedTheme.cheek)
        }
        .padding(12)
        .background(CheckMedTheme.belly)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var moodKey: String { "checkmed.homeMood.\(todayStamp)" }

    private var feelingItem: Binding<FeelingSheetItem?> {
        Binding(
            get: {
                path.pendingFeeling.map { FeelingSheetItem(logId: $0.logId, medicine: $0.medicine) }
            },
            set: { if $0 == nil { path.clearPendingFeeling() } }
        )
    }
}

private struct FeelingSheetItem: Identifiable {
    var id: UUID { logId }
    let logId: UUID
    let medicine: String
}
