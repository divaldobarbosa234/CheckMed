import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(FamilyStore.self) private var family
    @Environment(CheckMedStore.self) private var treatments
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

                    SpeechBubbleView(text: philBubble)

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
                    CheckMedButton(title: session.t(.homeSummary), style: .ghost) {
                        navPath.append(AppRoute.dailySummary)
                    }
                    HStack(spacing: 10) {
                        ghost(session.t(.journeyTitle)) { navPath.append(AppRoute.journeyReport) }
                        ghost(session.t(.pharmacyTitle)) { navPath.append(AppRoute.pharmacySearch) }
                    }
                    CheckMedButton(title: session.t(.notesOnDevice), style: .ghost) {
                        navPath.append(AppRoute.community)
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

    private var philBubble: String {
        if path.nodes.isEmpty {
            return session.t(.homeBubbleEmpty)
        }
        if path.pathComplete {
            return session.t(.homeBubbleComplete)
        }
        if path.mood == .celebrate, let current = path.current {
            return session.t(.homeBubbleCelebrate, current.medicine, current.time)
        }
        if path.mood == .skip, let current = path.current {
            return session.t(.homeBubbleSkip, current.medicine, current.time)
        }
        if let current = path.current {
            return session.t(.homeBubbleCurrent, current.medicine, current.time)
        }
        return session.t(.homeBubbleEmpty)
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
