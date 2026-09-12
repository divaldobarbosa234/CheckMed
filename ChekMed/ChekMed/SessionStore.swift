import Foundation
import UserNotifications

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

    /// Linear post-journey chain after confirm → journey Continue.
    /// Always: notifications → alarms → trial (unless Super) → Phil → Home.
    enum PostJourneyStep: String, Equatable {
        case notifications
        case alarms
        case trial
        case philReady
        case done
    }

    /// Single root UI destination. RootView MUST only switch on this.
    /// Priority (highest first) is encoded in `rootDestination`.
    enum RootDestination: Equatable, CustomStringConvertible {
        case restoring
        case resolvingPostAuth
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
    private var localLanguageChosen = false
    private var localHowItWorksSeen = false
    /// User finished the Sign-in screen (provider, email, or guest) in this install.
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
        /// Stable on-device owner for guest / pre-auth local plans (SwiftData requires non-nil owner).
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
        auth.onBeforeAuthenticated = { [weak self] isRestore in
            self?.preparePostAuth(isRestore: isRestore)
        }
        auth.onAuthenticated = { [weak self] isRestore in
            await self?.handleAuthenticated(isRestore: isRestore)
        }
        #if DEBUG
        print(
            "[CheckMed] preAuth init langChosen=\(localLanguageChosen) "
                + "howItWorks=\(localHowItWorksSeen) privacy=\(localPrivacyAcknowledged) "
                + "signInSeen=\(localSignInScreenSeen) "
                + "preAuth=\(hasFinishedPreAuthFunnel) "
                + "root=\(computeRootDestination()) "
                + "keychainOnboarded=\(ProfileSetupKeychain.isOnboardingComplete(for: nil)) "
                + "keychainProfile=\(ProfileSetupKeychain.load().isComplete)"
        )
        #endif
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
        case .splash, .language, .howItWorks, .privacy, .signIn:
            return false
        default:
            return true
        }
    }

    func startAuthIfNeeded() {
        auth.start()
    }

    private(set) var profileId: UUID?
    private(set) var isResolvingPostAuth = false
    private(set) var postAuthKind: PostAuthKind = .undetermined
    var selectedMainTab: MainTab = .home
    /// Locked gate: onboarded returning user sees miss-you once per process before Home.
    var showReturningWelcome = false
    /// Sticky miss-you intent for this process. `preparePostAuth` must never clear this —
    /// that race was splash→Home after delete+reinstall (auth restore cleared the soft flag).
    private var pendingReturningWelcome = false
    /// Once true, do not re-present ReturningWelcome until sign-out / process restart.
    /// Always starts false each process (in-memory only).
    private var showedReturningWelcomeThisSession = false
    var showResumeSetup = false
    var startFreshPrescription = false
    var showLeaveHealthWarning = false
    var didOfferUnfinishedPlanThisSession = false
    /// Armed on confirm (seed/add); becomes an active step queue after journey Continue.
    private var postJourneyArmed = false
    /// Active linear queue. Nil when idle. Never skip notifications for this chain.
    private(set) var postJourneyStep: PostJourneyStep?
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
    var onPostAuthSync: (() async -> Bool)?

    // MARK: - Single root router

    /// Exactly one destination. RootView switches only on this — no parallel if/else races.
    ///
    /// Priority (highest first):
    /// 1. pre-auth funnel incomplete (UserDefaults: language→howItWorks→privacy→**sign-in**)
    /// 2. auth restoring / post-auth resolving
    /// 3. unlocked + active post-journey / resume setup
    /// 4. unlocked + showReturningWelcome (miss-you)
    /// 5. unlocked + needsIdentityProfile
    /// 6. unlocked + startFreshPrescription (user-initiated only)
    /// 7. unlocked + !onboardingComplete → first-time meds flow
    /// 8. MainTab Home
    ///
    /// Delete+reinstall: session tokens cleared; user is signed out until Sign-in.
    /// Then ProfileSetupKeychain → miss-you (old account) or name/birth (new).
    var rootDestination: RootDestination {
        computeRootDestination()
    }

    /// Call from RootView when the presented destination may have changed.
    func noteRootDestinationPresented() {
        logRootDestinationIfChanged(computeRootDestination())
    }

    private func computeRootDestination() -> RootDestination {
        // Pre-auth is UserDefaults-only. Hold miss-you / profile / Home until
        // language, how-it-works, privacy, AND this-install Sign-in are done.
        if !hasFinishedLegalPreAuth || !hasCompletedSignInThisInstall {
            return .firstTime
        }
        if auth.isRestoring { return .restoring }
        if isResolvingPostAuth, isSessionUnlocked { return .resolvingPostAuth }
        if !isSessionUnlocked {
            return .firstTime
        }

        if let step = postJourneyStep, step != .done {
            return .resumeSetup
        }
        if showResumeSetup || pendingPostJourneySetup {
            return .resumeSetup
        }
        // Returning onboarded: miss-you BEFORE Home, once per cold start.
        if needsReturningWelcomeGate {
            return .returningWelcome
        }
        if needsIdentityProfile {
            return .accountProfile
        }
        if startFreshPrescription {
            return .addPrescription
        }
        if !hasCompletedOnboarding {
            return .firstTime
        }

        return .home
    }

    /// True when a returning (Keychain/onboarded) user must see miss-you before Home this process.
    private var needsReturningWelcomeGate: Bool {
        (pendingReturningWelcome || showReturningWelcome) && !showedReturningWelcomeThisSession
    }

    private func logRootDestinationIfChanged(_ dest: RootDestination) {
        guard dest != lastLoggedRootDestination else { return }
        lastLoggedRootDestination = dest
        #if DEBUG
        let step = postJourneyStep?.rawValue ?? "nil"
        print(
            "[CheckMed] rootDestination=\(dest) flags="
                + "unlocked=\(isSessionUnlocked) "
                + "preAuth=\(hasFinishedPreAuthFunnel) "
                + "langChosen=\(localLanguageChosen) "
                + "howItWorks=\(localHowItWorksSeen) "
                + "privacy=\(localPrivacyAcknowledged) "
                + "signInSeen=\(localSignInScreenSeen) "
                + "onboarded=\(hasCompletedOnboarding) "
                + "returningWelcome=\(showReturningWelcome) "
                + "pendingRW=\(pendingReturningWelcome) "
                + "showedRW=\(showedReturningWelcomeThisSession) "
                + "needsIdentity=\(needsIdentityProfile) "
                + "freshRx=\(startFreshPrescription) "
                + "resume=\(showResumeSetup) "
                + "postJourney=\(step) "
                + "pendingPJ=\(pendingPostJourneySetup) "
                + "postAuth=\(String(describing: postAuthKind)) "
                + "phase=\(localFirstTimePhase) "
                + "keychainProfile=\(ProfileSetupKeychain.isComplete(for: auth.userId)) "
                + "keychainOnboarded=\(ProfileSetupKeychain.isOnboardingComplete(for: auth.userId))"
        )
        #endif
    }

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        if guestUnlocked { return .guest }
        return .welcome
    }

    /// Signed in or guest — may continue past sign-in into profile / home.
    var isSessionUnlocked: Bool {
        kind == .authenticated || kind == .guest
    }

    /// Auth user id when signed in; otherwise a persisted on-device id so guest seeds are owned + visible.
    var planOwnerId: UUID {
        auth.userId ?? Self.persistedLocalOwnerId()
    }

    /// Remote profile when synced; otherwise a persisted local profile for guest SwiftData stamps.
    var planProfileId: UUID {
        profileId ?? Self.persistedLocalProfileId()
    }

    /// Local owner used before sign-in (for adopting guest rows onto the auth account).
    var localPlanOwnerId: UUID { Self.persistedLocalOwnerId() }

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

    /// Language → how-it-works → privacy Accept. UserDefaults; wiped on app delete.
    var hasFinishedLegalPreAuth: Bool {
        localLanguageChosen && localHowItWorksSeen && localPrivacyAcknowledged
    }

    /// User completed the Sign-in screen this install (not a silent Keychain restore).
    var hasCompletedSignInThisInstall: Bool { localSignInScreenSeen }

    /// Language → how-it-works → privacy → explicit Sign-in. All UserDefaults; wiped on app delete.
    var hasFinishedPreAuthFunnel: Bool {
        hasFinishedLegalPreAuth && hasCompletedSignInThisInstall
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
    var hasChosenLanguage: Bool { localLanguageChosen }
    var hasSeenHowItWorks: Bool { localHowItWorksSeen }

    var hasCompletedOnboarding: Bool { localOnboardingComplete || perUserOnboardingComplete }
    /// True only after the user confirms a prescription (seed/add) or finishes resume of their plan.
    var hasConfirmedMedicationPlan: Bool {
        localMedicationPlanConfirmed || perUserMedicationPlanConfirmed
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
            userId: auth.userId ?? (kind == .guest ? Self.persistedLocalOwnerId() : nil),
            displayName: (name.isEmpty || name == "there" || name == "friend") ? nil : name,
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

    /// Call only after the user finishes Sign-in (provider/email) or Continue as guest.
    /// Silent Keychain restore must never call this.
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

    /// Unsigned users always replay splash → language → how it works → privacy → sign-in.
    /// Language and appearance stay. Do not call while a provider sheet is in progress.
    func restartPreAuthOnboarding() {
        guard kind != .authenticated, !auth.isRestoring else { return }
        guestUnlocked = false
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localPrivacyAcknowledged = false
        localLanguageChosen = false
        localHowItWorksSeen = false
        clearSignInScreenSeenThisInstall()
        localFirstTimePhase = "language"
        localIntroSplashSeen = false
        isResolvingPostAuth = false
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
        } else {
            ProfileSetupKeychain.markOnboardingComplete(
                userId: kind == .guest ? Self.persistedLocalOwnerId() : nil
            )
        }
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        localFirstTimePhase = "language"
        showResumeSetup = false
        startFreshPrescription = false
        clearPostJourneyQueue()
        selectedMainTab = .home
    }

    /// After journey for a newly confirmed plan: notifications → alarms → trial → Phil → Home.
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

    /// Journey Continue: start the linear queue at notifications (always show the screen).
    func startPostJourneyQueue() {
        postJourneyArmed = true
        setPostJourneyStep(.notifications)
    }

    /// Align queue cursor with the screen currently shown (no debug log spam for same step).
    func syncPostJourneyStep(_ step: PostJourneyStep) {
        postJourneyArmed = true
        guard postJourneyStep != step else { return }
        setPostJourneyStep(step)
    }

    /// Advance one step. Pass `isSuper` so trial is skipped when already subscribed.
    @discardableResult
    func advancePostJourney(isSuper: Bool) -> PostJourneyStep {
        let current = postJourneyStep ?? .notifications
        let next: PostJourneyStep
        switch current {
        case .notifications:
            next = .alarms
        case .alarms:
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
        postJourneyArmed = false
        postJourneyStep = nil
    }

    private func setPostJourneyStep(_ step: PostJourneyStep) {
        postJourneyStep = step
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
        if step == .done {
            clearPostJourneyQueue()
        }
    }

    /// Kept for back-navigation hints only. Post-journey queue always shows notifications.
    func shouldShowNotificationsScreen() async -> Bool {
        true
    }

    func markMedicationPlanConfirmed() {
        guard !hasConfirmedMedicationPlan else { return }
        localMedicationPlanConfirmed = true
        UserDefaults.standard.set(true, forKey: Keys.medicationPlanConfirmed)
        if let userId = auth.userId {
            UserDefaults.standard.set(true, forKey: Self.medicationPlanConfirmedKey(for: userId))
        }
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

    /// "This plan still needs you" — only mid abandoned setup, never after confirm.
    func needsUnfinishedPlan(treatments: CheckMedStore) -> Bool {
        guard !hasConfirmedMedicationPlan else { return false }
        return kind == .authenticated
            && treatments.hasExistingTreatments
            && (needsNotificationsPrompt || !treatments.hasMedicationDaysSet)
    }

    func beginResumeSetup() {
        showReturningWelcome = false
        pendingReturningWelcome = false
        showedReturningWelcomeThisSession = true
        startFreshPrescription = false
        showResumeSetup = true
        didOfferUnfinishedPlanThisSession = true
        // If armed but queue not started (e.g. cold handoff), begin at notifications.
        if postJourneyArmed, postJourneyStep == nil {
            setPostJourneyStep(.notifications)
        }
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
        }
        markNotificationsPrompted()
        markMedicationPlanConfirmed()
        markOnboardingPaywallOffered()
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
    var isGuest: Bool { kind == .guest }
    var canSync: Bool { kind == .authenticated }
    var supabaseConfigured: Bool { auth.isConfigured }
    var googleConfigured: Bool { auth.isGoogleConfigured }
    var isRestoring: Bool { auth.isRestoring }
    var isLoading: Bool { auth.isLoading }
    var errorMessage: String? { auth.errorMessage }
    var lastAuthNote: String? { auth.statusMessage }

    func continueAsGuest() {
        auth.clearMessages()
        guestUnlocked = true
        markSignInScreenCompleted()
        branchAfterSignInScreenIfNeeded()
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

    /// Splash → language → how it works → privacy → sign-in. Never enables guest.
    /// Identity returns from Supabase on the next sign-in so a new Google/email
    /// account cannot inherit the previous user's name, DOB, or pronouns.
    private func resetFirstTimePathAfterLogout() {
        guestUnlocked = false
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
    }

    func deleteAccount() {
        let deletingUserId = auth.userId
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
        guestUnlocked = false
        profileId = nil
        isResolvingPostAuth = false
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
        if let userId = deletingUserId {
            UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey(for: userId))
            UserDefaults.standard.removeObject(forKey: Self.medicationPlanConfirmedKey(for: userId))
            ProfileSetupKeychain.clear(for: userId)
        } else {
            ProfileSetupKeychain.clear()
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
        // Do NOT clear pendingReturningWelcome / showedReturningWelcomeThisSession.
        // Soft flag only — sticky pending survives token refresh / second auth events.
        showReturningWelcome = false
        // Hard rule: auth restore / sign-in never auto-opens Add prescription.
        // Only `beginFreshPlan()` (explicit tap) may set this true.
        startFreshPrescription = false
        // Never wipe an in-flight post-journey chain on token refresh / re-auth.
        if !pendingPostJourneySetup {
            showResumeSetup = false
        }
        if !isRestore {
            localOnboardingComplete = false
            UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
            selectedMainTab = .home
        }
        #if DEBUG
        print(
            "[CheckMed] preparePostAuth restore=\(isRestore) "
                + "pendingRW=\(pendingReturningWelcome) showedRW=\(showedReturningWelcomeThisSession) "
                + "preAuth=\(hasFinishedPreAuthFunnel)"
        )
        #endif
    }

    /// New vs returning after sign-in / session restore.
    /// Returning = Keychain onboarding OR treatments OR per-user/local onboarding OR
    /// Keychain profile complete — never auto-scan; miss-you once, then Home / add by choice.
    ///
    /// Hard rules on auth restore / re-sign-in:
    /// - NEVER set `firstTimePhase = addMedication`
    /// - NEVER set `startFreshPrescription = true` (only `beginFreshPlan()`)
    /// - If Keychain onboarded/profile complete → stamp ReturningWelcome (once per process)
    private func handleAuthenticated(isRestore: Bool) async {
        if !isResolvingPostAuth {
            preparePostAuth(isRestore: isRestore)
        }
        defer { isResolvingPostAuth = false }
        // Interactive sign-in / confirm-account completes this-install Sign-in.
        // New-install session wipe must never mark Sign-in seen.
        if !isRestore {
            markSignInScreenCompleted()
        }

        let pending = UserDefaults.standard.bool(forKey: Keys.pendingUpload)
        let remote = await pullProfile()
        replaceIdentity(from: remote, overwriteEmpty: !isRestore)
        if let userId = auth.userId {
            ProfileSetupKeychain.associateUserIfNeeded(userId)
            hydrateIdentityFromKeychainIfNeeded(userId: userId)
        }
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
        // Stamp Keychain whenever identity fields are present so delete+reinstall skips profile.
        if hasRawIdentityFields {
            markProfileSetupComplete()
        }

        let hasTreatments = await syncedHasTreatments()
        let identityComplete = hasCompleteIdentityProfile
        let userOnboarded = perUserOnboardingComplete
        let restoredComplete = isRestore && localOnboardingComplete
        let keychainProfile = ProfileSetupKeychain.isComplete(for: auth.userId)
        let keychainOnboarded = ProfileSetupKeychain.isOnboardingComplete(for: auth.userId)
        // Any prior completion signal wins over stale UserDefaults `firstTimePhase=addMedication`.
        let previouslyOnboarded = userOnboarded
            || keychainOnboarded
            || hasTreatments
            || restoredComplete
            || keychainProfile

        // Hard rule: auth never auto-opens Add prescription.
        startFreshPrescription = false

        if previouslyOnboarded {
            enterReturningAfterAuth(
                hasTreatments: hasTreatments,
                keychainProfile: keychainProfile,
                keychainOnboarded: keychainOnboarded
            )
            return
        }

        // True first-time account.
        postAuthKind = .newAccount
        selectedMainTab = .home
        // Never force profile/meds over an incomplete language → how it works → privacy → sign-in funnel.
        // Never set addMedication on session restore (stale phase fights ReturningWelcome later).
        guard hasFinishedPreAuthFunnel else {
            #if DEBUG
            print("[CheckMed] auth → newAccount (waiting pre-auth; phase=\(localFirstTimePhase))")
            #endif
            return
        }
        if !isRestore {
            clearSessionOnboardingFlag()
            // Fresh sign-in only: land on profile or meds. Restore never writes addMedication.
            if !identityComplete {
                setFirstTimePhaseRaw(FirstTimePhase.profile.rawValue)
            } else {
                setFirstTimePhaseRaw(FirstTimePhase.addMedication.rawValue)
            }
        } else if !identityComplete {
            setFirstTimePhaseRaw(FirstTimePhase.profile.rawValue)
        }
        #if DEBUG
        print("[CheckMed] auth → newAccount (phase=\(localFirstTimePhase) identity=\(identityComplete) restore=\(isRestore))")
        #endif
    }

    /// After the user finishes Sign-in (or guest), branch miss-you vs profile.
    private func branchAfterSignInScreenIfNeeded() {
        let keychainProfile = ProfileSetupKeychain.isComplete(for: auth.userId)
            || ProfileSetupKeychain.load().isComplete
        let keychainOnboarded = ProfileSetupKeychain.isOnboardingComplete(for: auth.userId)
            || ProfileSetupKeychain.isOnboardingComplete(for: nil)
        if keychainProfile || keychainOnboarded || localOnboardingComplete || perUserOnboardingComplete {
            enterReturningAfterAuth(
                hasTreatments: false,
                keychainProfile: keychainProfile,
                keychainOnboarded: keychainOnboarded
            )
            return
        }
        postAuthKind = .newAccount
    }

    /// Already-unlocked (Keychain restore) user taps Apple/Google/Continue on Sign-in.
    func confirmRestoredAccountOnSignInScreen() {
        guard isSessionUnlocked else { return }
        markSignInScreenCompleted()
        branchAfterSignInScreenIfNeeded()
    }

    /// Keychain / treatments / prior onboarding → miss-you once; clear stale addMedication phase.
    private func enterReturningAfterAuth(
        hasTreatments: Bool,
        keychainProfile: Bool,
        keychainOnboarded: Bool
    ) {
        postAuthKind = .returning
        startFreshPrescription = false
        // Kill stale FT phase that prior agents left as addMedication after delete+reinstall.
        clearStaleFirstTimePhaseForReturning()

        if pendingPostJourneySetup {
            // Stay on post-journey chain; do not jump to Home / miss-you.
            #if DEBUG
            print("[CheckMed] auth → returning (post-journey; treatments=\(hasTreatments))")
            #endif
            return
        }

        selectedMainTab = .home
        showResumeSetup = false
        markOnboardingPaywallOffered()
        // Force miss-you once per process for returning Keychain/onboarded users.
        // Sticky pending survives preparePostAuth clearing the soft showReturningWelcome flag.
        if !showedReturningWelcomeThisSession {
            pendingReturningWelcome = true
            showReturningWelcome = true
        }
        markOnboardingComplete()
        #if DEBUG
        print(
            "[CheckMed] auth → returning (welcome=\(showReturningWelcome) pendingRW=\(pendingReturningWelcome) "
                + "showedRW=\(showedReturningWelcomeThisSession) treatments=\(hasTreatments) "
                + "keychainProfile=\(keychainProfile) keychainOnboarded=\(keychainOnboarded) "
                + "preAuth=\(hasFinishedPreAuthFunnel))"
        )
        #endif
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

        if !hasPreferredName, let name = snap.displayName?.nilIfEmpty {
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

        if let name = profile?.displayName?.nilIfEmpty {
            localDisplayName = name
            UserDefaults.standard.set(name, forKey: Keys.display)
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
