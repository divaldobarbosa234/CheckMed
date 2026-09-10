import Foundation

@Observable
final class SessionStore {
    enum Kind {
        case welcome
        case guest
        case authenticated
    }

    enum PostAuthKind: Equatable {
        case undetermined
        case newAccount
        case returning
    }

    enum MainTab: Hashable {
        case home
        case treatments
        case progress
        case refill
        case pharmacies
        case reports
        case profile
    }

    let auth = AuthManager()
    private var guestUnlocked = false
    private var localDisplayName = "there"
    private var localCompanionName = "Phil"
    private var localLanguage = AppLocale.english.rawValue
    private var localTimeZone = CheckMedTimeZones.preferred
    private var localBirthDate: Date?
    private var localPronouns = ""
    private var localGender = ""
    private var localNotificationsPrompted = false
    private var localPrivacyAcknowledged = false
    private var localOptionalAnalytics = false
    private var localOptionalMarketing = false
    private var localOnboardingComplete = false
    private var localOnboardingPaywallOffered = false
    private var localFirstTimePhase = "language"
    private var localAppearance = AppearanceMode.light
    private var localIntroSplashSeen = false
    private var localShowWelcomeBack = false

    private enum Keys {
        static let display = "checkmed.displayName"
        static let companion = "checkmed.companionName"
        static let language = "checkmed.language"
        static let timeZone = "checkmed.timeZone"
        static let birthDate = "checkmed.birthDate"
        static let pronouns = "checkmed.pronouns"
        static let gender = "checkmed.gender"
        static let notificationsPrompted = "checkmed.notificationsPrompted"
        static let pendingUpload = "checkmed.profilePendingUpload"
        static let privacyAcknowledged = "checkmed.privacyAcknowledged"
        static let optionalAnalytics = "checkmed.optionalAnalytics"
        static let optionalMarketing = "checkmed.optionalMarketing"
        static let onboardingComplete = "checkmed.onboardingComplete"
        static let onboardingPaywallOffered = "checkmed.onboardingPaywallOffered"
        static let firstTimePhase = "checkmed.firstTimePhase"
        static let appearance = "checkmed.appearanceMode"
        static let introSplashSeen = "checkmed.introSplashSeen"
        static let showWelcomeBack = "checkmed.showWelcomeBack"
    }

