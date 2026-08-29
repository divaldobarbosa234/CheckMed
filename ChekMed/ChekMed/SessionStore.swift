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

    init() {
        auth.start()
    }

    var kind: Kind {
        if auth.isAuthenticated { return .authenticated }
        if guestUnlocked { return .guest }
        return .welcome
    }

    var displayName: String {
        switch kind {
        case .welcome, .guest: "there"
        case .authenticated: auth.displayName
        }
    }

    var companionName: String { auth.companionName }
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

    func signOut() {
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
