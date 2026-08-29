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

    private enum Keys {
        static let display = "checkmed.displayName"
        static let companion = "checkmed.companionName"
        static let language = "checkmed.language"
        static let timeZone = "checkmed.timeZone"
        static let birthDate = "checkmed.birthDate"
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
           let date = SessionStore.birthStamp.date(from: stored) {
            localBirthDate = date
        }
        auth.start()
    }

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        if guestUnlocked { return .guest }
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

    private static let birthStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
    }

    func setLocale(_ locale: AppLocale) {
        localLanguage = locale.rawValue
        UserDefaults.standard.set(locale.rawValue, forKey: Keys.language)
    }

    func setLanguage(_ language: String) {
        setLocale(AppLocale.fromStored(language))
    }

    func setTimeZoneName(_ timeZoneName: String) {
        localTimeZone = CheckMedTimeZones.resolved(timeZoneName)
        UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
    }

    func setBirthDate(_ date: Date?) {
        localBirthDate = date
        if let date {
            UserDefaults.standard.set(SessionStore.birthStamp.string(from: date), forKey: Keys.birthDate)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
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
        localBirthDate = birthDate
        UserDefaults.standard.set(localDisplayName, forKey: Keys.display)
        UserDefaults.standard.set(localLanguage, forKey: Keys.language)
        UserDefaults.standard.set(localTimeZone, forKey: Keys.timeZone)
        UserDefaults.standard.set(localCompanionName, forKey: Keys.companion)
        if let birthDate {
            UserDefaults.standard.set(SessionStore.birthStamp.string(from: birthDate), forKey: Keys.birthDate)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.birthDate)
        }
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
            auth.presentFacebookUnavailable()
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
