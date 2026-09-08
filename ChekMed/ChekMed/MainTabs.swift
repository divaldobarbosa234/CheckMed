import SwiftUI

struct TreatmentsView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            TreatmentOverviewScreen(go: { path.append($0) })
                .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct ProgressTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ProgressDashboardScreen(go: { path.append($0) })
                .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments
    @Environment(FamilyStore.self) private var family
    @State private var confirmDelete = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.t(.profileTitle))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayName == "there" ? "Alex" : session.displayName)
                                .font(.system(.title2, design: .rounded).weight(.heavy))
                            Text(session.language)
                            Text(session.timeZoneName)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    }
                    SpeechBubbleView(text: session.t(.profileSignedBubble, session.displayName))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.t(.profileAccount))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(CheckMedTheme.muted)
                        Text(session.email ?? session.displayName)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        CheckMedButton(title: session.t(.profileSignOut), style: .secondary) {
                            session.signOut()
                        }
                        .accessibilityIdentifier("profile-sign-out")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(CheckMedTheme.hairline, lineWidth: 2)
                    )

                    Button { path.append(AppRoute.notificationPrefs) } label: {
                        profileRow(label: session.t(.profileNotifs), value: session.t(.profileOn))
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.settings) } label: {
                        profileRow(label: session.t(.profileSettings), value: "")
                    }
                    .buttonStyle(.plain)
                    LanguageSelectField(
                        locale: Binding(
                            get: { session.locale },
                            set: { session.setLocale($0) }
                        )
                    )
                    Button { path.append(AppRoute.family) } label: {
                        profileRow(
                            label: session.t(.profileFamily),
                            value: session.t(
                                .profileFamilyCount,
                                entitlements.isSuper ? family.occupiedSlots : 1,
                                entitlements.familySlots
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    Button { entitlements.presentPaywall() } label: {
                        profileRow(
                            label: session.t(.profileSuper),
                            value: entitlements.isSuper ? session.t(.paywallSuper) : session.t(.profileFree)
                        )
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.reminderSettings) } label: {
                        profileRow(
                            label: session.t(.profileReminders),
                            value: treatments.medicineSummaries().first?.name ?? ""
                        )
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.myMedicines) } label: {
                        profileRow(label: session.t(.profileMedicines), value: session.t(.profileLibrary))
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.journeyReport) } label: {
                        profileRow(label: session.t(.journeyTitle), value: "")
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.community) } label: {
                        profileRow(label: session.t(.notesOnDevice), value: "")
                    }
                    .buttonStyle(.plain)
                    Button { path.append(AppRoute.pharmacySearch) } label: {
                        profileRow(label: session.t(.pharmacyTitle), value: "")
                    }
                    .buttonStyle(.plain)

                    if !session.isGuest {
                        Button(session.t(.profileDelete)) { confirmDelete = true }
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.profileTitle))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route, path: $path)
            }
            .alert(session.t(.profileDeleteTitle), isPresented: $confirmDelete) {
                Button(session.t(.profileSignOutHere), role: .destructive) { session.deleteAccount() }
                Button(session.t(.cancel), role: .cancel) {}
            } message: {
                Text(session.t(.profileDeleteBody))
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.bold))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 2)
        )
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var showUnfinishedPrompt = false

    var body: some View {
        @Bindable var session = session
        ZStack {
            TabView(selection: $session.selectedMainTab) {
                HomeView()
                    .tabItem { Label(session.t(.tabHome), systemImage: "house.fill") }
                    .tag(SessionStore.MainTab.home)
                    .accessibilityIdentifier("tab-home")
                TreatmentsView()
                    .tabItem { Label(session.t(.tabTreatments), systemImage: "pills.fill") }
                    .tag(SessionStore.MainTab.treatments)
                    .accessibilityIdentifier("tab-treatments")
                ProgressTabView()
                    .tabItem { Label(session.t(.tabProgress), systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(SessionStore.MainTab.progress)
                    .accessibilityIdentifier("tab-progress")
                ProfileView()
                    .tabItem { Label(session.t(.tabProfile), systemImage: "person.fill") }
                    .tag(SessionStore.MainTab.profile)
                    .accessibilityIdentifier("tab-profile")
            }
            .tint(CheckMedTheme.primaryShadow)

            if session.showResumeSetup {
                ResumePlanSetupFlow()
                    .transition(.opacity)
            } else if showUnfinishedPrompt {
                UnfinishedPlanPromptView(kind: .afterReturn)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showUnfinishedPrompt)
        .animation(.easeInOut(duration: 0.35), value: session.showResumeSetup)
        .onChange(of: session.showResumeSetup) { _, active in
            if active { showUnfinishedPrompt = false }
        }
        .task(id: "\(session.selectedMainTab)-\(session.needsUnfinishedPlan(treatments: treatments))") {
            await offerUnfinishedPlanIfNeeded()
        }
    }

    private func offerUnfinishedPlanIfNeeded() async {
        guard session.selectedMainTab == .home || session.selectedMainTab == .progress else {
            showUnfinishedPrompt = false
            return
        }
        guard session.needsUnfinishedPlan(treatments: treatments) else {
            showUnfinishedPrompt = false
            return
        }
        guard !session.didOfferUnfinishedPlanThisSession else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        guard session.selectedMainTab == .home || session.selectedMainTab == .progress else { return }
        guard session.needsUnfinishedPlan(treatments: treatments) else { return }
        session.didOfferUnfinishedPlanThisSession = true
        showUnfinishedPrompt = true
    }
}
