import SwiftUI

private enum HomeMoodPhase: Equatable {
    case picker
    case note
    case hidden
}

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

    var noteKeys: [L10n.Key] {
        switch self {
        case .great:
            [.homeMoodNoteGreat, .homeMoodNoteGreat2, .homeMoodNoteGreat3,
             .homeMoodNoteGreat4, .homeMoodNoteGreat5, .homeMoodNoteGreat6]
        case .good:
            [.homeMoodNoteGood, .homeMoodNoteGood2, .homeMoodNoteGood3,
             .homeMoodNoteGood4, .homeMoodNoteGood5, .homeMoodNoteGood6]
        case .okay:
            [.homeMoodNoteOkay, .homeMoodNoteOkay2, .homeMoodNoteOkay3,
             .homeMoodNoteOkay4, .homeMoodNoteOkay5, .homeMoodNoteOkay6]
        case .notGreat:
            [.homeMoodNoteNotGreat, .homeMoodNoteNotGreat2, .homeMoodNoteNotGreat3,
             .homeMoodNoteNotGreat4, .homeMoodNoteNotGreat5, .homeMoodNoteNotGreat6]
        case .bad:
            [.homeMoodNoteBad, .homeMoodNoteBad2, .homeMoodNoteBad3,
             .homeMoodNoteBad4, .homeMoodNoteBad5, .homeMoodNoteBad6]
        }
    }

    /// Day-seeded pick from the pool, then a light shuffle so taps still feel fresh.
    func noteForDay(session: SessionStore, dayOfYear: Int, lastKeyRaw: String?) -> (key: L10n.Key, text: String) {
        let keys = noteKeys
        guard !keys.isEmpty else {
            return (.homeMoodNoteOkay, session.t(.homeMoodNoteOkay))
        }
        let preferred = ((dayOfYear % keys.count) + keys.count) % keys.count
        // Rotate so today’s preferred message leads, then shuffle the rest for within-day variety.
        var rotated = Array(keys[preferred...]) + Array(keys[..<preferred])
        if rotated.count > 1, let lastKeyRaw, let last = L10n.Key(rawValue: lastKeyRaw) {
            rotated.removeAll { $0 == last }
            if rotated.isEmpty { rotated = keys }
        }
        let picked = rotated.randomElement() ?? keys[preferred]
        return (picked, session.t(picked))
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
    @State private var moodPhase: HomeMoodPhase = .picker
    @State private var moodMessage = ""
    @State private var hideMoodTask: Task<Void, Never>?
    @State private var gameCelebrate: GameCelebrate?
    @State private var hideCelebrateTask: Task<Void, Never>?
    @State private var gamePrimed = false
    @State private var lastGameTaken = -1
    @State private var lastGameSkipped = -1
    /// Feeling check-in waits until Phil’s overlay finishes. UI-only; not a second timer.
    @State private var presentedFeeling: FeelingSheetItem?

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

    /// One dashboard row per distinct medicine scheduled today.
    private var todayMedicines: [HomeMedicineRow] {
        let grouped = Dictionary(grouping: path.nodes, by: \.medicineId)
        return grouped.keys
            .compactMap { medicineId -> HomeMedicineRow? in
                guard let doses = grouped[medicineId], !doses.isEmpty else { return nil }
                let ordered = doses.sorted { $0.scheduledAt < $1.scheduledAt }
                let pending = ordered.filter { node in
                    node.status != .done && node.status != .skipped
                }
                let display: DoseNode
                let status: PathStatus
                if let nextOpen = pending.first {
                    display = nextOpen
                    let upcoming = nextOpen.scheduledAt > Date() && nextOpen.status == .locked
                    status = upcoming ? .locked : (nextOpen.status == .done ? .done : .current)
                } else if let taken = ordered.last(where: { $0.status == .done }) {
                    display = taken
                    status = .done
                } else if let skipped = ordered.last(where: { $0.status == .skipped }) {
                    display = skipped
                    status = .skipped
                } else {
                    display = ordered[0]
                    status = display.status
                }
                return HomeMedicineRow(
                    id: medicineId,
                    medicine: display.medicine,
                    detail: display.detail,
                    time: display.time,
                    status: status,
                    takeDoseId: pending.first?.id,
                    scheduledAt: display.scheduledAt
                )
            }
            .sorted { lhs, rhs in
                // Pending medicines first (by next dose), then completed alphabetically by time.
                let lhsPending = lhs.takeDoseId != nil
                let rhsPending = rhs.takeDoseId != nil
                if lhsPending != rhsPending { return lhsPending && !rhsPending }
                if lhs.scheduledAt != rhs.scheduledAt { return lhs.scheduledAt < rhs.scheduledAt }
                return lhs.medicine.localizedCaseInsensitiveCompare(rhs.medicine) == .orderedAscending
            }
    }

    private var remainingMedicineCount: Int {
        todayMedicines.filter { $0.takeDoseId != nil }.count
    }

    /// Path nodes are empty until `reload()` runs after first layout. Today's
    /// logs already exist in the store — read them synchronously so Challenge
    /// keeps its slot above the week card on frame 1.
    private var challengeNodes: [DoseNode] {
        path.nodes.isEmpty ? treatments.todayNodes() : path.nodes
    }

    private var progressStats: AdherenceSnapshot { treatments.adherence() }

    private var challenge: GamificationSnapshot {
        let stats = progressStats
        return Gamification.snapshot(
            nodes: challengeNodes,
            currentStreak: stats.streakDays,
            longestStreak: stats.longestStreakDays,
            hasActiveTreatment: hasActivePlan && !isPlanVisibilityPending,
            todayTaken: stats.todayTaken,
            todayScheduled: stats.todayTotal,
            todayMissed: stats.todayMissedCount
        )
    }

    private var hasActivePlan: Bool { treatments.activeMedicineCount > 0 }

    /// Loading is not empty. Existing active rows that are not yet visible must
    /// not render "Escanear receita".
    private var isPlanVisibilityPending: Bool {
        !session.restorationComplete
            || !session.isPlanSurfaceReady
            || (treatments.hasActivePlan && treatments.activeMedicineCount == 0)
    }

    var body: some View {
        let _ = FreezeDiag.homeBody(
            revision: treatments.revision,
            nodeIds: path.nodes.map(\.id).joined(separator: ","),
            hasChanges: treatments.freezeDiagHasChanges()
        )
        let _ = FreezeDiag.watch("treatments.revision") { _ = treatments.revision }
        let _ = FreezeDiag.watch("treatments.surfacesPlan") { _ = treatments.surfacesPlan }
        let _ = FreezeDiag.watch("path.nodes") { _ = path.nodes.map(\.id) }
        let _ = FreezeDiag.watch("path.mood") { _ = path.mood }
        let _ = FreezeDiag.watch("path.pendingFeeling") { _ = path.pendingFeeling?.logId }
        let _ = FreezeDiag.watch("session.selectedMainTab") { _ = session.selectedMainTab }
        let _ = FreezeDiag.watch("session.displayName") { _ = session.displayName }
        let _ = FreezeDiag.watch("entitlements.isSuper") { _ = entitlements.isSuper }
        let _ = FreezeDiag.watch("family.isViewingExtra") { _ = family.isViewingExtra }
        NavigationStack(path: $navPath) {
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    let stats = progressStats
                    let nodes = challengeNodes
                    let game = Gamification.snapshot(
                        nodes: nodes,
                        currentStreak: stats.streakDays,
                        longestStreak: stats.longestStreakDays,
                        hasActiveTreatment: hasActivePlan && !isPlanVisibilityPending,
                        todayTaken: stats.todayTaken,
                        todayScheduled: stats.todayTotal,
                        todayMissed: stats.todayMissedCount
                    )
                    header
                    if isPlanVisibilityPending {
                        restoringPlanCard
                    } else if hasActivePlan {
                        if let journey = DailyMedicationJourney.snapshot(
                            from: game,
                            nodes: nodes,
                            planSurfaceReady: !isPlanVisibilityPending
                        ) {
                            DailyMedicationJourneyCard(
                                journey: journey,
                                streakDays: game.currentStreak
                            ) {
                                #if DEBUG
                                print(
                                    "[JOURNEY-DIAG] state=\(journey.state) action=\(String(describing: DailyMedicationJourney.action(for: journey.state))) challengeAnchorAvailable=true"
                                )
                                #endif
                                proxy.scrollTo("todays-challenge", anchor: .top)
                            }
                        }
                        TodaysChallengeCard(snapshot: game) { doseId in
                            #if DEBUG
                            print("[PHASE4A-REGRESSION] dose tap challenge id=\(doseId)")
                            #endif
                            let node = nodes.first(where: { $0.id == doseId })
                            if node?.status == .skipped {
                                path.requestMissedSheetPresentation()
                                return
                            }
                            confirmDoseAndCoach(id: doseId)
                        }
                        .id("todays-challenge")
                        WeeklyAdherenceCard(
                            stats: stats,
                            weekly: treatments.weeklyMedicationProgress(),
                            snapshot: game,
                            hasUpcomingDose: nodes.contains { $0.status == .current || $0.status == .locked }
                        ) {
                            navPath.append(AppRoute.treatmentOverview)
                        }
                        GamificationStreakCard(snapshot: game)
                        if moodPhase != .hidden {
                            moodCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                ))
                        }
                        medicationsCard
                        progressGlanceLinks
                        if let days = treatments.daysUntilNextRevision(calendar: session.foundationCalendar), days >= 0 {
                            revisionCard(days: days)
                        }
                        quoteBanner
                    } else {
                        emptyPlanCard
                    }
                    CheckMedButton(title: session.t(.homeScan)) {
                        // Active-medicine free cap only — empty / under cap opens intake, not Super.
                        if !entitlements.isSuper,
                           treatments.storedMedicineCount > 0,
                           entitlements.freeMedicineSlotsRemaining(existingCount: treatments.storedMedicineCount) <= 0 {
                            entitlements.presentPaywall()
                        } else {
                            navPath.append(AppRoute.addPrescription)
                        }
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
                FreezeDiag.log("Home onAppear START")
                LaunchLog.home("onAppear tab=\(session.selectedMainTab)")
                applyMoodVisibilityForToday(animated: false)
                path.reload()
                primeGamificationIfNeeded()
                Task { @MainActor in
                    treatments.refreshDoseLogsForDisplay()
                    path.reload()
                    primeGamificationIfNeeded()
                }
                FreezeDiag.log("Home onAppear END")
            }
            .onChange(of: session.selectedMainTab) { _, tab in
                LaunchLog.home("tab→\(tab)")
                if tab == .home {
                    applyMoodVisibilityForToday(animated: false)
                    presentFeelingCheckInIfNeeded()
                } else {
                    dismissPhilReaction(animated: false)
                }
            }
            .onChange(of: navPath.count) { _, count in
                if count == 0, session.selectedMainTab == .home {
                    applyMoodVisibilityForToday(animated: false)
                    presentFeelingCheckInIfNeeded()
                } else if count > 0 {
                    dismissPhilReaction(animated: false)
                }
            }
            .onChange(of: session.restorationComplete) { _, ready in
                if ready {
                    path.reload()
                    primeGamificationIfNeeded()
                }
            }
            .onChange(of: session.isPlanSurfaceReady) { _, ready in
                if ready {
                    path.reload()
                    primeGamificationIfNeeded()
                }
            }
            .onChange(of: session.planOwnerId) { _, _ in
                resetGamificationSession()
            }
            .onChange(of: session.planProfileId) { _, _ in
                resetGamificationSession()
            }
            .onChange(of: path.pendingFeeling?.logId) { _, id in
                if id == nil {
                    if presentedFeeling != nil { presentedFeeling = nil }
                    return
                }
                presentFeelingCheckInIfNeeded()
            }
            .onDisappear {
                hideMoodTask?.cancel()
                hideMoodTask = nil
                dismissPhilReaction(animated: false)
            }
            .task {
                FreezeDiag.log("Home.task start")
                LaunchLog.home("task start")
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
        .sheet(item: feelingItem) { item in
            FeelingCheckInSheet(logId: item.logId, medicine: item.medicine)
        }
        .overlay(alignment: .top) {
            if let gameCelebrate {
                GamificationCelebrateBanner(
                    event: gameCelebrate,
                    streak: lastGameTaken,
                    missedCount: challenge.skippedCount
                )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(1000)
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CheckMedTheme.surface, CheckMedTheme.mintWash],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(CheckMedTheme.primary.opacity(0.10))
                .frame(width: 180, height: 180)
                .offset(x: 38, y: 34)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(session.t(.homeGreetingFormat, greetingWord, greetingName))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(CheckMedTheme.ink)
                        .minimumScaleFactor(0.78)
                    Rectangle()
                        .fill(CheckMedTheme.primary)
                        .frame(width: 44, height: 4)
                        .clipShape(Capsule())
                    Text(session.t(.homeFeelAsk))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Text(session.t(.homeFeelTogether))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
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
                    .offset(y: 12)
            }
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.vertical, 14)

            Button {
                navPath.append(AppRoute.settings)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(CheckMedTheme.surface.opacity(0.92), in: Circle())
                    .shadow(color: CheckMedTheme.ink.opacity(0.08), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(session.t(.profileSettings))
        }
        .frame(minHeight: 190)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch moodPhase {
            case .picker:
                moodPicker
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            case .note:
                if let dailyMood {
                    moodNote(dailyMood)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
            case .hidden:
                EmptyView()
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
    }

    private var moodPicker: some View {
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
                        selectMood(mood)
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
    }

    private func moodNote(_ mood: HomeDailyMood) -> some View {
        Button {
            dismissMoodSection()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(mood.symbol)
                        .font(.system(size: 28))
                        .frame(width: 48, height: 48)
                        .background(mood.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(mood.title(session))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Spacer()
                }
                Text(moodMessage)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var todayStamp: String {
        let comps = session.foundationCalendar.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private var moodAnsweredDateKey: String { "checkmed.homeMood.answeredDate" }

    private func hasAnsweredMoodToday() -> Bool {
        UserDefaults.standard.string(forKey: moodAnsweredDateKey) == todayStamp
    }

    private func markMoodAnsweredToday() {
        UserDefaults.standard.set(todayStamp, forKey: moodAnsweredDateKey)
    }

    private func selectMood(_ mood: HomeDailyMood) {
        let dayOfYear = session.foundationCalendar.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let lastKey = UserDefaults.standard.string(forKey: lastMoodNoteKey(for: mood))
        let picked = mood.noteForDay(session: session, dayOfYear: dayOfYear, lastKeyRaw: lastKey)
        UserDefaults.standard.set(picked.key.rawValue, forKey: lastMoodNoteKey(for: mood))
        markMoodAnsweredToday()
        moodMessage = picked.text
        withAnimation(.easeInOut(duration: 0.38)) {
            dailyMood = mood
            moodPhase = .note
        }
        scheduleMoodSectionHide()
    }

    private func scheduleMoodSectionHide() {
        hideMoodTask?.cancel()
        hideMoodTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            dismissMoodSection()
        }
    }

    private func dismissMoodSection() {
        hideMoodTask?.cancel()
        hideMoodTask = nil
        markMoodAnsweredToday()
        guard moodPhase != .hidden else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            moodPhase = .hidden
        }
    }

    /// Once per calendar day: show picker until answered; after pick + fade, stay hidden until tomorrow.
    private func applyMoodVisibilityForToday(animated: Bool) {
        if hasAnsweredMoodToday() {
            hideMoodTask?.cancel()
            hideMoodTask = nil
            if moodPhase != .hidden {
                if animated {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        moodPhase = .hidden
                    }
                } else {
                    moodPhase = .hidden
                }
            }
            return
        }
        // Mid-note flow: leave the encouragement visible until it fades.
        if moodPhase == .note { return }
        hideMoodTask?.cancel()
        hideMoodTask = nil
        dailyMood = nil
        moodMessage = ""
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                moodPhase = .picker
            }
        } else {
            moodPhase = .picker
        }
    }

    private func resetGamificationSession() {
        gamePrimed = false
        gameCelebrate = nil
        lastGameTaken = -1
        lastGameSkipped = -1
        presentedFeeling = nil
    }

    private func primeGamificationIfNeeded() {
        guard session.restorationComplete, session.isPlanSurfaceReady else { return }
        guard !isPlanVisibilityPending, hasActivePlan else { return }
        let snap = challenge
        let owner = session.planOwnerId
        let profile = session.planProfileId
        let recorded = GamificationMemory.lastDoneSignature(ownerId: owner, profileId: profile)
        let recordedIds = GamificationMemory.doneIds(recorded)
        let currentIds = GamificationMemory.doneIds(snap.doneSignature)
        if gamePrimed {
            if lastGameTaken > snap.takenCount {
                lastGameTaken = snap.takenCount
                lastGameSkipped = snap.skippedCount
            }
            if !recordedIds.isEmpty, currentIds.isDisjoint(with: recordedIds) {
                GamificationMemory.markDoneSignature(ownerId: owner, profileId: profile, signature: snap.doneSignature)
                lastGameTaken = snap.takenCount
                lastGameSkipped = snap.skippedCount
            }
            return
        }
        GamificationMemory.seedIfNeeded(
            ownerId: owner,
            profileId: profile,
            streak: snap.currentStreak,
            dayStamp: todayStamp,
            doneSignature: snap.doneSignature
        )
        lastGameTaken = snap.takenCount
        lastGameSkipped = snap.skippedCount
        gamePrimed = true
        print("[PHIL-DIAG] primed already presented=true signature=\(snap.doneSignature) milestone=\(GamificationMemory.lastMilestone(ownerId: owner, profileId: profile))")
    }

    private func confirmDoseAndCoach(id: String) {
        let pathNodes = path.nodes
        let storeNodes = pathNodes.contains(where: { $0.id == id }) ? [] : treatments.todayNodes()
        let node = pathNodes.first(where: { $0.id == id })
            ?? storeNodes.first(where: { $0.id == id })
        if node?.status == .done { return }
        let wasMissedLike = PhilCoach.wasMissedLikeBeforeConfirm(
            id: id,
            pathNodes: pathNodes,
            storeNodes: storeNodes
        )
        path.take(id: id)
        applyPhilEvent(.doseConfirmed(id: id, wasMissedLike: wasMissedLike))
    }

    private func applyPhilEvent(_ event: PhilEvent) {
        guard gamePrimed, session.restorationComplete, session.isPlanSurfaceReady else {
            #if DEBUG
            print("[PHASE4A-REGRESSION] Phil trigger skipped primed=\(gamePrimed) restore=\(session.restorationComplete) planReady=\(session.isPlanSurfaceReady)")
            #endif
            return
        }
        let snap = challenge
        guard snap.isActive else {
            #if DEBUG
            print("[PHASE4A-REGRESSION] Phil trigger skipped inactive challenge")
            #endif
            return
        }
        let owner = session.planOwnerId
        let profile = session.planProfileId
        var recorded = GamificationMemory.lastDoneSignature(ownerId: owner, profileId: profile)
        let recordedIds = GamificationMemory.doneIds(recorded)
        let currentIds = GamificationMemory.doneIds(snap.doneSignature)
        if !recordedIds.isEmpty, currentIds.isDisjoint(with: recordedIds) {
            recorded = ""
        }
        let memory = PhilCoachMemoryState(
            doneSignature: recorded,
            lastMilestone: GamificationMemory.lastMilestone(ownerId: owner, profileId: profile),
            completeDayStamp: GamificationMemory.didCelebrateComplete(ownerId: owner, profileId: profile, dayStamp: todayStamp) ? todayStamp : "",
            currentDayStamp: todayStamp
        )
        let reaction = PhilCoach.decision(snapshot: snap, event: event, memory: memory)
        lastGameTaken = snap.takenCount
        lastGameSkipped = snap.skippedCount

        #if DEBUG
        if case .doseConfirmed(let doseID, let wasMissedLike) = event {
            print("[PHIL-DIAG] medication confirmation event")
            print("[PHIL-DIAG] dose ID=\(doseID) recovery=\(wasMissedLike)")
            print("[PHIL-DIAG] gamification progress before=\(recorded) after=\(snap.doneSignature)")
            print("[PHIL-DIAG] reaction=\(String(describing: reaction))")
        }
        #endif

        if case .doseConfirmed = event {
            GamificationMemory.markDoneSignature(ownerId: owner, profileId: profile, signature: snap.doneSignature)
            if snap.isComplete {
                GamificationMemory.markComplete(ownerId: owner, profileId: profile, dayStamp: todayStamp)
            }
            if Gamification.reactionMilestones.contains(snap.currentStreak) {
                GamificationMemory.markMilestone(ownerId: owner, profileId: profile, day: snap.currentStreak)
            }
        }

        if let reaction {
            presentGameCelebrate(reaction)
        } else {
            presentFeelingCheckInIfNeeded()
        }
    }

    private func dismissPhilReaction(animated: Bool) {
        hideCelebrateTask?.cancel()
        hideCelebrateTask = nil
        guard gameCelebrate != nil else { return }
        #if DEBUG
        print("[PHASE4A-REGRESSION] Phil cleared")
        #endif
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) {
                gameCelebrate = nil
            }
        } else {
            gameCelebrate = nil
        }
    }

    private func presentGameCelebrate(_ event: GameCelebrate) {
        guard session.selectedMainTab == .home, navPath.isEmpty else {
            print("[PHIL-DIAG] reaction=\(event) skipped not on dashboard")
            #if DEBUG
            print("[PHASE4A-REGRESSION] Phil trigger skipped tab=\(session.selectedMainTab) navCount=\(navPath.count)")
            #endif
            presentFeelingCheckInIfNeeded()
            return
        }
        if gameCelebrate == event { return }
        hideCelebrateTask?.cancel()
        #if DEBUG
        print("[PHASE4A-REGRESSION] Phil triggered \(event)")
        #endif
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            gameCelebrate = event
        }
        hideCelebrateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[PHASE4A-REGRESSION] Phil cleared")
            #endif
            withAnimation(.easeInOut(duration: 0.28)) {
                gameCelebrate = nil
            }
            presentFeelingCheckInIfNeeded()
        }
    }

    private func presentFeelingCheckInIfNeeded() {
        guard gameCelebrate == nil else { return }
        guard presentedFeeling == nil else { return }
        guard let pending = path.pendingFeeling else { return }
        #if DEBUG
        print("[PHASE4A-REGRESSION] feeling sheet triggered")
        #endif
        presentedFeeling = FeelingSheetItem(logId: pending.logId, medicine: pending.medicine)
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
                    if todayMedicines.isEmpty {
                        Text(session.t(.todayNothing))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                    } else {
                        Text(session.t(.homeScheduledRemaining, todayMedicines.count, remainingMedicineCount))
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
            if todayMedicines.isEmpty {
                Text(session.t(.homeBubbleEmpty, greetingName))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(todayMedicines) { row in
                        HStack(spacing: 8) {
                            medicineRow(row)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    navPath.append(AppRoute.medicationDetail(row.id))
                                }
                            if let doseId = row.takeDoseId {
                                Button {
                                    #if DEBUG
                                    print("[PHASE4A-REGRESSION] dose tap medicines id=\(doseId)")
                                    #endif
                                    confirmDoseAndCoach(id: doseId)
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color(hex: 0x5FA86B), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(session.t(.taken))
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
    }

    private var restoringPlanCard: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .tint(CheckMedTheme.primary)
            Text(session.t(.restoringPlan))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
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
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
    }

    private var emptyPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                PhilDoctor2DImage(size: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.t(.noTreatmentInProgressHeadline))
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    Text(session.t(.homeBubbleEmpty, greetingName))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(session.t(.noTreatmentInProgressBody))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
    }

    private func medicineRow(_ row: HomeMedicineRow) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(statusBar(row.status))
                .frame(width: 5, height: 44)
            Text(row.time)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .frame(width: 48, alignment: .leading)
            Image(systemName: "pills.fill")
                .foregroundStyle(CheckMedTheme.flowDot)
                .frame(width: 36, height: 36)
                .background(CheckMedTheme.philFlowCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.medicine)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            statusChip(row)
        }
        .padding(.vertical, 4)
    }

    private func statusChip(_ row: HomeMedicineRow) -> some View {
        let label: String
        let icon: String
        let tint: Color
        switch row.status {
        case .done:
            label = session.t(.taken)
            icon = "checkmark"
            tint = Color(hex: 0x5FA86B)
        case .skipped:
            label = session.t(.missedDidNotTake)
            icon = "minus"
            tint = CheckMedTheme.muted
        case .current:
            label = session.t(.homeStatusPending)
            icon = "clock.fill"
            tint = CheckMedTheme.flowDot
        case .locked:
            label = session.t(.homeStatusUpcoming)
            icon = "clock"
            tint = CheckMedTheme.muted
        }
        // Status badge only — Taken is the row checkmark (next pending dose for this medicine).
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.heavy))
        }
        .foregroundStyle(row.status == .done ? Color.white : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            (row.status == .done ? tint : tint.opacity(0.16)),
            in: Capsule()
        )
        .accessibilityLabel(label)
        .accessibilityHint(row.takeDoseId != nil ? session.t(.taken) : "")
    }

    private func statusBar(_ status: PathStatus) -> Color {
        switch status {
        case .done: Color(hex: 0x5FA86B)
        case .current: CheckMedTheme.flowDot
        case .skipped: CheckMedTheme.skip
        case .locked: CheckMedTheme.locked
        }
    }

    /// Compact Progress glance — full Progress stays on + menu.
    private var progressGlanceLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.progressQuickActions))
                .font(.system(.headline, design: .rounded).weight(.heavy))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                progressActionCard(
                    title: session.t(.progressCalendar),
                    hint: session.t(.progressCalendarHint),
                    icon: "calendar",
                    tint: Color(hex: 0x5FA86B)
                ) { navPath.append(AppRoute.adherence) }
                progressActionCard(
                    title: session.t(.progressHistory),
                    hint: session.t(.progressHistoryHint),
                    icon: "clock.fill",
                    tint: CheckMedTheme.flowDot
                ) { navPath.append(AppRoute.treatmentHistory) }
                progressActionCard(
                    title: session.t(.journeyTitle),
                    hint: session.t(.progressJourneyHint),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: Color(hex: 0x9B7ED9)
                ) { navPath.append(AppRoute.journeyReport) }
                progressActionCard(
                    title: session.t(.progressHeadline),
                    hint: session.t(.progressSubhead),
                    icon: "chart.bar.fill",
                    tint: CheckMedTheme.primaryShadow
                ) { navPath.append(AppRoute.progressDashboard) }
            }
        }
    }

    private func progressActionCard(
        title: String,
        hint: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(hint)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint, in: Circle())
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [CheckMedTheme.surface, tint.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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

    private func lastMoodNoteKey(for mood: HomeDailyMood) -> String {
        "checkmed.homeMood.lastNote.\(mood.rawValue)"
    }

    private var feelingItem: Binding<FeelingSheetItem?> {
        Binding(
            get: { presentedFeeling },
            set: { newValue in
                presentedFeeling = newValue
                if newValue == nil {
                    path.clearPendingFeeling()
                }
            }
        )
    }
}

/// Home dashboard row: one entry per medicine for today (not every dose slot).
private struct HomeMedicineRow: Identifiable {
    let id: UUID
    let medicine: String
    let detail: String
    /// Next pending dose time, or last completed/skipped time when finished for today.
    let time: String
    let status: PathStatus
    /// Earliest pending dose log id — swipe Taken marks this dose.
    let takeDoseId: String?
    let scheduledAt: Date
}

private struct FeelingSheetItem: Identifiable {
    var id: UUID { logId }
    let logId: UUID
    let medicine: String
}
