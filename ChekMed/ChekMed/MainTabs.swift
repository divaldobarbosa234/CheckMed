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
            return session.t(.homeFriendName)
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
                    Button(session.t(.profileDelete)) { confirmDelete = true }
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
                Button(session.t(.profileDeleteConfirm), role: .destructive) {
                    session.deleteAccount(treatments: treatments, family: family)
                }
                Button(session.t(.cancel), role: .cancel) {}
            } message: {
                Text(session.t(session.hasAppleIdentity ? .profileDeleteBodyApple : .profileDeleteBody))
            }
            .disabled(session.isDeletingAccount)
            .overlay {
                if session.isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                        ProgressView()
                            .tint(CheckMedTheme.primary)
                    }
                    .allowsHitTesting(true)
                }
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
                Text(session.email ?? session.t(.profileAccount))
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
                ReportPerf.tap()
                ReportPerf.log("TAB STATE CHANGED profile path reportsHub")
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
        let _ = ReportPerf.log("ReportsTabView body")
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

    var body: some View {
        let _ = ReportPerf.log("ReportsHubScreen body")
        MedicineReportScreen(go: go)
    }
}

/// Destinations opened from the floating + menu (not bottom-tab roots).
enum PlusMenuDestination: String, Identifiable {
    case pharmacies
    case reports
    case scanPrescription
    case progress

    var id: String { rawValue }
}

