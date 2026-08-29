import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @State private var navPath = NavigationPath()

    private var greeting: String {
        let hour = session.foundationCalendar.component(.hour, from: Date())
        switch hour {
        case 5..<12: return session.t(.homeMorning)
        case 12..<18: return session.t(.homeAfternoon)
        default: return session.t(.homeEvening)
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.t(.homeDashboard))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(CheckMedTheme.muted)
                            Text(greeting)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                            Text(session.t(.homeReady))
                                .font(.system(.title2, design: .rounded).weight(.heavy))
                        }
                        Spacer()
                        freezeChip
                    }

                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 108, mood: path.displayMood)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("🔥")
                                Text("\(path.streakDays)")
                                    .font(.system(.title, design: .rounded).weight(.black))
                                    .foregroundStyle(CheckMedTheme.streak)
                            }
                            Text(session.t(.homeStreak))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        .padding(12)
                        .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xF3D7A0), lineWidth: 2)
                        )
                    }

                    SpeechBubbleView(text: path.bubble)

                    if family.isViewingExtra, let extra = family.extra {
                        Text(session.t(.familyLookingAt, extra.name))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.superAccent)
                    }

                    Text(session.t(.homeToday))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .tracking(1)

                    if path.nodes.isEmpty {
                        Text(session.t(.todayNothing))
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    } else {
                        ForEach(Array(path.nodes.enumerated()), id: \.element.id) { index, node in
                            PathNodeView(
                                node: node,
                                offset: TodayPathStore.offsets[index % TodayPathStore.offsets.count],
                                showConnector: index < path.nodes.count - 1,
                                onTake: { path.takeCurrent() },
                                onSkip: { path.skipCurrent() }
                            )
                        }
                    }

                    CheckMedButton(title: session.t(.homeScan)) {
                        navPath.append(AppRoute.addPrescription)
                    }

                    HStack(spacing: 10) {
                        ghost(session.t(.homeNextDose)) { navPath.append(AppRoute.nextDose) }
                        ghost(session.t(.homeAlarm)) { navPath.append(AppRoute.medicationAlarm) }
                    }

                    HStack(spacing: 10) {
                        ghost(session.t(.homeTodaysTreatment)) { navPath.append(AppRoute.todayTreatment) }
                        ghost(session.t(.homeUpcoming)) { navPath.append(AppRoute.upcoming) }
                    }
                    CheckMedButton(title: session.t(.homeSummary), style: .ghost) {
                        navPath.append(AppRoute.dailySummary)
                    }

                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.homeDashboard))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route, path: $navPath)
            }
            .onAppear { path.reload() }
            .task {
                guard session.shouldOfferOnboardingPaywall, !entitlements.isSuper else { return }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard !Task.isCancelled else { return }
                guard session.shouldOfferOnboardingPaywall, !entitlements.isSuper else { return }
                session.markOnboardingPaywallOffered()
                entitlements.presentPaywall()
            }
        }
    }

    private var freezeChip: some View {
        Button {
            if !entitlements.canUseStreakFreeze {
                entitlements.presentPaywall()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: entitlements.canUseStreakFreeze ? "snowflake" : "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(session.t(.homeFreeze))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
            }
            .foregroundStyle(entitlements.canUseStreakFreeze ? CheckMedTheme.superAccent : CheckMedTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CheckMedTheme.surface, in: Capsule())
            .overlay(
                Capsule().stroke(
                    entitlements.canUseStreakFreeze ? CheckMedTheme.superAccent : Color(hex: 0xEFEFEF),
                    lineWidth: 2
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            entitlements.canUseStreakFreeze
                ? session.t(.homeFreezeOn)
                : session.t(.homeFreezeLocked)
        )
    }

    private func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(Capsule().stroke(CheckMedTheme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
