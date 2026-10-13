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
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route, path: $path)
                }
        }
    }
}

struct ProfileView: View {
    var body: some View {
        ProfileRootScreen()
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
        // Capacity gates creation only; existing medication data is never pruned.
        if dest == .scanPrescription,
           !entitlements.applyMedicineCapacityGate(existingCount: treatments.intakeOpeningMedicineCount) {
            collapseMenu()
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
            if destination != .scanPrescription, destination != .progress {
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
            // Alternative A: FAB on Treatments and Refill only. Home keeps its
            // existing in-flow scan/progress actions; Profile stays full-width.
            if session.selectedMainTab == .treatments || session.selectedMainTab == .refill {
                FloatingPlusMenu()
                    .allowsHitTesting(
                        !(showUnfinishedPrompt && session.needsUnfinishedPlan(treatments: treatments))
                    )
            }
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
