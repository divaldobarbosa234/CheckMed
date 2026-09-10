import SwiftUI
import UserNotifications

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
    @State private var showLanguage = false
    @State private var notificationsOn = false

    private var shownName: String {
        let raw = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = raw.lowercased()
        if raw.isEmpty || lowered == "there" || lowered == "friend" {
            return session.isGuest ? session.t(.profileGuest) : session.t(.homeFriendName)
        }
        return raw
    }

    private var familyOccupied: Int {
        entitlements.isSuper ? family.occupiedSlots : 1
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    identityCard
                    accountCard
                    prefsCard
                    languageFamilyCard
                    moreCard
                    helpBanner
                    if !session.isGuest {
                        Button(session.t(.profileDelete)) { confirmDelete = true }
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    if let error = session.errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                    }
                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .navigationTitle(session.t(.profileTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteView(route: route, path: $path)
            }
            .sheet(isPresented: $showLanguage) {
                LanguageWheelSheet(
                    locale: Binding(
                        get: { session.locale },
                        set: { session.setLocale($0) }
                    )
                )
                .environment(session)
                .environment(\.locale, session.locale.foundationLocale)
            }
            .task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                notificationsOn = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
            .alert(session.t(.profileDeleteTitle), isPresented: $confirmDelete) {
                Button(session.t(.profileSignOutHere), role: .destructive) { session.deleteAccount() }
                Button(session.t(.cancel), role: .cancel) {}
            } message: {
                Text(session.t(.profileDeleteBody))
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [CheckMedTheme.surface, CheckMedTheme.mintWash],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(CheckMedTheme.primary.opacity(0.11))
                .frame(width: 180, height: 180)
                .offset(x: 42, y: 24)
                .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: 2) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CheckMed")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.primaryShadow)
                    Text(session.t(.profileTitle))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(CheckMedTheme.ink)
                    Rectangle()
                        .fill(CheckMedTheme.primary)
                        .frame(width: 44, height: 4)
                        .clipShape(Capsule())
                    Text(session.t(.profileSubhead))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if family.isViewingExtra, let extra = family.extra {
                        Text(session.t(.familyLookingAt, extra.name))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.superAccent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PhilDoctor2DImage(size: 142)
                    .offset(y: 11)
            }
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.vertical, 14)

            Button { path.append(AppRoute.settings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(CheckMedTheme.surface.opacity(0.94), in: Circle())
                    .shadow(color: CheckMedTheme.navy.opacity(0.08), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(session.t(.profileSettings))
        }
        .frame(minHeight: 188)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var identityCard: some View {
        card {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CheckMedTheme.belly)
                    Circle()
                        .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
                    PhilView(size: 52, smiling: true)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(shownName)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CheckMedTheme.flowDot)
                        Text(session.language)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CheckMedTheme.current)
                        Text(session.timeZoneName)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var accountCard: some View {
        card {
            Text(session.t(.profileAccount))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            HStack(spacing: 12) {
                iconBadge("envelope.fill", wash: CheckMedTheme.belly, tint: CheckMedTheme.primaryShadow)
                Text(session.email ?? session.t(.profileGuest))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Button {
                session.signOut()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(session.t(.profileSignOut))
                }
                .font(.system(.body, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.primaryShadow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CheckMedTheme.primaryShadow, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-sign-out")
        }
    }

    private var prefsCard: some View {
        card {
            settingRow(
                icon: "bell.fill",
                wash: CheckMedTheme.philFlowCanvas,
                tint: CheckMedTheme.flowDot,
                title: session.t(.profileNotifs),
                subtitle: session.t(.profileNotifsHint),
                badge: notificationsOn ? session.t(.profileOn) : nil
            ) {
                path.append(AppRoute.notificationPrefs)
            }
            divider
            settingRow(
                icon: "gearshape.fill",
                wash: Color(hex: 0x9B7ED9).opacity(0.22),
                tint: Color(hex: 0x9B7ED9),
                title: session.t(.profileSettings),
                subtitle: session.t(.profileSettingsHint)
            ) {
                path.append(AppRoute.settings)
            }
        }
    }

    private var languageFamilyCard: some View {
        card {
            Text(session.t(.language))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            settingRow(
                icon: "globe",
                wash: CheckMedTheme.belly,
                tint: CheckMedTheme.primaryShadow,
                title: session.language,
                subtitle: session.t(.profileAppLanguage)
            ) {
                showLanguage = true
            }
            divider
            settingRow(
                icon: "person.2.fill",
                wash: CheckMedTheme.cheek.opacity(0.28),
                tint: CheckMedTheme.current,
                title: session.t(.profileFamily),
                subtitle: session.t(.profileFamilyManage, familyOccupied, entitlements.familySlots)
            ) {
                path.append(AppRoute.family)
            }
        }
    }

    private var moreCard: some View {
        card {
            Text(session.t(.profileMore))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            settingRow(
                icon: "sparkles",
                wash: CheckMedTheme.belly,
                tint: CheckMedTheme.superAccent,
                title: session.t(.profileSuper),
                subtitle: entitlements.isSuper ? session.t(.paywallSuper) : session.t(.profileFree)
            ) {
                entitlements.presentPaywall()
            }
            divider
            settingRow(
                icon: "alarm.fill",
                wash: CheckMedTheme.philFlowCanvas,
                tint: CheckMedTheme.flowDot,
                title: session.t(.profileReminders),
                subtitle: treatments.medicineSummaries().first?.name ?? session.t(.remindersNoneScheduled)
            ) {
                path.append(AppRoute.reminderSettings)
            }
            divider
            settingRow(
                icon: "pills.fill",
                wash: Color(hex: 0x5FA86B).opacity(0.18),
                tint: Color(hex: 0x5FA86B),
                title: session.t(.profileMedicines),
                subtitle: session.t(.profileLibrary)
            ) {
                path.append(AppRoute.myMedicines)
            }
            divider
            settingRow(
                icon: "doc.text.fill",
                wash: CheckMedTheme.mintWash,
                tint: Color(hex: 0x5FA86B),
                title: session.t(.reportsHubTitle),
                subtitle: session.t(.reportsHubSubhead)
            ) {
                path.append(AppRoute.reportsHub)
            }
            divider
            settingRow(
                icon: "battery.75percent",
                wash: CheckMedTheme.belly,
                tint: CheckMedTheme.primaryShadow,
                title: session.t(.refillHeadline),
                subtitle: session.t(.refillTipBodyGeneric)
            ) {
                path.append(AppRoute.refillStock)
            }
            divider
            settingRow(
                icon: "note.text",
                wash: CheckMedTheme.philFlowCanvas,
                tint: CheckMedTheme.flowDot,
                title: session.t(.notesOnDevice),
                subtitle: ""
            ) {
                path.append(AppRoute.community)
            }
        }
    }

    private var helpBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            PhilGlassesImage(size: 72)
            VStack(alignment: .leading, spacing: 10) {
                Text(session.t(.profileHelpTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Text(session.t(.profileHelpBody))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                Button {
                    path.append(AppRoute.community)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text(session.t(.profileTalkToUs))
                    }
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule()
                            .stroke(CheckMedTheme.primaryShadow, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .shadow(color: CheckMedTheme.navy.opacity(0.055), radius: 12, y: 5)
    }

    private var divider: some View {
        Rectangle()
            .fill(CheckMedTheme.hairline)
            .frame(height: 1)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .shadow(color: CheckMedTheme.navy.opacity(0.055), radius: 12, y: 5)
    }

    private func iconBadge(_ systemName: String, wash: Color, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingRow(
        icon: String,
        wash: Color,
        tint: Color,
        title: String,
        subtitle: String,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                iconBadge(icon, wash: wash, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.onPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(CheckMedTheme.primary, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct RefillTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            RefillStockScreen(go: { path.append($0) })
                .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct PharmaciesTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            PharmacySearchScreen()
                .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct ReportsTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ReportsHubScreen(go: { path.append($0) })
                .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct ReportsHubScreen: View {
    var go: (AppRoute) -> Void
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.t(.reportsHubTitle))
                    .font(.system(.title, design: .rounded).weight(.black))
                Text(session.t(.reportsHubSubhead))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)

                hubRow(
                    icon: "flag.checkered",
                    wash: CheckMedTheme.belly,
                    tint: CheckMedTheme.primaryShadow,
                    title: session.t(.journeyTitle),
                    subtitle: session.t(.progressJourneyHint)
                ) {
                    go(.journeyReport)
                }

                hubRow(
                    icon: "doc.richtext",
                    wash: CheckMedTheme.mintWash,
                    tint: Color(hex: 0x5FA86B),
                    title: session.t(.reportHeadline),
                    subtitle: session.t(.reportProgressHint)
                ) {
                    go(.medicineReport)
                }

                Text(session.t(.journeyNotAdvice))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.safety)
            }
            .padding(16)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.reportsHubTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hubRow(
        icon: String,
        wash: Color,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
            )
            .shadow(color: CheckMedTheme.navy.opacity(0.055), radius: 12, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var showUnfinishedPrompt = false

    /// Custom bar — UIKit TabView caps at 5 items and auto-adds "More" for the rest.
    private static let tabItems: [(tab: SessionStore.MainTab, title: L10n.Key, icon: String, id: String)] = [
        (.home, .tabHome, "house.fill", "tab-home"),
        (.treatments, .tabTreatments, "pills.fill", "tab-treatments"),
        (.progress, .tabProgress, "chart.line.uptrend.xyaxis", "tab-progress"),
        (.refill, .tabRefill, "battery.75percent", "tab-refill"),
        (.pharmacies, .tabPharmacies, "cross.case.fill", "tab-pharmacies"),
        (.reports, .tabReports, "doc.richtext", "tab-reports"),
        (.profile, .tabProfile, "person.fill", "tab-profile"),
    ]

    var body: some View {
        ZStack {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    customTabBar
                }

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

    /// Keep non-map tabs mounted so each NavigationStack retains its path.
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            keptTab(.home) { HomeView() }
            keptTab(.treatments) { TreatmentsView() }
            keptTab(.progress) { ProgressTabView() }
            keptTab(.refill) { RefillTabView() }
            // Tear down MapKit when leaving — Map stays heavy once mounted.
            Group {
                if session.selectedMainTab == .pharmacies {
                    PharmaciesTabView()
                } else {
                    Color.clear
                }
            }
            .opacity(session.selectedMainTab == .pharmacies ? 1 : 0)
            .allowsHitTesting(session.selectedMainTab == .pharmacies)
            .accessibilityElement(children: session.selectedMainTab == .pharmacies ? .contain : .ignore)
            keptTab(.reports) { ReportsTabView() }
            keptTab(.profile) { ProfileView() }
        }
    }

    @ViewBuilder
    private func keptTab<Content: View>(
        _ tab: SessionStore.MainTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = session.selectedMainTab == tab
        content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityElement(children: selected ? .contain : .ignore)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabItems, id: \.tab) { item in
                let selected = session.selectedMainTab == item.tab
                Button {
                    session.selectedMainTab = item.tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 22)
                        Text(session.t(item.title))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selected ? CheckMedTheme.primaryShadow : CheckMedTheme.muted)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.id)
                .accessibilityLabel(session.t(item.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .background(CheckMedTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CheckMedTheme.hairline)
                .frame(height: 1)
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
