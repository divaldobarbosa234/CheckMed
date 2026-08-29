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

    private enum Keys {
        static let display = "checkmed.displayName"
        static let companion = "checkmed.companionName"
    }

    init() {
        if let stored = UserDefaults.standard.string(forKey: Keys.display), !stored.isEmpty {
            localDisplayName = stored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.companion), !stored.isEmpty {
            localCompanionName = stored
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
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let companion = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        localDisplayName = display.isEmpty ? "there" : display
        localCompanionName = companion.isEmpty ? "Phil" : companion
        UserDefaults.standard.set(localDisplayName, forKey: Keys.display)
        UserDefaults.standard.set(localCompanionName, forKey: Keys.companion)
    }

    func signOut() {
        guestUnlocked = false
        Task { await auth.signOut() }
    }

    func deleteAccount() {
        localDisplayName = "there"
        localCompanionName = "Phil"
        UserDefaults.standard.removeObject(forKey: Keys.display)
        UserDefaults.standard.removeObject(forKey: Keys.companion)
        guestUnlocked = false
        Task { await auth.signOut() }
    }

    func requestProvider(_ provider: AuthProvider) {
        switch provider {
        case .apple:
            auth.presentAppleComingSoon()
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
