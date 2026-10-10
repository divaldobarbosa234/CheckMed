import Foundation
import UserNotifications

@Observable
final class SessionStore {
    enum Kind {
        case welcome
        case authenticated
    }

    enum UserDataLoadState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed

        var isSettled: Bool {
            self == .loaded || self == .failed
        }
    }

    struct UserDataRestoreResult {
        var hasTreatments: Bool
        var failed: Bool
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

    /// Linear post-journey chain after confirm → journey Continue.
    /// Always: alarms → notifications → trial (unless Super) → Phil → Home.
    enum PostJourneyStep: String, Equatable {
        case alarms
        case notifications
        case trial
        case philReady
        case done

        /// Forward-only order. Leftover trial/permission callbacks must not rewind.
        var rank: Int {
            switch self {
            case .alarms: 0
            case .notifications: 1
            case .trial: 2
            case .philReady: 3
            case .done: 4
            }
        }
    }

    /// Single root UI destination. RootView MUST only switch on this.
    /// Priority (highest first) is encoded in `rootDestination`.
    enum RootDestination: Equatable, CustomStringConvertible {
        case restoring
        case resolvingPostAuth
        case loadError
        case firstTime
        case resumeSetup
        case returningWelcome
        case accountProfile
        case addPrescription
        case home

        var description: String {
            switch self {
            case .restoring: return "restoring"
            case .resolvingPostAuth: return "resolvingPostAuth"
            case .loadError: return "loadError"
            case .firstTime: return "firstTime"
            case .resumeSetup: return "resumeSetup"
            case .returningWelcome: return "returningWelcome"
            case .accountProfile: return "accountProfile"
            case .addPrescription: return "addPrescription"
            case .home: return "home"
            }
        }
    }

    let auth = AuthManager()
    private var localDisplayName = "there"
    private var localCompanionName = "Phil"
    private var localLanguage = AppLocale.english.rawValue
    private var localTimeZone = CheckMedTimeZones.preferred
    private var localBirthDate: Date?
    private var localPronouns = ""
    private var localGender = ""
    private var localNotificationsPrompted = false
    private var localPrivacyAcknowledged = false
    private var localLanguageChosen = false
    private var localHowItWorksSeen = false
    /// User finished the Sign-in screen (Apple, Google, or email) in this install.
    private var localSignInScreenSeen = false
    private var localOptionalAnalytics = false
    private var localOptionalMarketing = false
    private var localOnboardingComplete = false
    private var localOnboardingPaywallOffered = false
    private var localMedicationPlanConfirmed = false
    private var localFirstTimePhase = "language"
    private var localAppearance = AppearanceMode.light
    private var localIntroSplashSeen = false
    private var localShowWelcomeBack = false

    private enum Keys {
        static let display = "checkmed.displayName"
        static let companion = "checkmed.companionName"
        static let language = "checkmed.language"
        static let languageChosen = "checkmed.languageChosen"
        static let howItWorksSeen = "checkmed.howItWorksSeen"
        /// Present only in this install's UserDefaults. Missing after app delete.
        static let preAuthInstallStamp = "checkmed.preAuthInstallStamp"
        /// Forced false on a new container so leftover Keychain session cannot skip Sign-in.
        static let signInScreenSeenThisInstall = "checkmed.signInScreenSeenThisInstall"
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
        /// User confirmed a prescription (onboarding / add / resume). Gates Home doses + alarms.
        static let medicationPlanConfirmed = "checkmed.medicationPlanConfirmed"
        /// One-time wipe of unconfirmed / leftover plans after ownership hardening.
        static let purgedUnconfirmedPlansV1 = "checkmed.purgedUnconfirmedPlans.v1"
        /// Stable on-device owner for leftover pre-auth SwiftData (adopted onto `auth.userId` at sign-in).
        static let localOwnerId = "checkmed.localOwnerId"
        static let localProfileId = "checkmed.localProfileId"
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
        loadPreAuthFlagsFromUserDefaults()
        localOptionalAnalytics = UserDefaults.standard.bool(forKey: Keys.optionalAnalytics)
        localOptionalMarketing = UserDefaults.standard.bool(forKey: Keys.optionalMarketing)
        localOnboardingComplete = UserDefaults.standard.bool(forKey: Keys.onboardingComplete)
        localOnboardingPaywallOffered = UserDefaults.standard.bool(forKey: Keys.onboardingPaywallOffered)
        localMedicationPlanConfirmed = UserDefaults.standard.bool(forKey: Keys.medicationPlanConfirmed)
        if let stored = UserDefaults.standard.string(forKey: Keys.firstTimePhase), !stored.isEmpty {
            localFirstTimePhase = stored
        }
        localAppearance = .light
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: Keys.appearance)
        localIntroSplashSeen = UserDefaults.standard.bool(forKey: Keys.introSplashSeen)
        localShowWelcomeBack = UserDefaults.standard.bool(forKey: Keys.showWelcomeBack)
        // Never copy Keychain onboarded into language / how-it-works / privacy.
        // After delete, wait until sign-in to hydrate ProfileSetupKeychain identity.
        if !CheckMedAuthPersistence.skipRestoreThisProcess {
            hydrateIdentityFromKeychainIfNeeded(userId: nil)
        }
        auth.onAuthenticated = { [weak self] isRestore in
            await self?.enqueueAuthenticated(isRestore: isRestore)
        }
        auth.onSessionCheckFinished = { [weak self] in
            self?.markLaunchSessionKnown()
        }
        LaunchLog.app("Launch ID: \(LaunchLog.launchId)")
        LaunchLog.app("start restoring=\(auth.isRestoring) root=\(computeRootDestination())")
    }

    /// Language / how-it-works / privacy live only in UserDefaults (wiped on delete).
    /// A missing install stamp means a new container — never inherit pre-auth from
    /// Keychain, iCloud profile language, or an older build's privacy-only flag.
    /// Also discard Keychain *session* tokens so delete+reinstall is signed out.
    private func loadPreAuthFlagsFromUserDefaults() {
        let defaults = UserDefaults.standard
        let isNewContainer = defaults.object(forKey: Keys.preAuthInstallStamp) == nil
        if isNewContainer {
            CheckMedAuthPersistence.discardPersistedSession()
            localPrivacyAcknowledged = false
            localLanguageChosen = false
            localHowItWorksSeen = false
            localSignInScreenSeen = false
            localIntroSplashSeen = false
            localFirstTimePhase = "language"
            defaults.removeObject(forKey: Keys.privacyAcknowledged)
            defaults.removeObject(forKey: Keys.languageChosen)
            defaults.removeObject(forKey: Keys.howItWorksSeen)
            defaults.removeObject(forKey: Keys.signInScreenSeenThisInstall)
            defaults.removeObject(forKey: Keys.introSplashSeen)
            defaults.removeObject(forKey: Keys.firstTimePhase)
            defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: Keys.preAuthInstallStamp)
            return
        }
        localPrivacyAcknowledged = defaults.bool(forKey: Keys.privacyAcknowledged)
        localLanguageChosen = defaults.bool(forKey: Keys.languageChosen)
        localHowItWorksSeen = defaults.bool(forKey: Keys.howItWorksSeen)
        localSignInScreenSeen = loadSignInScreenSeen(from: defaults)
    }

    /// New flag: missing on upgrades. Do not force Sign-in again if this install already
    /// passed it (onboarded or a post-sign-in first-time phase). Delete/reinstall never hits this.
    private func loadSignInScreenSeen(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.signInScreenSeenThisInstall) != nil {
            return defaults.bool(forKey: Keys.signInScreenSeenThisInstall)
        }
        if defaults.bool(forKey: Keys.onboardingComplete) { return true }
        let phase = FirstTimePhase(rawValue: defaults.string(forKey: Keys.firstTimePhase) ?? "") ?? .language
        switch phase {
        case .splash, .language, .privacy, .signIn:
            return false
        case .howItWorks:
            // Welcome is after sign-in. A leftover pre-auth How it Works
            // (privacy not accepted yet) must not skip Sign-in.
            return defaults.bool(forKey: Keys.privacyAcknowledged)
        default:
            return true
        }
    }

    func startAuthIfNeeded() {
        auth.start()
    }

    private(set) var profileId: UUID?
    private(set) var isResolvingPostAuth = false
    private(set) var isDeletingAccount = false
    private(set) var userDataLoadState: UserDataLoadState = .notLoaded
    /// Settled restore never treats an empty in-memory array as “new user”.
    private(set) var hasMedicalData = false
    /// Bound identity + local plan visibility have been applied. Home empty vs
    /// treatment is illegal until this is true.
    private(set) var isPlanSurfaceReady = false
    private var lastAuthWasRestore = false
    private(set) var postAuthKind: PostAuthKind = .undetermined
    var selectedMainTab: MainTab = .home
    /// Locked gate: miss-you is not a Google-sign-in destination.
    var showReturningWelcome = false
    /// Sticky miss-you intent for this process. Not set on login or silent restore.
    private var pendingReturningWelcome = false
    /// Once true, do not re-present ReturningWelcome until sign-out / process restart.
    private var showedReturningWelcomeThisSession = false
    var showResumeSetup = false
    var startFreshPrescription = false
    var showLeaveHealthWarning = false
    var didOfferUnfinishedPlanThisSession = false
    /// Armed on confirm (seed/add); becomes an active step queue after journey Continue.
    private var postJourneyArmed = false
    /// Active linear queue. Nil when idle. Never skip notifications for this chain.
    private(set) var postJourneyStep: PostJourneyStep?
    @ObservationIgnored
    private var philReadyFailsafe: Task<Void, Never>?
    @ObservationIgnored
    private var isHandlingAuth = false
    /// Last user whose data restore completed this process (idempotent).
    private var completedRestoreUserId: UUID?
    private var inFlightRestoreId: UUID?
    /// After the launch session is known, `.restoring` must not return this process.
    private var launchRestoreReleased = false
    private var authEventCount = 0
    private var restoreCount = 0
    private var navigationDecisionCount = 0
    /// True while armed or mid-queue (before `.done` is cleared).
    var pendingPostJourneySetup: Bool {
        postJourneyArmed || (postJourneyStep != nil && postJourneyStep != .done)
    }
    private var didBackgroundIncompleteSetup = false
    /// First `FirstTimeOnboardingView` bootstrap in this process.
    private static var didHandleLaunchOnboarding = false
    /// Last logged root destination (DEBUG) — avoid spam when flags re-publish.
    @ObservationIgnored
    private var lastLoggedRootDestination: RootDestination?

    /// Awaits treatment sync and reports whether this owner already has treatments.
    @ObservationIgnored
    var onPostAuthSync: (() async -> UserDataRestoreResult)?
    /// Bind/adopt SwiftData onto the signed-in owner. Sync, no network.
    @ObservationIgnored
    var onBindAuthenticatedIdentity: (() -> Void)?
    /// Local SwiftData already has treatments for the bound owner.
    @ObservationIgnored
    var onLocalTreatmentsCheck: (() -> Bool)?
    /// Persist Phil plan status with the treatments store (SwiftData + Keychain).
    @ObservationIgnored
    var onPhilPlanPersist: ((PhilPlanStatus) -> Void)?

    // MARK: - Single root router

    /// Exactly one destination. RootView switches only on this — no parallel if/else races.
    ///
    /// Priority (highest first):
    /// 1. launch session unknown only (never after `markLaunchSessionKnown`)
    /// 2. pre-auth funnel incomplete (UserDefaults: language→privacy→**sign-in**; Welcome is post-sign-in)
    /// 3. unlocked + active post-journey / resume setup (incomplete plan, after restore)
    /// 4. unlocked + showReturningWelcome (never from Google sign-in)
    /// 5. unlocked + needsIdentityProfile
    /// 6. unlocked + startFreshPrescription (user-initiated only)
    /// 7. unlocked + !onboardingComplete → first-time meds flow
    /// 8. MainTab Home
    ///
    /// Configured users (medicines / plan / report): restore once → Home.
    /// Miss-you is not “you just signed in with Google.”
    var rootDestination: RootDestination {
        computeRootDestination()
    }

    /// Call from RootView when the presented destination may have changed.
    func noteRootDestinationPresented() {
        if !auth.isRestoring {
            markLaunchSessionKnown()
        }
        logRootDestinationIfChanged(computeRootDestination())
    }

    /// Auth finished the launch session check. Replica must not reopen `.restoring`.
    func markLaunchSessionKnown() {
        guard !launchRestoreReleased else { return }
        launchRestoreReleased = true
        LaunchLog.nav("launch restore released — .restoring cannot re-enter")
    }

    private func computeRootDestination() -> RootDestination {
        // `.restoring` is launch-only: unknown session. After the first auth
        // event (or no-session), this process never returns here — including
        // mood taps, Google double-fire, and replica pull.
        if !launchRestoreReleased, auth.isRestoring {
            return .restoring
        }
        if isSessionUnlocked, userDataLoadState == .failed {
            return .loadError
        }
        // Pre-auth is UserDefaults-only. A restored configured account must
        // not replay splash → language → Google while those flags are empty.
        if !isReturningConfiguredUser,
           (!hasFinishedLegalPreAuth || !hasCompletedSignInThisInstall || !isSessionUnlocked) {
            return .firstTime
        }
        if !isSessionUnlocked {
            return .firstTime
        }
        // Interactive Google/Apple: never paint Home from Keychain flags while
        // SwiftData is still empty and replica has not finished.
        if isResolvingPostAuth {
            return .resolvingPostAuth
        }
        // Unlocked is not "data ready". Home must not paint the empty scan
        // state while userDataLoadState is still notLoaded/loading.
        if isSessionUnlocked, !userDataLoadState.isSettled {
            return .resolvingPostAuth
        }
        if isSessionUnlocked, !isPlanSurfaceReady {
            return .resolvingPostAuth
        }

        if let step = postJourneyStep, step != .done {
            return .resumeSetup
        }
        // Armed-only (confirmed, still on Your Journey) must not steal the intake/onboarding host.
        if showResumeSetup {
            return .resumeSetup
        }
        if needsReturningWelcomeGate {
            return .returningWelcome
        }
        if DoseLoop.shouldPresentIdentitySetup(
            needsIdentityProfile: needsIdentityProfile,
            isReturningConfiguredUser: isReturningConfiguredUser
        ) {
            return .accountProfile
        }
        if startFreshPrescription {
            return .addPrescription
        }
        if !hasCompletedOnboarding, !isReturningConfiguredUser {
            return .firstTime
        }

        return .home
    }

    /// True only after interactive returning sign-in, until Progress / Add dismisses miss-you.
    /// Silent Keychain restore and scene resume must not set these flags.
    private var needsReturningWelcomeGate: Bool {
        (pendingReturningWelcome || showReturningWelcome) && !showedReturningWelcomeThisSession
    }

    private func logRootDestinationIfChanged(_ dest: RootDestination) {
        let from = lastLoggedRootDestination
        guard dest != lastLoggedRootDestination else { return }
        lastLoggedRootDestination = dest
        LaunchLog.nav("Determining destination")
        LaunchLog.nav("Destination = \(dest)")
        LaunchLog.nav(
            "Navigating to \(dest) unlocked=\(isSessionUnlocked) load=\(userDataLoadState) "
                + "medical=\(hasMedicalData) restoring=\(auth.isRestoring) resolving=\(isResolvingPostAuth) "
                + "onboarded=\(hasCompletedOnboarding) returning=\(showReturningWelcome) "
                + "authEvents=\(authEventCount) restores=\(restoreCount) navDecisions=\(navigationDecisionCount)"
        )
        #if DEBUG
        printRestoreDiag(
            reason: "DESTINATION CHANGE from=\(from.map(String.init(describing:)) ?? "nil") to=\(dest)"
        )
        #endif
    }

    #if DEBUG
    private func printRestoreDiag(reason: String) {
        print(
            "[RESTORE-DIAG] \(reason) sessionState=\(kind) sessionUserID=\(auth.userId?.uuidString ?? "nil") "
                + "profileLoaded=\(userDataLoadState) profileExists=\(hasRawIdentityFields) "
                + "preferredName=\(hasPreferredName) birthDate=\(localBirthDate != nil) "
                + "treatmentsLoaded=\(userDataLoadState.isSettled) treatmentCount=\(hasMedicalData) "
                + "rootDestination=\(computeRootDestination()) isFirstTime=\(computeRootDestination() == .firstTime) "
                + "isResumeSetup=\(computeRootDestination() == .resumeSetup) isRestoring=\(auth.isRestoring) "
                + "isResolving=\(isResolvingPostAuth) planReady=\(isPlanSurfaceReady) "
                + "returningConfigured=\(isReturningConfiguredUser) needsIdentity=\(needsIdentityProfile)"
        )
        print(
            "[RESTORE-DIAG] PROFILE loaded=\(userDataLoadState.isSettled) exists=\(hasRawIdentityFields || ProfileSetupKeychain.isComplete(for: auth.userId))"
        )
        print(
            "[RESTORE-DIAG] DATA loaded=\(userDataLoadState.isSettled) medicineCount=\(hasMedicalData) treatmentCount=\(hasMedicalData)"
        )
    }
    #endif

    /// True after treatments/profile restore finished (loaded or failed). Home must not start restore.
    var restorationComplete: Bool { userDataLoadState.isSettled }

    /// Call after identity bind + `surfacesPlan` reconciliation. Not from views.
    func notePlanSurfaceReady() {
        guard !isPlanSurfaceReady else { return }
        isPlanSurfaceReady = true
        LaunchLog.restore("plan surface ready medical=\(hasMedicalData)")
    }

    private func resetPlanSurfaceReady() {
        if isPlanSurfaceReady {
            isPlanSurfaceReady = false
        }
    }

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        return .welcome
    }

    /// Signed in with Apple, Google, or email — may continue past sign-in into profile / home.
    var isSessionUnlocked: Bool {
        kind == .authenticated
    }

    /// Auth user id when signed in; otherwise the leftover on-device owner used only to adopt old rows.
    var planOwnerId: UUID {
        auth.userId ?? Self.persistedLocalOwnerId()
    }

    /// Remote profile when synced; otherwise a persisted local profile stamp for leftover SwiftData.
    var planProfileId: UUID {
        profileId ?? Self.persistedLocalProfileId()
    }

    /// Local owner used before sign-in (for adopting leftover device rows onto the auth account).
    var localPlanOwnerId: UUID { Self.persistedLocalOwnerId() }
    /// Device profile stamp used before `profiles.id` exists.
    var localPlanProfileId: UUID { Self.persistedLocalProfileId() }

    private static func persistedLocalOwnerId() -> UUID {
        let key = Keys.localOwnerId
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    private static func persistedLocalProfileId() -> UUID {
        let key = Keys.localProfileId
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    /// Language + privacy Accept, plus Welcome (`howItWorksSeen`) after sign-in.
    /// Welcome stays in the first-time host so RootView does not jump to Profile/Home first.
    /// UserDefaults; wiped on app delete.
    var hasFinishedLegalPreAuth: Bool {
        localLanguageChosen && localHowItWorksSeen && localPrivacyAcknowledged
    }

    /// User completed the Sign-in screen this install (not a silent Keychain restore).
    var hasCompletedSignInThisInstall: Bool { localSignInScreenSeen }

    /// Silent restore of an already-configured account. Not "medicines exist ⇒ skip
    /// onboarding" for a brand-new install — Keychain/onboarding/plan flags only.
    private var isReturningConfiguredUser: Bool {
        guard isSessionUnlocked else { return false }
        if hasCompletedOnboarding { return true }
        if hasConfirmedMedicationPlan { return true }
        if hasMedicalData { return true }
        if ProfileSetupKeychain.isOnboardingComplete(for: auth.userId) { return true }
        if ProfileSetupKeychain.isPlanConfirmed(for: auth.userId) { return true }
        if ProfileSetupKeychain.isComplete(for: auth.userId) { return true }
        return false
    }

    /// Language → privacy → explicit Sign-in, then Welcome. All UserDefaults; wiped on app delete.
    var hasFinishedPreAuthFunnel: Bool {
        hasFinishedLegalPreAuth && hasCompletedSignInThisInstall
    }

    var displayName: String {
        let name = localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEligiblePreferredName(name) {
            return name
        }
        return "there"
    }

    /// Public share cards only. First token of the canonical Preferred name.
    var shareCardFirstName: String? {
        guard hasPreferredName else { return nil }
        let trimmed = localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split { $0.isWhitespace || $0 == "," }.first.map(String.init) ?? trimmed
        let value = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
        isEligiblePreferredName(localDisplayName)
    }

    /// Call You prefill only. Never an email local-part. Never written as Preferred name automatically.
    var inferredPreferredName: String? {
        switch auth.displayNameInference {
        case .friend, .emailLocalPart:
            return nil
        case .providerMetadata, .appleFullName:
            let inferred = auth.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return isEligiblePreferredName(inferred) ? inferred : nil
        }
    }

    /// Exact match to the auth email-prefix seed. Not a word blacklist.
    private func isAuthEmailLocalPart(_ raw: String) -> Bool {
        guard let prefix = auth.emailLocalPartLabel else { return false }
        return raw == prefix
    }

    private func isEligiblePreferredName(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "there" || name == "friend" { return false }
        if name.contains("@") { return false }
        if isAuthEmailLocalPart(name) { return false }
        return true
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
    var hasChosenLanguage: Bool { localLanguageChosen }
    var hasSeenHowItWorks: Bool { localHowItWorksSeen }

    var hasCompletedOnboarding: Bool { localOnboardingComplete || perUserOnboardingComplete }
    /// True only after the user confirms a prescription (seed/add) or finishes resume of their plan.
    var hasConfirmedMedicationPlan: Bool {
        localMedicationPlanConfirmed
            || perUserMedicationPlanConfirmed
            || ProfileSetupKeychain.isPlanConfirmed(for: auth.userId)
    }
    var firstTimePhaseRaw: String { localFirstTimePhase }
    var shouldPlayIntroSplash: Bool { !localIntroSplashSeen }

    func markIntroSplashSeen() {
        guard !localIntroSplashSeen else { return }
        localIntroSplashSeen = true
        UserDefaults.standard.set(true, forKey: Keys.introSplashSeen)
        #if DEBUG
        print("[CheckMed] intro splash marked seen")
        #endif
    }
    var shouldOfferOnboardingPaywall: Bool {
        localOnboardingComplete && !localOnboardingPaywallOffered
    }

    /// Identity fields collected after sign-in (name, DOB, pronouns, gender). Not language.
    /// Keychain completion (survives app delete) short-circuits so reinstall + same
    /// Apple/Google account never replays name → birth → pronouns.
    var needsIdentityProfile: Bool {
        if ProfileSetupKeychain.isComplete(for: auth.userId) { return false }
        if auth.isRestoring, ProfileSetupKeychain.load().isComplete { return false }
        return !hasRawIdentityFields
    }

    /// Saved profile has name, date of birth, pronouns, and gender.
    var hasCompleteIdentityProfile: Bool { !needsIdentityProfile }

    /// Local UserDefaults fields only (ignores Keychain short-circuit).
    private var hasRawIdentityFields: Bool {
        guard hasPreferredName, localBirthDate != nil else { return false }
        let pronouns = localPronouns.trimmingCharacters(in: .whitespacesAndNewlines)
        let gender = localGender.trimmingCharacters(in: .whitespacesAndNewlines)
        return !pronouns.isEmpty && pronouns != ProfilePronoun.custom.rawValue
            && !gender.isEmpty && gender != ProfileGender.custom.rawValue
    }

    /// Persist identity completion in Keychain (and UserDefaults fields already saved).
    func markProfileSetupComplete() {
        let name = localDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ProfileSetupKeychain.markComplete(
            userId: auth.userId,
            displayName: isEligiblePreferredName(name) ? name : nil,
            birthStamp: localBirthDate.map(BirthDateWheels.stamp),
            pronouns: localPronouns.nilIfEmpty,
            gender: localGender.nilIfEmpty
        )
    }

    var optionalAnalyticsEnabled: Bool { localOptionalAnalytics }
    var optionalMarketingEnabled: Bool { localOptionalMarketing }

    /// Stores Privacy Policy / Terms acknowledgement only. Never enables advertising, analytics, or marketing.
    func acknowledgePrivacy() {
        guard !localPrivacyAcknowledged else { return }
        localPrivacyAcknowledged = true
        UserDefaults.standard.set(true, forKey: Keys.privacyAcknowledged)
        #if DEBUG
        print(
            "[CheckMed] privacy accepted → preAuth=\(hasFinishedPreAuthFunnel) "
                + "pendingRW=\(pendingReturningWelcome) showRW=\(showReturningWelcome)"
        )
        #endif
    }

    /// User confirmed a language on the language onboarding screen (not merely a default locale).
    func markLanguageChosen() {
        guard !localLanguageChosen else { return }
        localLanguageChosen = true
        UserDefaults.standard.set(true, forKey: Keys.languageChosen)
        #if DEBUG
        print("[CheckMed] language chosen → preAuth=\(hasFinishedPreAuthFunnel)")
        #endif
    }

    /// User finished How it works (Let's get started).
    func markHowItWorksSeen() {
        guard !localHowItWorksSeen else { return }
        localHowItWorksSeen = true
        UserDefaults.standard.set(true, forKey: Keys.howItWorksSeen)
        #if DEBUG
        print("[CheckMed] how-it-works seen → preAuth=\(hasFinishedPreAuthFunnel)")
        #endif
    }

    /// Call after the user finishes Sign-in, or after silent restore of a
    /// already-configured returning account (so the next launch is not `.firstTime`).
    func markSignInScreenCompleted() {
        guard !localSignInScreenSeen else { return }
        localSignInScreenSeen = true
        UserDefaults.standard.set(true, forKey: Keys.signInScreenSeenThisInstall)
        #if DEBUG
        print("[CheckMed] sign-in screen completed this install → preAuth=\(hasFinishedPreAuthFunnel)")
        #endif
    }

    private func clearSignInScreenSeenThisInstall() {
        localSignInScreenSeen = false
        UserDefaults.standard.removeObject(forKey: Keys.signInScreenSeenThisInstall)
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
        isSessionUnlocked && hasCompletedOnboarding && needsIdentityProfile
    }

    func setFirstTimePhaseRaw(_ raw: String) {
        guard raw != localFirstTimePhase else { return }
        localFirstTimePhase = raw
        UserDefaults.standard.set(raw, forKey: Keys.firstTimePhase)
    }

    /// Cold launch while setup is unfinished.
    /// Pre-auth incomplete → splash → language → how it works → privacy → sign-in.
    /// Keychain onboarded / auth restored must not skip that funnel on a new install.
    func consumeIncompleteColdLaunchIfNeeded() -> Bool {
        if Self.didHandleLaunchOnboarding { return false }
        Self.didHandleLaunchOnboarding = true
        if hasFinishedPreAuthFunnel {
            return false
        }

        localIntroSplashSeen = false
        localFirstTimePhase = "language"
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        return true
    }

    /// Unsigned users always replay splash → language → privacy → sign-in.
    /// Language and appearance stay. Do not call while a provider sheet is in progress.
    func restartPreAuthOnboarding() {
        guard kind != .authenticated, !auth.isRestoring else { return }
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localPrivacyAcknowledged = false
        localLanguageChosen = false
        localHowItWorksSeen = false
        clearSignInScreenSeenThisInstall()
        localFirstTimePhase = "language"
        localIntroSplashSeen = false
        isResolvingPostAuth = false
        userDataLoadState = .notLoaded
        hasMedicalData = false
        resetPlanSurfaceReady()
        completedRestoreUserId = nil
        inFlightRestoreId = nil
        restoreCount = 0
        postAuthKind = .undetermined
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = false
        showResumeSetup = false
        startFreshPrescription = false
        clearPostJourneyQueue()
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        UserDefaults.standard.removeObject(forKey: Keys.languageChosen)
        UserDefaults.standard.removeObject(forKey: Keys.howItWorksSeen)
        UserDefaults.standard.removeObject(forKey: Keys.signInScreenSeenThisInstall)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
    }

    func markOnboardingComplete() {
        localOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: Keys.onboardingComplete)
        if let userId = auth.userId {
            Self.persistPerUserOnboardingComplete(true, userId: userId)
        }
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        localFirstTimePhase = "language"
        showResumeSetup = false
        startFreshPrescription = false
        clearPostJourneyQueue()
        selectedMainTab = .home
    }

    /// After journey for a newly confirmed plan: alarms → notifications → trial → Phil → Home.
    /// True for first-time setup, and for add-prescription that starts a new plan (pending flag).
    var needsPostConfirmSetup: Bool {
        if pendingPostJourneySetup { return true }
        guard hasConfirmedMedicationPlan else { return false }
        return !hasCompletedOnboarding
    }

    /// Call when a new plan is confirmed (first setup or add-prescription seed/add) so the post-journey chain cannot be skipped.
    func markPendingPostJourneySetup() {
        postJourneyArmed = true
    }

    /// Journey Continue: start the linear queue at alarms (always show the screen).
    func startPostJourneyQueue() {
        postJourneyArmed = true
        if postJourneyStep == nil || postJourneyStep == .done {
            setPostJourneyStep(.alarms)
        }
    }

    /// Align queue cursor with the screen currently shown (no debug log spam for same step).
    func syncPostJourneyStep(_ step: PostJourneyStep) {
        if let current = postJourneyStep, current.rank > step.rank {
            return
        }
        postJourneyArmed = true
        guard postJourneyStep != step else { return }
        setPostJourneyStep(step)
    }

    /// Advance one step. Pass `isSuper` so trial is skipped when already subscribed.
    /// Nil / already-done queue must not restart at alarms (Phil double-complete / leftover trial).
    @discardableResult
    func advancePostJourney(isSuper: Bool) -> PostJourneyStep {
        guard let current = postJourneyStep, current != .done else {
            return .done
        }
        let next: PostJourneyStep
        switch current {
        case .alarms:
            next = .notifications
        case .notifications:
            next = isSuper ? .philReady : .trial
        case .trial:
            next = .philReady
        case .philReady, .done:
            next = .done
        }
        setPostJourneyStep(next)
        return next
    }

    func clearPendingPostJourneySetup() {
        clearPostJourneyQueue()
    }

    private func clearPostJourneyQueue() {
        philReadyFailsafe?.cancel()
        philReadyFailsafe = nil
        postJourneyArmed = false
        postJourneyStep = nil
    }

    private func setPostJourneyStep(_ step: PostJourneyStep) {
        postJourneyStep = step
        persistPostJourney(step)
        #if DEBUG
        let label: String
        switch step {
        case .notifications: label = "notifications"
        case .alarms: label = "alarms"
        case .trial: label = "trial"
        case .philReady: label = "phil"
        case .done: label = "home"
        }
        print("[CheckMed] postJourney → \(label)")
        #endif
        if step == .philReady {
            onPhilPlanPersist?(.creating)
        } else {
            philReadyFailsafe?.cancel()
            philReadyFailsafe = nil
        }
        if step == .done {
            onPhilPlanPersist?(.active)
            clearPostJourneyQueue()
        }
    }

    /// Phil auto-continue lives on the Phil-ready screen. Do not force Home from here.
    private func armPhilReadyFailsafe() {}

    /// Kept for back-navigation hints only. Post-journey queue always shows the permission screens.
    func shouldShowNotificationsScreen() async -> Bool {
        true
    }

    func markMedicationPlanConfirmed() {
        localMedicationPlanConfirmed = true
        UserDefaults.standard.set(true, forKey: Keys.medicationPlanConfirmed)
        if let userId = auth.userId {
            UserDefaults.standard.set(true, forKey: Self.medicationPlanConfirmedKey(for: userId))
        }
        ProfileSetupKeychain.markPlanConfirmed(userId: auth.userId)
    }

    func clearMedicationPlanConfirmed() {
        localMedicationPlanConfirmed = false
        UserDefaults.standard.removeObject(forKey: Keys.medicationPlanConfirmed)
        if let userId = auth.userId {
            UserDefaults.standard.removeObject(forKey: Self.medicationPlanConfirmedKey(for: userId))
        }
    }

    /// Device-level one-time migration marker (optionally scoped per owner).
    func didPurgeUnconfirmedPlans(ownerId: UUID?) -> Bool {
        UserDefaults.standard.bool(forKey: Self.purgedUnconfirmedPlansKey(ownerId: ownerId))
    }

    func markDidPurgeUnconfirmedPlans(ownerId: UUID?) {
        UserDefaults.standard.set(true, forKey: Self.purgedUnconfirmedPlansKey(ownerId: ownerId))
    }

    func finishReturningWelcome(select tab: MainTab) {
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = true
        selectedMainTab = tab
        didOfferUnfinishedPlanThisSession = false
        #if DEBUG
        print("[CheckMed] finishReturningWelcome → tab=\(tab)")
        #endif
    }

    /// "This plan still needs you" — only a true abandoned first setup after data is loaded.
    /// Never because SwiftData is empty, sync is late, or sign-out cleared UserDefaults flags.
    func needsUnfinishedPlan(treatments: CheckMedStore) -> Bool {
        guard userDataLoadState.isSettled else { return false }
        guard !hasConfirmedMedicationPlan else { return false }
        guard !hasCompletedOnboarding else { return false }
        return kind == .authenticated && treatments.hasExistingTreatments
    }

    func beginResumeSetup() {
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = true
        startFreshPrescription = false
        showResumeSetup = true
        didOfferUnfinishedPlanThisSession = true
        // Armed but no step yet: ResumePlanSetupFlow shows Your Journey first.
    }

    func beginFreshPlan() {
        // Never open scan/add while identity profile is still required.
        guard !needsIdentityProfile else { return }
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = true
        showResumeSetup = false
        startFreshPrescription = true
        didOfferUnfinishedPlanThisSession = true
        clearMedicationPlanConfirmed()
    }

    func finishFreshPlan(select tab: MainTab) {
        startFreshPrescription = false
        showResumeSetup = false
        selectedMainTab = tab
    }

    func finishResumeSetup() {
        showResumeSetup = false
        startFreshPrescription = false
        showReturningWelcome = false
        pendingReturningWelcome = false
        if postJourneyStep == .philReady {
            setPostJourneyStep(.done)
        } else {
            clearPostJourneyQueue()
            persistPostJourney(nil)
        }
        markNotificationsPrompted()
        markMedicationPlanConfirmed()
        markOnboardingPaywallOffered()
        markOnboardingComplete()
        onPhilPlanPersist?(.active)
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
        if let userId = auth.userId {
            UserDefaults.standard.set(true, forKey: Self.notificationsPromptedKey(for: userId))
        }
    }

    func t(_ key: L10n.Key, _ args: CVarArg...) -> String {
        L10n.string(key, locale: locale, args: args)
    }

    var email: String? { auth.email }
    var canSync: Bool { kind == .authenticated }
    var supabaseConfigured: Bool { auth.isConfigured }
    var googleConfigured: Bool { auth.isGoogleConfigured }
    var isRestoring: Bool { auth.isRestoring }
    var isLoading: Bool { auth.isLoading }
    var hasAppleIdentity: Bool { auth.hasAppleIdentity }
    var errorMessage: String? { auth.errorMessage }
    var lastAuthNote: String? { auth.statusMessage }

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
        if hasRawIdentityFields {
            markProfileSetupComplete()
        }
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

    /// Cloud Auth deletion must succeed before local wipe. Failures stay signed in.
    func deleteAccount(treatments: CheckMedStore, family: FamilyStore) {
        Task { await performAccountDeletion(treatments: treatments, family: family) }
    }

    @MainActor
    private func performAccountDeletion(treatments: CheckMedStore, family: FamilyStore) async {
        guard !isDeletingAccount else { return }
        auth.clearMessages()
        guard kind == .authenticated, let userId = auth.userId else {
            auth.presentError(t(.profileDeleteFailed))
            return
        }
        await auth.refreshAppleIdentityLink()
        var appleAuthorizationCode: String?
        if auth.hasAppleIdentity {
            switch await auth.appleAuthorizationCodeForDeletion() {
            case .success(let code):
                appleAuthorizationCode = code
            case .failure(.cancelled):
                auth.presentError(t(.profileDeleteCancelled))
                return
            case .failure(.failed):
                auth.presentError(t(.profileDeleteFailed))
                return
            }
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        let deletedRemotely = await auth.deleteOwnAuthenticatedAccount(
            appleAuthorizationCode: appleAuthorizationCode
        )
        guard deletedRemotely else {
            auth.presentError(t(.profileDeleteFailed))
            return
        }
        treatments.eraseOwnedLocalData(ownerId: userId)
        treatments.setSurfacesPlan(false)
        treatments.bindIdentity(ownerId: nil, profileId: nil)
        family.clearLocalSeat(for: userId)
        await ReminderScheduler.shared.cancelAllManagedReminders()
        applyLocalDeletionCleanup(userId: userId)
        await auth.clearSessionAfterRemoteAccountDeletion()
    }

    /// Splash → language → how it works → privacy → sign-in.
    /// Identity returns from Supabase on the next sign-in so a new Google/email
    /// account cannot inherit the previous user's name, DOB, or pronouns.
    private func resetFirstTimePathAfterLogout() {
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localPrivacyAcknowledged = false
        localLanguageChosen = false
        localHowItWorksSeen = false
        clearSignInScreenSeenThisInstall()
        localNotificationsPrompted = false
        localFirstTimePhase = "language"
        profileId = nil
        isResolvingPostAuth = false
        userDataLoadState = .notLoaded
        hasMedicalData = false
        resetPlanSurfaceReady()
        postAuthKind = .undetermined
        selectedMainTab = .home
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = false
        showResumeSetup = false
        startFreshPrescription = false
        clearPostJourneyQueue()
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        // Keep Keychain profile/onboarding flags for the same Apple/Google user on re-sign-in.
        // Only clear in-memory / UserDefaults identity so a different account cannot inherit it.
        clearLocalIdentity()
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.privacyAcknowledged)
        UserDefaults.standard.removeObject(forKey: Keys.languageChosen)
        UserDefaults.standard.removeObject(forKey: Keys.howItWorksSeen)
        UserDefaults.standard.removeObject(forKey: Keys.signInScreenSeenThisInstall)
        UserDefaults.standard.removeObject(forKey: Keys.notificationsPrompted)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        UserDefaults.standard.removeObject(forKey: Keys.medicationPlanConfirmed)
        localMedicationPlanConfirmed = false
        localIntroSplashSeen = false
        completedRestoreUserId = nil
        inFlightRestoreId = nil
        restoreCount = 0
    }

    private func applyLocalDeletionCleanup(userId: UUID) {
        markSignedOutForWelcomeBack()
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
        UserDefaults.standard.removeObject(forKey: Keys.languageChosen)
        UserDefaults.standard.removeObject(forKey: Keys.howItWorksSeen)
        UserDefaults.standard.removeObject(forKey: Keys.signInScreenSeenThisInstall)
        UserDefaults.standard.removeObject(forKey: Keys.optionalAnalytics)
        UserDefaults.standard.removeObject(forKey: Keys.optionalMarketing)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.onboardingPaywallOffered)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        UserDefaults.standard.removeObject(forKey: Keys.introSplashSeen)
        UserDefaults.standard.removeObject(forKey: Keys.medicationPlanConfirmed)
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localMedicationPlanConfirmed = false
        localFirstTimePhase = "language"
        localIntroSplashSeen = false
        localPronouns = ""
        localGender = ""
        localNotificationsPrompted = false
        localPrivacyAcknowledged = false
        localLanguageChosen = false
        localHowItWorksSeen = false
        clearSignInScreenSeenThisInstall()
        localOptionalAnalytics = false
        localOptionalMarketing = false
        profileId = nil
        isResolvingPostAuth = false
        userDataLoadState = .notLoaded
        hasMedicalData = false
        resetPlanSurfaceReady()
        postAuthKind = .undetermined
        selectedMainTab = .home
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = false
        showResumeSetup = false
        startFreshPrescription = false
        clearPostJourneyQueue()
        didOfferUnfinishedPlanThisSession = false
        didBackgroundIncompleteSetup = false
        completedRestoreUserId = nil
        inFlightRestoreId = nil
        restoreCount = 0
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey(for: userId))
        UserDefaults.standard.removeObject(forKey: Self.medicationPlanConfirmedKey(for: userId))
        ProfileSetupKeychain.clear(for: userId)
    }

    func requestProvider(_ provider: AuthProvider) {
        switch provider {
        case .apple:
            Task { await auth.signInWithApple() }
        case .google:
            LaunchLog.auth("Google button tapped")
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
        // Do not set `.loading` here — that used to flip RootView back to
        // `.restoring` after Home. Replica runs in the background.
        lastAuthWasRestore = isRestore
        showReturningWelcome = false
        pendingReturningWelcome = false
        startFreshPrescription = false
        if !pendingPostJourneySetup {
            showResumeSetup = false
        }
        if !isRestore {
            selectedMainTab = .home
        }
        LaunchLog.auth("preparePostAuth restore=\(isRestore)")
    }

    private func enqueueAuthenticated(isRestore: Bool) async {
        authEventCount += 1
        LaunchLog.auth(
            "coordinator event count=\(authEventCount) restoreFlag=\(isRestore) "
                + "user=\(auth.userId?.uuidString ?? "nil")"
        )
        if isHandlingAuth || inFlightRestoreId != nil {
            LaunchLog.auth("skip duplicate restore (already in flight) restoreCount=\(restoreCount)")
            return
        }
        if completedRestoreUserId != nil,
           completedRestoreUserId == auth.userId,
           userDataLoadState.isSettled {
            LaunchLog.auth("skip duplicate restore user=\(auth.userId?.uuidString ?? "nil") restoreCount=\(restoreCount)")
            return
        }
        isHandlingAuth = true
        await handleAuthenticated(isRestore: isRestore)
        isHandlingAuth = false
    }

    /// New vs returning after sign-in / session restore.
    /// Session-known first: hydrate Keychain / local flags, route, then replica in background.
    /// Empty SwiftData while replica runs is not a new user.
    /// Configured users (medicines / plan / report) go Home — not miss-you.
    private func handleAuthenticated(isRestore: Bool) async {
        markLaunchSessionKnown()
        if !isResolvingPostAuth {
            preparePostAuth(isRestore: isRestore)
        }
        if !isRestore {
            markSignInScreenCompleted()
        }

        let restoreId = UUID()
        inFlightRestoreId = restoreId
        restoreCount += 1
        LaunchLog.restore("ENTER id=\(restoreId.uuidString) count=\(restoreCount)")
        if restoreCount > 1 {
            LaunchLog.restore("WARNING restoreCount>1 id=\(restoreId.uuidString) — duplicate restore")
        }
        LaunchLog.restore("START id=\(restoreId.uuidString)")
        defer {
            if inFlightRestoreId == restoreId {
                inFlightRestoreId = nil
            }
            isResolvingPostAuth = false
            LaunchLog.restore("EXIT id=\(restoreId.uuidString) restoreCount=\(restoreCount)")
            #if DEBUG
            printRestoreDiag(reason: "handleAuthenticated EXIT")
            #endif
        }

        onBindAuthenticatedIdentity?()
        if let userId = auth.userId {
            ProfileSetupKeychain.associateUserIfNeeded(userId)
            hydrateIdentityFromKeychainIfNeeded(userId: userId)
        }
        if hasRawIdentityFields {
            markProfileSetupComplete()
        }
        hydratePlanFlagsFromPersistence()
        restorePersistedPostJourneyIfNeeded()

        let hasLocal = onLocalTreatmentsCheck?() ?? false
        hasMedicalData = hasMedicalData || hasLocal
        if isReturningConfiguredUser {
            markSignInScreenCompleted()
        }
        LaunchLog.auth(
            "Current user loaded user=\(auth.userId?.uuidString ?? "nil") medicalLocal=\(hasLocal)"
        )

        var replicaFailed = false
        if hasLocal {
            userDataLoadState = .loaded
            LaunchLog.restore(
                "SETTLED-LOCAL id=\(restoreId.uuidString) medical=\(hasMedicalData) — replica continues in background"
            )
            let restoreFlag = isRestore
            Task { await self.hydrateRemoteProfileAndReplica(isRestore: restoreFlag) }
        } else {
            LaunchLog.nav("Determining destination — waiting for replica (no local treatments)")
            replicaFailed = await hydrateRemoteProfileAndReplica(isRestore: isRestore)
            if replicaFailed && !hasMedicalData {
                userDataLoadState = .failed
            } else {
                userDataLoadState = .loaded
            }
        }
        completedRestoreUserId = auth.userId

        let identityComplete = hasCompleteIdentityProfile
        let keychainProfile = ProfileSetupKeychain.isComplete(for: auth.userId)
        let keychainOnboarded = ProfileSetupKeychain.isOnboardingComplete(for: auth.userId)
        let keychainPlan = ProfileSetupKeychain.isPlanConfirmed(for: auth.userId)
        let previouslyOnboarded = perUserOnboardingComplete
            || keychainOnboarded
            || keychainProfile
            || keychainPlan
            || (isRestore && localOnboardingComplete)
            || hasConfirmedMedicationPlan
            || hasMedicalData

        startFreshPrescription = false
        decidePostRestoreRoute(
            hasTreatments: hasMedicalData,
            failed: replicaFailed && !hasMedicalData,
            previouslyOnboarded: previouslyOnboarded,
            identityComplete: identityComplete,
            keychainProfile: keychainProfile,
            keychainOnboarded: keychainOnboarded,
            isRestore: isRestore
        )
        LaunchLog.nav("Destination = \(computeRootDestination())")
        LaunchLog.nav("Navigating to \(computeRootDestination())")
    }

    /// Profile + replica. Does not change `rootDestination` — caller decides once.
    @discardableResult
    private func hydrateRemoteProfileAndReplica(isRestore: Bool) async -> Bool {
        let pending = UserDefaults.standard.bool(forKey: Keys.pendingUpload)
        let remote = await pullProfile()
        if Task.isCancelled { return false }
        LaunchLog.auth("Profile loaded present=\(remote != nil) user=\(auth.userId?.uuidString ?? "nil")")
        replaceIdentity(from: remote, overwriteEmpty: !isRestore)
        if let userId = auth.userId {
            ProfileSetupKeychain.associateUserIfNeeded(userId)
            hydrateIdentityFromKeychainIfNeeded(userId: userId)
        }
        if remote == nil, pending {
            Task { await pushProfile() }
        } else if isRestore, remote == nil || remoteNeedsPush(remote) {
            Task { await pushProfile() }
        }
        if hasRawIdentityFields {
            markProfileSetupComplete()
        }

        let restore = await restoreUserData()
        if Task.isCancelled { return restore.failed }
        if restore.hasTreatments {
            markMedicationPlanConfirmed()
        }
        hasMedicalData = hasMedicalData || restore.hasTreatments
        restorePersistedPostJourneyIfNeeded()

        if restore.failed {
            LaunchLog.restore("replica pull failed keepLocal medical=\(hasMedicalData)")
        } else {
            LaunchLog.restore("replica pull ok medical=\(hasMedicalData) treatments=\(restore.hasTreatments)")
        }
        return restore.failed && !hasMedicalData
    }

    /// One navigation decision after restorationComplete. Child views must not navigate globally.
    private func decidePostRestoreRoute(
        hasTreatments: Bool,
        failed: Bool,
        previouslyOnboarded: Bool,
        identityComplete: Bool,
        keychainProfile: Bool,
        keychainOnboarded: Bool,
        isRestore: Bool
    ) {
        navigationDecisionCount += 1
        pendingReturningWelcome = false
        showReturningWelcome = false
        startFreshPrescription = false
        LaunchLog.nav(
            "decision=#\(navigationDecisionCount) medical=\(hasTreatments) failed=\(failed) "
                + "onboarded=\(previouslyOnboarded) restore=\(isRestore) "
                + "authEvents=\(authEventCount) restores=\(restoreCount)"
        )
        if failed {
            return
        }
        if pendingPostJourneySetup {
            postAuthKind = .returning
            showResumeSetup = true
            LaunchLog.nav("decision=#\(navigationDecisionCount) resumeSetup (post-journey)")
            return
        }
        if previouslyOnboarded || hasTreatments {
            enterReturningAfterAuth(
                hasTreatments: hasTreatments,
                keychainProfile: keychainProfile,
                keychainOnboarded: keychainOnboarded
            )
            return
        }

        postAuthKind = .newAccount
        selectedMainTab = .home
        guard hasFinishedPreAuthFunnel else {
            LaunchLog.auth("newAccount waiting pre-auth phase=\(localFirstTimePhase)")
            return
        }
        if !isRestore {
            clearSessionOnboardingFlag()
            if !identityComplete {
                setFirstTimePhaseRaw(FirstTimePhase.profile.rawValue)
            } else {
                setFirstTimePhaseRaw(FirstTimePhase.addMedication.rawValue)
            }
        } else if !identityComplete {
            setFirstTimePhaseRaw(FirstTimePhase.profile.rawValue)
        }
        LaunchLog.auth("newAccount phase=\(localFirstTimePhase) identity=\(identityComplete) restore=\(isRestore)")
    }

    /// After the user finishes Sign-in, branch Home vs profile. Never miss-you.
    private func branchAfterSignInScreenIfNeeded() {
        let keychainProfile = ProfileSetupKeychain.isComplete(for: auth.userId)
            || ProfileSetupKeychain.load().isComplete
        let keychainOnboarded = ProfileSetupKeychain.isOnboardingComplete(for: auth.userId)
            || ProfileSetupKeychain.isOnboardingComplete(for: nil)
        if keychainProfile || keychainOnboarded || localOnboardingComplete || perUserOnboardingComplete || hasMedicalData {
            enterReturningAfterAuth(
                hasTreatments: hasMedicalData,
                keychainProfile: keychainProfile,
                keychainOnboarded: keychainOnboarded
            )
            return
        }
        postAuthKind = .newAccount
    }

    /// Already-unlocked user taps Apple/Google/Continue on Sign-in.
    /// Marks this-install Sign-in only. Does not restore or present miss-you.
    func confirmRestoredAccountOnSignInScreen() {
        guard isSessionUnlocked else { return }
        markSignInScreenCompleted()
        guard userDataLoadState.isSettled else { return }
        branchAfterSignInScreenIfNeeded()
    }

    /// Configured / returning users → Home. Miss-you is not a login destination.
    private func enterReturningAfterAuth(
        hasTreatments: Bool,
        keychainProfile: Bool,
        keychainOnboarded: Bool
    ) {
        postAuthKind = .returning
        startFreshPrescription = false
        pendingReturningWelcome = false
        showReturningWelcome = false
        clearStaleFirstTimePhaseForReturning()

        if pendingPostJourneySetup {
            showResumeSetup = true
            LaunchLog.auth("returning post-journey treatments=\(hasTreatments)")
            return
        }

        selectedMainTab = .home
        showResumeSetup = false
        markOnboardingPaywallOffered()
        markOnboardingComplete()
        LaunchLog.auth(
            "returning home treatments=\(hasTreatments) "
                + "keychainProfile=\(keychainProfile) keychainOnboarded=\(keychainOnboarded)"
        )
    }

    /// Returning users must not resume into Adicionar receita via saved firstTimePhase.
    private func clearStaleFirstTimePhaseForReturning() {
        let saved = FirstTimePhase(rawValue: localFirstTimePhase) ?? .language
        switch saved {
        case .addMedication, .camera, .manualEntry, .analysing, .confirm, .planResume,
             .organize, .notifications, .alarmSetup, .trial, .ready, .profile, .signIn:
            localFirstTimePhase = "language"
            UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        default:
            break
        }
    }

    private func restoreUserData() async -> UserDataRestoreResult {
        if let onPostAuthSync {
            return await onPostAuthSync()
        }
        let hasLocal = onLocalTreatmentsCheck?() ?? false
        if kind == .authenticated {
            LaunchLog.error("restore callback missing; using local only has=\(hasLocal)")
        }
        return UserDataRestoreResult(hasTreatments: hasLocal, failed: false)
    }

    func retryUserDataLoad() {
        guard kind == .authenticated else { return }
        completedRestoreUserId = nil
        inFlightRestoreId = nil
        resetPlanSurfaceReady()
        LaunchLog.data("retry user data load")
        Task { await enqueueAuthenticated(isRestore: lastAuthWasRestore) }
    }

    func noteLocalDataBound() {
        guard kind != .authenticated else { return }
        // Session restore is still in flight — do not mark loaded from a
        // welcome bind or Home will treat an empty store as final.
        guard !auth.isRestoring else { return }
        guard userDataLoadState != .failed, userDataLoadState != .loading else { return }
        let hasLocal = onLocalTreatmentsCheck?() ?? false
        hasMedicalData = hasLocal
        userDataLoadState = .loaded
    }

    private func hydratePlanFlagsFromPersistence() {
        let userId = auth.userId
        if perUserMedicationPlanConfirmed || ProfileSetupKeychain.isPlanConfirmed(for: userId) {
            localMedicationPlanConfirmed = true
            UserDefaults.standard.set(true, forKey: Keys.medicationPlanConfirmed)
        }
        if let userId, UserDefaults.standard.bool(forKey: Self.notificationsPromptedKey(for: userId)) {
            localNotificationsPrompted = true
            UserDefaults.standard.set(true, forKey: Keys.notificationsPrompted)
        }
    }

    private func restorePersistedPostJourneyIfNeeded() {
        if hasCompletedOnboarding && hasConfirmedMedicationPlan {
            persistPostJourney(nil)
            return
        }
        guard postJourneyStep == nil || postJourneyStep == .done else { return }
        let userId = auth.userId
        let raw = (userId.flatMap { UserDefaults.standard.string(forKey: Self.postJourneyKey(for: $0)) })
            ?? ProfileSetupKeychain.persistedPostJourneyStep(for: userId)
        guard let raw, let step = PostJourneyStep(rawValue: raw), step != .done else { return }
        postJourneyArmed = true
        postJourneyStep = step
        showResumeSetup = true
    }

    private func persistPostJourney(_ step: PostJourneyStep?) {
        let raw: String? = {
            guard let step, step != .done else { return nil }
            return step.rawValue
        }()
        ProfileSetupKeychain.persistPostJourneyStep(raw, userId: auth.userId)
        if let userId = auth.userId {
            if let raw {
                UserDefaults.standard.set(raw, forKey: Self.postJourneyKey(for: userId))
            } else {
                UserDefaults.standard.removeObject(forKey: Self.postJourneyKey(for: userId))
            }
        }
    }

    private var perUserOnboardingComplete: Bool {
        guard let userId = auth.userId else {
            return ProfileSetupKeychain.isOnboardingComplete(for: nil)
        }
        let defaults = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey(for: userId))
        if defaults { return true }
        guard ProfileSetupKeychain.isOnboardingComplete(for: userId) else { return false }
        // Mirror into UserDefaults only after this install finished pre-auth.
        // Never treat Keychain onboarded as language / how-it-works / privacy done.
        if hasFinishedPreAuthFunnel {
            UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey(for: userId))
        }
        return true
    }

    private static func persistPerUserOnboardingComplete(_ complete: Bool, userId: UUID) {
        let key = onboardingCompleteKey(for: userId)
        if complete {
            UserDefaults.standard.set(true, forKey: key)
            ProfileSetupKeychain.markOnboardingComplete(userId: userId)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private var perUserMedicationPlanConfirmed: Bool {
        guard let userId = auth.userId else { return false }
        return UserDefaults.standard.bool(forKey: Self.medicationPlanConfirmedKey(for: userId))
    }

    private func clearSessionOnboardingFlag() {
        localOnboardingComplete = false
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
    }

    private static func onboardingCompleteKey(for userId: UUID) -> String {
        "checkmed.onboardingComplete.\(userId.uuidString)"
    }

    private static func medicationPlanConfirmedKey(for userId: UUID) -> String {
        "checkmed.medicationPlanConfirmed.\(userId.uuidString)"
    }

    private static func notificationsPromptedKey(for userId: UUID) -> String {
        "checkmed.notificationsPrompted.\(userId.uuidString)"
    }

    private static func postJourneyKey(for userId: UUID) -> String {
        "checkmed.postJourneyStep.\(userId.uuidString)"
    }

    private static func purgedUnconfirmedPlansKey(ownerId: UUID?) -> String {
        if let ownerId {
            return "\(Keys.purgedUnconfirmedPlansV1).\(ownerId.uuidString)"
        }
        return Keys.purgedUnconfirmedPlansV1
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

    /// After sign-in, restore name/DOB from ProfileSetupKeychain so a returning
    /// Apple/Google account can miss-you instead of replaying profile setup.
    private func hydrateIdentityFromKeychainIfNeeded(userId: UUID?) {
        let snap = ProfileSetupKeychain.load()
        guard snap.isComplete else { return }
        if let userId {
            guard ProfileSetupKeychain.isComplete(for: userId) else { return }
        }

        if !hasPreferredName, let name = snap.displayName, isEligiblePreferredName(name) {
            localDisplayName = name
            UserDefaults.standard.set(name, forKey: Keys.display)
        }
        if localBirthDate == nil,
           let stamp = snap.birthStamp?.nilIfEmpty,
           let date = BirthDateWheels.date(fromStamp: stamp) {
            localBirthDate = BirthDateWheels.clampedDate(date)
            UserDefaults.standard.set(BirthDateWheels.stamp(from: localBirthDate!), forKey: Keys.birthDate)
        }
        if localPronouns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pronouns = snap.pronouns?.nilIfEmpty {
            localPronouns = pronouns
            UserDefaults.standard.set(pronouns, forKey: Keys.pronouns)
        }
        if localGender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let gender = snap.gender?.nilIfEmpty {
            localGender = gender
            UserDefaults.standard.set(gender, forKey: Keys.gender)
        }
    }

    /// Remote profile is the source of truth after a fresh sign-in. On session
    /// restore, keep name/DOB/pronouns already saved on this iPhone if the
    /// network row is missing or incomplete — otherwise every relaunch wipes
    /// identity and sends the user back to “How should we call you”.
    private func replaceIdentity(from profile: CheckMedProfile?, overwriteEmpty: Bool) {
        // Never wipe local/Keychain-backed identity when the remote row is incomplete.
        let protectIdentity = ProfileSetupKeychain.isComplete(for: auth.userId) || hasRawIdentityFields
        let wipeEmpty = overwriteEmpty && !protectIdentity

        if let name = profile?.displayName, isEligiblePreferredName(name) {
            localDisplayName = name
            UserDefaults.standard.set(name, forKey: Keys.display)
        } else if isEligiblePreferredName(localDisplayName) {
            // Keep an explicit Preferred name. Polluted remote email-prefix must not overwrite it.
        } else if wipeEmpty {
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
        } else if wipeEmpty {
            localBirthDate = nil
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
        if let pronouns = profile?.pronouns?.nilIfEmpty {
            localPronouns = pronouns
            UserDefaults.standard.set(pronouns, forKey: Keys.pronouns)
        } else if wipeEmpty {
            localPronouns = ""
            UserDefaults.standard.removeObject(forKey: Keys.pronouns)
        }
        if let gender = profile?.gender?.nilIfEmpty {
            localGender = gender
            UserDefaults.standard.set(gender, forKey: Keys.gender)
        } else if wipeEmpty {
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
        let nameMissing = !isEligiblePreferredName(profile.displayName)
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
        let name = isEligiblePreferredName(savedName) ? savedName : nil
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
