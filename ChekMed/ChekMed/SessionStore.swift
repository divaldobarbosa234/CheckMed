import Foundation

@Observable
final class SessionStore {
    enum Kind {
        case welcome
        case guest
        case authenticated
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
        auth.onAuthenticated = { [weak self] _ in
            await self?.handleAuthenticated()
        }
        auth.start()
    }

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        if guestUnlocked || localOnboardingComplete { return .guest }
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
    var birthDate: Date? { localBirthDate }
    var pronouns: String { localPronouns }
    var gender: String { localGender }

    var hasPreferredName: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != "there" && name != "friend"
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

    var hasCompletedOnboarding: Bool { localOnboardingComplete }
    var firstTimePhaseRaw: String { localFirstTimePhase }
    var shouldOfferOnboardingPaywall: Bool {
        localOnboardingComplete && !localOnboardingPaywallOffered
    }

    /// Identity fields collected after sign-in (name, DOB, pronouns, gender). Not language.
    var needsIdentityProfile: Bool { needsCallYouScreen || needsAddressYouScreen }

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

    func markOnboardingComplete() {
        localOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.firstTimePhase)
        localFirstTimePhase = "language"
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
    var isGuest: Bool { kind != .authenticated }
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
        guestUnlocked = false
        Task { await auth.signOut() }
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
        localOnboardingComplete = false
        localOnboardingPaywallOffered = false
        localFirstTimePhase = "language"
        localPronouns = ""
        localGender = ""
        localNotificationsPrompted = false
        localPrivacyAcknowledged = false
        localOptionalAnalytics = false
        localOptionalMarketing = false
        guestUnlocked = false
        Task { await auth.signOut() }
    }

    func requestProvider(_ provider: AuthProvider) {
        switch provider {
        case .apple:
            auth.presentAppleComingSoon(t(.appleComingSoon))
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

    private func handleAuthenticated() async {
        let pending = UserDefaults.standard.bool(forKey: Keys.pendingUpload)
        // Guest setup stays local until sign-in. Failed signed-in writes also
        // stay pending so the next session can retry, then we read back.
        if pending {
            await pushProfile()
        }
        let remote = await pullProfile()
        if remote == nil {
            await pushProfile()
        }
    }

    private func pushProfile() async {
        guard canSync, let userId = auth.userId else {
            UserDefaults.standard.set(true, forKey: Keys.pendingUpload)
            return
        }
        let name = localDisplayName == "there" ? nil : localDisplayName
        let profile = CheckMedProfile(
            ownerId: userId,
            displayName: name ?? auth.displayName.nilIfEmpty,
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
        guard let profile = await auth.fetchProfile() else { return nil }
        applyRemote(profile)
        return profile
    }

    private func applyRemote(_ profile: CheckMedProfile) {
        if let name = profile.displayName?.nilIfEmpty {
            localDisplayName = name
            UserDefaults.standard.set(name, forKey: Keys.display)
        }
        if let companion = profile.companionName.nilIfEmpty {
            localCompanionName = companion
            UserDefaults.standard.set(companion, forKey: Keys.companion)
        }
        if let language = profile.language?.nilIfEmpty {
            localLanguage = AppLocale.fromStored(language).rawValue
            UserDefaults.standard.set(localLanguage, forKey: Keys.language)
        }
        if let timeZone = profile.timeZone?.nilIfEmpty {
            localTimeZone = CheckMedTimeZones.resolved(timeZone)
            UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
        }
        if let raw = profile.dateOfBirth?.nilIfEmpty,
           let date = BirthDateWheels.date(fromStamp: raw) {
            localBirthDate = BirthDateWheels.clampedDate(date)
            UserDefaults.standard.set(BirthDateWheels.stamp(from: localBirthDate!), forKey: Keys.birthDate)
        }
        if let pronouns = profile.pronouns?.nilIfEmpty {
            localPronouns = pronouns
            UserDefaults.standard.set(pronouns, forKey: Keys.pronouns)
        }
        if let gender = profile.gender?.nilIfEmpty {
            localGender = gender
            UserDefaults.standard.set(gender, forKey: Keys.gender)
        }
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