    init() {
        if let stored = UserDefaults.standard.string(forKey: Keys.display), !stored.isEmpty {
            localDisplayName = stored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.companion), !stored.isEmpty {
            localCompanionName = stored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.language), !stored.isEmpty {
            localLanguage = AppLocale.fromStored(stored).rawValue
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.timeZone), !stored.isEmpty {
            localTimeZone = CheckMedTimeZones.resolved(stored)
        } else {
            localTimeZone = CheckMedTimeZones.preferred
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.birthDate),
           let date = BirthDateWheels.date(fromStamp: stored) {
            localBirthDate = BirthDateWheels.clampedDate(date)
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.pronouns) {
            localPronouns = stored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.gender) {
            localGender = stored
        }
        localNotificationsPrompted = UserDefaults.standard.bool(forKey: Keys.notificationsPrompted)
        localPrivacyAcknowledged = UserDefaults.standard.bool(forKey: Keys.privacyAcknowledged)
        localOptionalAnalytics = UserDefaults.standard.bool(forKey: Keys.optionalAnalytics)
        localOptionalMarketing = UserDefaults.standard.bool(forKey: Keys.optionalMarketing)
        localOnboardingComplete = UserDefaults.standard.bool(forKey: Keys.onboardingComplete)
        localOnboardingPaywallOffered = UserDefaults.standard.bool(forKey: Keys.onboardingPaywallOffered)
        if let stored = UserDefaults.standard.string(forKey: Keys.firstTimePhase), !stored.isEmpty {
            localFirstTimePhase = stored
        }
        localAppearance = .light
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: Keys.appearance)
        localIntroSplashSeen = UserDefaults.standard.bool(forKey: Keys.introSplashSeen)
        localShowWelcomeBack = UserDefaults.standard.bool(forKey: Keys.showWelcomeBack)
        auth.onBeforeAuthenticated = { [weak self] isRestore in
            self?.preparePostAuth(isRestore: isRestore)
        }
        auth.onAuthenticated = { [weak self] isRestore in
            await self?.handleAuthenticated(isRestore: isRestore)
        }
    }

    func startAuthIfNeeded() {
        auth.start()
    }

    private(set) var profileId: UUID?
    private(set) var isResolvingPostAuth = false
    private(set) var postAuthKind: PostAuthKind = .undetermined
    var selectedMainTab: MainTab = .home
    /// Returning sign-in (not a session restore): miss-you screen before tabs.
    var showReturningWelcome = false
    var showResumeSetup = false
    var startFreshPrescription = false
    var showLeaveHealthWarning = false
    var didOfferUnfinishedPlanThisSession = false
    private var didBackgroundIncompleteSetup = false
    /// First `FirstTimeOnboardingView` bootstrap in this process.
    private static var didHandleLaunchOnboarding = false

    /// Awaits treatment sync and reports whether this owner already has treatments.
    @ObservationIgnored
    var onPostAuthSync: (() async -> Bool)?

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        return .welcome
    }

    var displayName: String {
        if kind == .authenticated, localDisplayName == "there" {
            return auth.displayName
        }
        return localDisplayName
    }

    var companionName: String {
        if kind == .authenticated, localCompanionName == "Phil" {
            return auth.companionName
        }
        return localCompanionName
    }

    var language: String { locale.displayName }
    var locale: AppLocale { AppLocale.fromStored(localLanguage) }
    var timeZoneName: String { localTimeZone }
    var foundationTimeZone: TimeZone {
        TimeZone(identifier: localTimeZone) ?? .current
    }
    var foundationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = foundationTimeZone
        return calendar
    }
    var birthDate: Date? { localBirthDate }
    var pronouns: String { localPronouns }
    var gender: String { localGender }
    var appearance: AppearanceMode { .light }

    /// Pastel light theme is locked so the app does not flip to black or stark white.
    func setAppearance(_ mode: AppearanceMode) {
        localAppearance = .light
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: Keys.appearance)
        _ = mode
    }

    /// Email form title after the user has signed out of an account.
    var showWelcomeBack: Bool { localShowWelcomeBack }

    func markSignedOutForWelcomeBack() {
        localShowWelcomeBack = true
        UserDefaults.standard.set(true, forKey: Keys.showWelcomeBack)
    }

    var hasPreferredName: Bool {
        let name = localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != "there" && name != "friend"
    }

    /// Google/email metadata is not a saved profile. Prefill only.
    var inferredPreferredName: String? {
        let inferred = auth.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inferred.isEmpty, inferred != "there", inferred != "friend" else { return nil }
        return inferred
    }

    var needsCallYouScreen: Bool { !hasPreferredName || localBirthDate == nil }
    var needsAddressYouScreen: Bool {
        localPronouns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || localGender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var needsNotificationsPrompt: Bool { !localNotificationsPrompted }

    /// Policy/terms acknowledgement from Accept. Does not imply analytics or marketing.
    var hasAcknowledgedPrivacy: Bool { localPrivacyAcknowledged }
    var needsPrivacyAcknowledgement: Bool { !localPrivacyAcknowledged }

    var hasCompletedOnboarding: Bool { localOnboardingComplete || perUserOnboardingComplete }
    var firstTimePhaseRaw: String { localFirstTimePhase }
    var shouldPlayIntroSplash: Bool { !localIntroSplashSeen }

    func markIntroSplashSeen() {
        guard !localIntroSplashSeen else { return }
        localIntroSplashSeen = true
        UserDefaults.standard.set(true, forKey: Keys.introSplashSeen)
    }
    var shouldOfferOnboardingPaywall: Bool {
        localOnboardingComplete && !localOnboardingPaywallOffered
    }

    /// Identity fields collected after sign-in (name, DOB, pronouns, gender). Not language.
    var needsIdentityProfile: Bool { needsCallYouScreen || needsAddressYouScreen }

    /// Saved profile has name, date of birth, pronouns, and gender.
    var hasCompleteIdentityProfile: Bool { !needsIdentityProfile }

    var optionalAnalyticsEnabled: Bool { localOptionalAnalytics }
    var optionalMarketingEnabled: Bool { localOptionalMarketing }

    /// Stores Privacy Policy / Terms acknowledgement only. Never enables advertising, analytics, or marketing.
    func acknowledgePrivacy() {
        guard !localPrivacyAcknowledged else { return }
        localPrivacyAcknowledged = true
        UserDefaults.standard.set(true, forKey: Keys.privacyAcknowledged)
    }

    func setOptionalAnalyticsEnabled(_ enabled: Bool) {
        guard enabled != localOptionalAnalytics else { return }
        localOptionalAnalytics = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.optionalAnalytics)
    }

    func setOptionalMarketingEnabled(_ enabled: Bool) {
        guard enabled != localOptionalMarketing else { return }
        localOptionalMarketing = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.optionalMarketing)
    }

    var needsAccountProfile: Bool {
        kind == .authenticated && hasCompletedOnboarding && needsIdentityProfile
    }

    func setFirstTimePhaseRaw(_ raw: String) {
        guard raw != localFirstTimePhase else { return }
        localFirstTimePhase = raw
        UserDefaults.standard.set(raw, forKey: Keys.firstTimePhase)
    }

    /// Cold launch while setup is unfinished: splash → language → how it works → privacy.
    /// Keeps the Apple/Google session; does not jump straight to Add prescription.
    func consumeIncompleteColdLaunchIfNeeded() -> Bool {
        if Self.didHandleLaunchOnboarding { return false }
        Self.didHandleLaunchOnboarding = true
        guard !hasCompletedOnboarding else { return false }
        localIntroSplashSeen = false
        localFirstTimePhase = "language"
        localPrivacyAcknowledged = false
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        return true
    }

    /// Unsigned users always replay splash → language → how it works → privacy → sign-in.
    /// Language and appearance stay. Do not call while a provider sheet is in progress.
    func restartPreAuthOnboarding() {
        guard kind != .authenticated, !auth.isRestoring else { return }
        guestUnlocked = false
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localPrivacyAcknowledged = false
        localFirstTimePhase = "language"
        localIntroSplashSeen = false
        isResolvingPostAuth = false
        postAuthKind = .undetermined
        showReturningWelcome = false
        showResumeSetup = false
        startFreshPrescription = false
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
    }

    func markOnboardingComplete() {
        localOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: Keys.onboardingComplete)
        if let userId = auth.userId {
            UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey(for: userId))
        }
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        localFirstTimePhase = "language"
    }

    func finishReturningWelcome(select tab: MainTab) {
        showReturningWelcome = false
        selectedMainTab = tab
        didOfferUnfinishedPlanThisSession = false
    }

    func needsUnfinishedPlan(treatments: CheckMedStore) -> Bool {
        kind == .authenticated
            && treatments.activeTreatmentCount > 0
            && (needsNotificationsPrompt || !treatments.hasMedicationDaysSet)
    }

    func beginResumeSetup() {
        showReturningWelcome = false
        startFreshPrescription = false
        showResumeSetup = true
        didOfferUnfinishedPlanThisSession = true
    }

    func beginFreshPlan() {
        showReturningWelcome = false
        showResumeSetup = false
        startFreshPrescription = true
        didOfferUnfinishedPlanThisSession = true
    }

    func finishFreshPlan(select tab: MainTab) {
        startFreshPrescription = false
        showResumeSetup = false
        selectedMainTab = tab
    }

    func finishResumeSetup() {
        showResumeSetup = false
        markNotificationsPrompted()
        markOnboardingComplete()
    }

    func noteIncompleteSetupBackground() {
        guard !didBackgroundIncompleteSetup else { return }
        didBackgroundIncompleteSetup = true
        showLeaveHealthWarning = true
        ReminderScheduler.shared.nudgeUnfinishedSetup(locale: locale)
    }

    func clearLeaveHealthWarning() {
        showLeaveHealthWarning = false
    }

    func showHomeTab() {
        selectedMainTab = .home
    }

    func markOnboardingPaywallOffered() {
        guard !localOnboardingPaywallOffered else { return }
        localOnboardingPaywallOffered = true
        UserDefaults.standard.set(true, forKey: Keys.onboardingPaywallOffered)
    }

    func markNotificationsPrompted() {
        guard !localNotificationsPrompted else { return }
        localNotificationsPrompted = true
        UserDefaults.standard.set(true, forKey: Keys.notificationsPrompted)
    }

    func t(_ key: L10n.Key, _ args: CVarArg...) -> String {
        L10n.string(key, locale: locale, args: args)
    }

    var email: String? { auth.email }
    var isGuest: Bool { false }
    var canSync: Bool { kind == .authenticated }
    var supabaseConfigured: Bool { auth.isConfigured }
    var googleConfigured: Bool { auth.isGoogleConfigured }
    var isRestoring: Bool { auth.isRestoring }
    var isLoading: Bool { auth.isLoading }
    var errorMessage: String? { auth.errorMessage }
    var lastAuthNote: String? { auth.statusMessage }

    func continueAsGuest() {
        auth.clearMessages()
        guestUnlocked = false
    }

    func saveOnboardingNames(displayName: String, companionName: String) {
        saveOnboardingProfile(
            displayName: displayName,
            language: localLanguage,
            timeZoneName: localTimeZone,
            birthDate: localBirthDate
        )
        let companion = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        localCompanionName = companion.isEmpty ? "Phil" : companion
        UserDefaults.standard.set(localCompanionName, forKey: Keys.companion)
        queueProfileSync()
    }

    func setDisplayName(_ name: String) {
        let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = display.isEmpty ? "there" : display
        guard next != localDisplayName else { return }
        localDisplayName = next
        UserDefaults.standard.set(localDisplayName, forKey: Keys.display)
        queueProfileSync()
    }

    func setLocale(_ locale: AppLocale) {
        guard locale.rawValue != localLanguage else { return }
        localLanguage = locale.rawValue
        UserDefaults.standard.set(locale.rawValue, forKey: Keys.language)
        queueProfileSync()
    }

    func setLanguage(_ language: String) {
        setLocale(AppLocale.fromStored(language))
    }

    func setTimeZoneName(_ timeZoneName: String) {
        let next = CheckMedTimeZones.resolved(timeZoneName)
        guard next != localTimeZone else { return }
        localTimeZone = next
        UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
        queueProfileSync()
    }

    func setBirthDate(_ date: Date?) {
        let next = date.map(BirthDateWheels.clampedDate)
        let nextStamp = next.map(BirthDateWheels.stamp)
        let currentStamp = localBirthDate.map(BirthDateWheels.stamp)
        guard nextStamp != currentStamp else { return }
        localBirthDate = next
        if let nextStamp {
            UserDefaults.standard.set(nextStamp, forKey: Keys.birthDate)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
        queueProfileSync()
    }

    func setPronouns(_ value: String) {
        let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != localPronouns else { return }
        localPronouns = next
        UserDefaults.standard.set(localPronouns, forKey: Keys.pronouns)
        queueProfileSync()
    }

    func setGender(_ value: String) {
        let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != localGender else { return }
        localGender = next
        UserDefaults.standard.set(localGender, forKey: Keys.gender)
        queueProfileSync()
    }

    func saveAddressing(pronouns: String, gender: String) {
        localPronouns = pronouns.trimmingCharacters(in: .whitespacesAndNewlines)
        localGender = gender.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(localPronouns, forKey: Keys.pronouns)
        UserDefaults.standard.set(localGender, forKey: Keys.gender)
        queueProfileSync()
    }

    func saveOnboardingProfile(
        displayName: String,
        language: String,
        timeZoneName: String,
        birthDate: Date? = nil
    ) {
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        localDisplayName = display.isEmpty ? "there" : display
        localLanguage = AppLocale.fromStored(language).rawValue
        localTimeZone = CheckMedTimeZones.resolved(timeZoneName)
        localBirthDate = birthDate.map(BirthDateWheels.clampedDate)
        UserDefaults.standard.set(localDisplayName, forKey: Keys.display)
        UserDefaults.standard.set(localLanguage, forKey: Keys.language)
        UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
        UserDefaults.standard.set(localCompanionName, forKey: Keys.companion)
        if let localBirthDate {
            UserDefaults.standard.set(BirthDateWheels.stamp(from: localBirthDate), forKey: Keys.birthDate)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
        queueProfileSync()
    }

    func signOut() {
        markSignedOutForWelcomeBack()
        resetFirstTimePathAfterLogout()
        Task { await auth.signOut() }
    }

    /// Splash → language → how it works → privacy → sign-in. Never enables guest.
    /// Identity returns from Supabase on the next sign-in so a new Google/email
    /// account cannot inherit the previous user's name, DOB, or pronouns.
    private func resetFirstTimePathAfterLogout() {
        guestUnlocked = false
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localPrivacyAcknowledged = false
        localNotificationsPrompted = false
        localFirstTimePhase = "language"
        profileId = nil
        isResolvingPostAuth = false
        postAuthKind = .undetermined
        selectedMainTab = .home
        showReturningWelcome = false
        showResumeSetup = false
        startFreshPrescription = false
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        clearLocalIdentity()
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        UserDefaults.standard.removeObject(forKey: Keys.notificationsPrompted)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        localIntroSplashSeen = false
    }

    func deleteAccount() {
        localDisplayName = "there"
        localCompanionName = "Phil"
        localLanguage = AppLocale.english.rawValue
        localTimeZone = CheckMedTimeZones.preferred
        localBirthDate = nil
        UserDefaults.standard.removeObject(forKey: Keys.display)
        UserDefaults.standard.removeObject(forKey: Keys.companion)
        UserDefaults.standard.removeObject(forKey: Keys.language)
        UserDefaults.standard.removeObject(forKey: Keys.timeZone)
        UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        UserDefaults.standard.removeObject(forKey: Keys.pronouns)
        UserDefaults.standard.removeObject(forKey: Keys.gender)
        UserDefaults.standard.removeObject(forKey: Keys.notificationsPrompted)
        UserDefaults.standard.removeObject(forKey: Keys.pendingUpload)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        UserDefaults.standard.removeObject(forKey: Keys.optionalAnalytics)
        UserDefaults.standard.removeObject(forKey: Keys.optionalMarketing)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localFirstTimePhase = "language"
        localIntroSplashSeen = false
        localPronouns = ""
        localGender = ""
        localNotificationsPrompted = false
        localPrivacyAcknowledged = false
        localOptionalAnalytics = false
        localOptionalMarketing = false
        guestUnlocked = false
        profileId = nil
        isResolvingPostAuth = false
        postAuthKind = .undetermined
        selectedMainTab = .home
        showReturningWelcome = false
        showResumeSetup = false
        startFreshPrescription = false
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        if let userId = auth.userId {
            UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey(for: userId))
        }
        Task { await auth.signOut() }
    }

    func requestProvider(_ provider: AuthProvider) {
        switch provider {
        case .apple:
            Task { await auth.signInWithApple() }
        case .google:
            Task { await auth.signInWithGoogle() }
        case .facebook:
            auth.clearMessages()
            auth.presentFacebookUnavailable(t(.facebookUnavailable))
        case .email:
            break
        }
    }

    func signIn(email: String, password: String) async {
        await auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async {
        await auth.signUp(email: email, password: password)
    }

    func resetPassword(email: String) async {
        await auth.resetPassword(email: email)
    }

    private func queueProfileSync() {
        if canSync {
            UserDefaults.standard.set(false, forKey: Keys.pendingUpload)
            Task { await pushProfile() }
        } else {
            UserDefaults.standard.set(true, forKey: Keys.pendingUpload)
        }
    }

    private func preparePostAuth(isRestore: Bool) {
        isResolvingPostAuth = true
        postAuthKind = .undetermined
        showReturningWelcome = false
        showResumeSetup = false
        startFreshPrescription = false
        if !isRestore {
            localOnboardingComplete = false
            UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
            selectedMainTab = .home
        }
    }

    /// New vs returning: signed-in Supabase user + `profiles` name/DOB/pronouns/gender
    /// **and** (per-user `onboardingComplete` or treatments in CheckMedStore/sync).
    /// Incomplete identity always takes the first-time name/pronouns/… path.
    private func handleAuthenticated(isRestore: Bool) async {
        if !isResolvingPostAuth {
            preparePostAuth(isRestore: isRestore)
        }
        defer { isResolvingPostAuth = false }

        let pending = UserDefaults.standard.bool(forKey: Keys.pendingUpload)
        let remote = await pullProfile()
        replaceIdentity(from: remote, overwriteEmpty: !isRestore)
        if !hasPreferredName {
            let inferred = auth.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inferred.isEmpty, inferred != "friend", inferred != "there" {
                setDisplayName(inferred)
            }
        }
        if remote == nil, pending {
            await pushProfile()
            if let pushed = await pullProfile() {
                replaceIdentity(from: pushed, overwriteEmpty: !isRestore)
            }
        } else if isRestore, remote == nil || remoteNeedsPush(remote) {
            await pushProfile()
        }

        let hasTreatments = await syncedHasTreatments()
        let identityComplete = hasCompleteIdentityProfile
        let userOnboarded = perUserOnboardingComplete
        let restoredComplete = isRestore && localOnboardingComplete
        let midFirstTimeSetup = !localOnboardingComplete && isPastIdentityOnboardingStep
        let returning = identityComplete
            && !midFirstTimeSetup
            && (userOnboarded || hasTreatments || restoredComplete)

        if returning {
            if !isRestore {
                selectedMainTab = .progress
                markOnboardingPaywallOffered()
                showReturningWelcome = true
            }
            markOnboardingComplete()
            postAuthKind = .returning
        } else {
            postAuthKind = .newAccount
            selectedMainTab = .home
            if isRestore {
                if !identityComplete, !isPastIdentityOnboardingStep {
                    setFirstTimePhaseRaw(FirstTimePhase.profile.rawValue)
                }
            } else if !isPastIdentityOnboardingStep {
                clearSessionOnboardingFlag()
                setFirstTimePhaseRaw(identityComplete ? FirstTimePhase.addMedication.rawValue : FirstTimePhase.profile.rawValue)
            }
        }
    }

    private var isPastIdentityOnboardingStep: Bool {
        switch FirstTimePhase(rawValue: localFirstTimePhase) {
        case .addMedication, .camera, .manualEntry, .analysing, .confirm, .planResume, .organize, .notifications, .alarmSetup, .trial, .ready:
            true
        default:
            false
        }
    }

    private func syncedHasTreatments() async -> Bool {
        if onPostAuthSync == nil {
            for _ in 0..<30 {
                if onPostAuthSync != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        return await onPostAuthSync?() ?? false
    }

    private var perUserOnboardingComplete: Bool {
        guard let userId = auth.userId else { return false }
        return UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey(for: userId))
    }

    private func clearSessionOnboardingFlag() {
        localOnboardingComplete = false
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
    }

    private static func onboardingCompleteKey(for userId: UUID) -> String {
        "checkmed.onboardingComplete.\(userId.uuidString)"
    }

    private func clearLocalIdentity() {
        localDisplayName = "there"
        localBirthDate = nil
        localPronouns = ""
        localGender = ""
        UserDefaults.standard.removeObject(forKey: Keys.display)
        UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        UserDefaults.standard.removeObject(forKey: Keys.pronouns)
        UserDefaults.standard.removeObject(forKey: Keys.gender)
    }

    /// Remote profile is the source of truth after a fresh sign-in. On session
    /// restore, keep name/DOB/pronouns already saved on this iPhone if the
    /// network row is missing or incomplete — otherwise every relaunch wipes
    /// identity and sends the user back to “How should we call you”.
    private func replaceIdentity(from profile: CheckMedProfile?, overwriteEmpty: Bool) {
        if let name = profile?.displayName?.nilIfEmpty {
            localDisplayName = name
            UserDefaults.standard.set(name, forKey: Keys.display)
        } else if overwriteEmpty {
            localDisplayName = "there"
            UserDefaults.standard.removeObject(forKey: Keys.display)
        }
        if let companion = profile?.companionName.nilIfEmpty {
            localCompanionName = companion
            UserDefaults.standard.set(companion, forKey: Keys.companion)
        }
        if let language = profile?.language?.nilIfEmpty {
            localLanguage = AppLocale.fromStored(language).rawValue
            UserDefaults.standard.set(localLanguage, forKey: Keys.language)
        }
        if let timeZone = profile?.timeZone?.nilIfEmpty {
            localTimeZone = CheckMedTimeZones.resolved(timeZone)
            UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
        }
        if let raw = profile?.dateOfBirth?.nilIfEmpty,
           let date = BirthDateWheels.date(fromStamp: raw) {
            localBirthDate = BirthDateWheels.clampedDate(date)
            UserDefaults.standard.set(BirthDateWheels.stamp(from: localBirthDate!), forKey: Keys.birthDate)
        } else if overwriteEmpty {
            localBirthDate = nil
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
        if let pronouns = profile?.pronouns?.nilIfEmpty {
            localPronouns = pronouns
            UserDefaults.standard.set(pronouns, forKey: Keys.pronouns)
        } else if overwriteEmpty {
            localPronouns = ""
            UserDefaults.standard.removeObject(forKey: Keys.pronouns)
        }
        if let gender = profile?.gender?.nilIfEmpty {
            localGender = gender
            UserDefaults.standard.set(gender, forKey: Keys.gender)
        } else if overwriteEmpty {
            localGender = ""
            UserDefaults.standard.removeObject(forKey: Keys.gender)
        }
        if let id = profile?.id {
            profileId = id
        }
    }

    private func remoteNeedsPush(_ profile: CheckMedProfile?) -> Bool {
        guard hasCompleteIdentityProfile else { return false }
        guard let profile else { return true }
        let nameMissing = profile.displayName?.nilIfEmpty == nil
        let dobMissing = profile.dateOfBirth?.nilIfEmpty == nil
        let pronounsMissing = profile.pronouns?.nilIfEmpty == nil
        let genderMissing = profile.gender?.nilIfEmpty == nil
        return nameMissing || dobMissing || pronounsMissing || genderMissing
    }

    private func pushProfile() async {
        guard canSync, let userId = auth.userId else {
            UserDefaults.standard.set(true, forKey: Keys.pendingUpload)
            return
        }
        let savedName = localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (savedName.isEmpty || savedName == "there" || savedName == "friend") ? nil : savedName
        let profile = CheckMedProfile(
            id: profileId,
            ownerId: userId,
            displayName: name,
            companionName: localCompanionName,
            dateOfBirth: localBirthDate.map(BirthDateWheels.stamp),
            language: localLanguage,
            timeZone: localTimeZone,
            pronouns: localPronouns.nilIfEmpty,
            gender: localGender.nilIfEmpty
        )
        let ok = await auth.upsertProfile(profile)
        UserDefaults.standard.set(!ok, forKey: Keys.pendingUpload)
    }

    @discardableResult
    private func pullProfile() async -> CheckMedProfile? {
        guard canSync else { return nil }
        return await auth.fetchProfile()
    }
}

enum AuthProvider: String {
    case apple, google, facebook, email

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .facebook: "Facebook"
        case .email: "Email"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