/// Shared + overlay — bottom-trailing FAB above the system tab bar.
///
/// Must sit in a parent `ZStack(alignment: .bottomTrailing)` (or
/// `.overlay(alignment: .bottomTrailing)`). A plain `.overlay { }` centers
/// content, which pinned this control mid-screen when collapsed.
struct FloatingPlusMenu: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CheckMedStore.self) private var treatments

    @State private var menuExpanded = false
    @State private var destination: PlusMenuDestination?

    /// Standard UITabBar height; FAB clears it while staying above the home indicator.
    private static let tabBarClearance: CGFloat = 52
    private static let trailingPadding: CGFloat = 18
    private static let bottomGap: CGFloat = 10

    private static let menuItems: [(destination: PlusMenuDestination, title: L10n.Key, icon: String, wash: Color, tint: Color)] = [
        (.pharmacies, .tabPharmacies, "cross.case.fill", CheckMedTheme.belly, CheckMedTheme.primaryShadow),
        (.reports, .tabReports, "doc.richtext", CheckMedTheme.mintWash, Color(hex: 0x5FA86B)),
        (.scanPrescription, .homeScan, "doc.viewfinder", CheckMedTheme.cheek.opacity(0.28), CheckMedTheme.current),
        (.progress, .tabProgress, "chart.line.uptrend.xyaxis", CheckMedTheme.philFlowCanvas, CheckMedTheme.flowDot),
    ]

    var body: some View {
        let _ = FreezeDiag.log("FloatingPlusMenu body expanded=\(menuExpanded)")
        ZStack(alignment: .bottomTrailing) {
            if menuExpanded {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { collapseMenu() }
            }
            plusAndCard
                .padding(.trailing, Self.trailingPadding)
                .padding(.bottom, Self.tabBarClearance + Self.bottomGap)
        }
        .frame(maxWidth: menuExpanded ? .infinity : nil, maxHeight: menuExpanded ? .infinity : nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: menuExpanded)
        .sheet(item: $destination) { dest in
            PlusMenuDestinationHost(destination: dest)
        }
        .onChange(of: destination) { _, newValue in
            if newValue == .reports {
                ReportPerf.log("TAB STATE CHANGED destination=reports sheet")
            }
            if newValue != nil { menuExpanded = false }
        }
    }

    private var plusAndCard: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if menuExpanded {
                menuCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            plusButton
        }
    }

    private var plusButton: some View {
        Button {
            if menuExpanded {
                collapseMenu()
            } else {
                menuExpanded = true
            }
        } label: {
            Image(systemName: menuExpanded ? "xmark" : "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CheckMedTheme.onPrimary)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(CheckMedTheme.primaryShadow)
                        .shadow(color: CheckMedTheme.navy.opacity(0.22), radius: 14, y: 6)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityIdentifier("floating-plus-menu")
        .accessibilityLabel(session.t(menuExpanded ? .cancel : .plusMenuA11y))
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.t(.plusMenuTitle))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(Self.menuItems, id: \.destination) { item in
                Button {
                    open(item.destination)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(item.tint)
                            .frame(width: 40, height: 40)
                            .background(item.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(session.t(item.title))
                            .font(.system(.body, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.t(item.title))
            }
        }
        .padding(.bottom, 8)
        .frame(width: 268)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
        .shadow(color: CheckMedTheme.navy.opacity(0.14), radius: 18, y: 8)
    }

    private func open(_ dest: PlusMenuDestination) {
        // Empty / under free active-medicine cap → intake; Super only at/over cap.
        if dest == .scanPrescription,
           !entitlements.isSuper,
           treatments.storedMedicineCount > 0,
           entitlements.freeMedicineSlotsRemaining(existingCount: treatments.storedMedicineCount) <= 0 {
            collapseMenu()
            entitlements.presentPaywall()
            return
        }
        if dest == .reports {
            ReportPerf.tap()
        }
        destination = dest
    }

    private func collapseMenu() {
        menuExpanded = false
    }
}

/// Presents a +menu destination in its own stack; MapKit tears down when the sheet dismisses.
struct PlusMenuDestinationHost: View {
    let destination: PlusMenuDestination
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var scanPath = NavigationPath()

    var body: some View {
        Group {
            switch destination {
            case .pharmacies:
                PharmaciesTabView()
            case .reports:
                ReportsTabView()
                    .onAppear { ReportPerf.log("PlusMenuDestinationHost reports onAppear") }
            case .scanPrescription:
                NavigationStack(path: $scanPath) {
                    AppRouteView(route: .addPrescription, path: $scanPath)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(session.t(.cancel)) { dismiss() }
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            AppRouteView(route: route, path: $scanPath)
                        }
                }
            case .progress:
                ProgressTabView()
            }
        }
        .overlay(alignment: .topLeading) {
            if destination != .scanPrescription {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .frame(width: 34, height: 34)
                        .background(CheckMedTheme.surface.opacity(0.96), in: Circle())
                        .shadow(color: CheckMedTheme.navy.opacity(0.1), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.top, 10)
                .accessibilityLabel(session.t(.cancel))
            }
        }
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var showUnfinishedPrompt = false

    /// Four system tabs — no “More”. Pharmacies / Reports / Scan / Progress via +.
    private static let primaryTabs: Set<SessionStore.MainTab> = [
        .home, .treatments, .refill, .profile,
    ]

    var body: some View {
        TabView(selection: Binding(
            get: { session.selectedMainTab },
            set: {
                FreezeDiag.log("tab setter \($0) — SwiftUI received a tab selection")
                session.selectedMainTab = $0
            }
        )) {
            Tab(session.t(.tabHome), systemImage: "house.fill", value: SessionStore.MainTab.home) {
                HomeView()
            }
            Tab(session.t(.tabTreatments), systemImage: "pills.fill", value: SessionStore.MainTab.treatments) {
                TreatmentsView()
            }
            Tab(session.t(.tabRefill), systemImage: "battery.75percent", value: SessionStore.MainTab.refill) {
                RefillTabView()
            }
            Tab(session.t(.tabProfile), systemImage: "person.fill", value: SessionStore.MainTab.profile) {
                ProfileView()
            }
        }
        .tint(CheckMedTheme.primaryShadow)
        .overlay(alignment: .bottomTrailing) {
            FloatingPlusMenu()
                .allowsHitTesting(
                    !(showUnfinishedPrompt && session.needsUnfinishedPlan(treatments: treatments))
                )
        }
        .overlay {
            if showUnfinishedPrompt, session.needsUnfinishedPlan(treatments: treatments) {
                let _ = FreezeDiag.log("UnfinishedPlanPromptView covering MainTabView")
                UnfinishedPlanPromptView(kind: .afterReturn)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showUnfinishedPrompt)
        .animation(.easeInOut(duration: 0.35), value: session.showResumeSetup)
        .onAppear { clampSelectedTab() }
        .onChange(of: session.selectedMainTab) { _, _ in
            clampSelectedTab()
        }
        .onChange(of: session.showResumeSetup) { _, active in
            if active { showUnfinishedPrompt = false }
        }
        .task(id: "\(session.selectedMainTab)-\(session.needsUnfinishedPlan(treatments: treatments))") {
            FreezeDiag.log("MainTabView.task tab=\(session.selectedMainTab) unfinished=\(session.needsUnfinishedPlan(treatments: treatments))")
            await offerUnfinishedPlanIfNeeded()
        }
    }

    /// Legacy MainTab cases (progress/pharmacies/reports) still exist for API compat — snap back to Home.
    private func clampSelectedTab() {
        if !Self.primaryTabs.contains(session.selectedMainTab) {
            session.selectedMainTab = .home
        }
    }

    private func offerUnfinishedPlanIfNeeded() async {
        guard session.selectedMainTab == .home else {
            showUnfinishedPrompt = false
            return
        }
        guard session.needsUnfinishedPlan(treatments: treatments) else {
            showUnfinishedPrompt = false
            return
        }
        guard !session.didOfferUnfinishedPlanThisSession else { return }
        guard session.restorationComplete else { return }
        session.didOfferUnfinishedPlanThisSession = true
        showUnfinishedPrompt = true
    }
}
