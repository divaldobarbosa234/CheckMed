import CryptoKit
import Foundation
import GoogleSignIn
import Security
import Supabase
import UIKit

nonisolated struct CheckMedProfile: Codable, Sendable {
    var ownerId: UUID
    var displayName: String?
    var companionName: String

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case displayName = "display_name"
        case companionName = "companion_name"
    }
}

/// Owns the Supabase client, persisted session, and provider sign-in.
/// SessionStore is the single SwiftUI session source and wraps this type.
@MainActor
@Observable
final class AuthManager {
    private(set) var isRestoring = true
    private(set) var isLoading = false
    private(set) var isAuthenticated = false
    private(set) var displayName = "friend"
    private(set) var companionName = "Phil"
    private(set) var email: String?
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    var isConfigured: Bool { client != nil }
    var isGoogleConfigured: Bool { AuthConfig.isGoogleConfigured }

    private var client: SupabaseClient?
    private var listenerTask: Task<Void, Never>?
    private var didStart = false
    private var sawInitialSession = false

    func start() {
        guard !didStart else { return }
        didStart = true
        configureClient()
        configureGoogle()
        guard let client else {
            isRestoring = false
            return
        }
        listen(to: client)
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    func presentAppleComingSoon(_ message: String = AuthConfig.appleComingSoonMessage) {
        errorMessage = nil
        statusMessage = message
    }

    func presentFacebookUnavailable() {
        errorMessage = nil
        statusMessage = "Facebook sign-in is not enabled yet."
    }

    func presentError(_ message: String) {
        errorMessage = message
        statusMessage = nil
    }

    func signIn(email: String, password: String) async {
        await run {
            _ = try await $0.auth.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await run { client in
            let response = try await client.auth.signUp(email: email, password: password)
            if response.session == nil {
                self.statusMessage = "Check your email to confirm the account, then log in."
            }
        }
    }

    func resetPassword(email: String) async {
        await run { client in
            try await client.auth.resetPasswordForEmail(email)
            self.statusMessage = "If that email is registered, Phil sent a reset link."
        }
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        guard let client else {
            apply(session: nil)
            return
        }
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = Self.message(for: error)
        }
        apply(session: nil)
    }

    func signInWithGoogle() async {
        errorMessage = nil
        statusMessage = nil

        guard let client else {
            errorMessage = "Add SUPABASE_URL and the publishable key to Secrets.xcconfig, then build again."
            return
        }
        guard let googleClientID = AuthConfig.googleClientID else {
            errorMessage = Self.missingGoogleClientIDMessage
            return
        }
        guard let presenter = Self.topViewController() else {
            errorMessage = "Google Sign-In needs a visible window to present."
            return
        }

        isLoading = true
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)

        do {
            let rawNonce = Self.randomNonce()
            let hashedNonce = Self.sha256Hex(rawNonce)
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthFlowError.missingGoogleIDToken
            }
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    nonce: rawNonce
                )
            )
        } catch {
            if Self.isGoogleCancel(error) {
                statusMessage = "Google sign-in was canceled."
                errorMessage = nil
            } else {
                errorMessage = Self.googleMessage(for: error)
            }
        }
        isLoading = false
    }

    static let missingGoogleClientIDMessage = """
    Google Sign-In needs the iOS OAuth Client ID. In Google Cloud Console → APIs & Services → Credentials, open the iOS client and paste Client ID into GOOGLE_IOS_CLIENT_ID (Info.plist GIDClientID). Then paste iOS URL scheme (reversed client ID) into GOOGLE_IOS_REVERSED_CLIENT_ID and add it as a URL Type.
    """

    private func configureClient() {
        guard let url = AuthConfig.supabaseURL, let key = AuthConfig.supabaseAnonKey else {
            client = nil
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    private func configureGoogle() {
        if let clientID = AuthConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    private func listen(to client: SupabaseClient) {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            for await (_, session) in client.auth.authStateChanges {
                await self?.handleAuthChange(session, client: client)
            }
        }
    }

    private func handleAuthChange(_ session: Session?, client: SupabaseClient) async {
        apply(session: session)
        if !sawInitialSession {
            sawInitialSession = true
            isRestoring = false
        }
        if session != nil {
            await refreshProfile(using: client)
        }
    }

    private func apply(session: Session?) {
        isAuthenticated = session != nil
        email = session?.user.email
        if let user = session?.user {
            displayName = Self.inferredDisplayName(from: user)
        } else {
            displayName = "friend"
            companionName = "Phil"
        }
        if session != nil {
            errorMessage = nil
        }
    }

    private func refreshProfile(using client: SupabaseClient) async {
        guard let userId = client.auth.currentUser?.id else { return }
        do {
            let rows: [CheckMedProfile] = try await client
                .from("profiles")
                .select()
                .eq("owner_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            if let profile = rows.first {
                displayName = profile.displayName?.nilIfEmpty ?? displayName
                companionName = profile.companionName.nilIfEmpty ?? "Phil"
            } else {
                let name = displayName
                try await client
                    .from("profiles")
                    .insert(CheckMedProfile(ownerId: userId, displayName: name, companionName: "Phil"))
                    .execute()
            }
        } catch {
            // Profile is best-effort; a valid session still signs the user in.
        }
    }

    private func run(_ work: (SupabaseClient) async throws -> Void) async {
        errorMessage = nil
        statusMessage = nil
        guard let client else {
            errorMessage = "Add SUPABASE_URL and the publishable key to Secrets.xcconfig, then build again."
            return
        }
        isLoading = true
        do {
            try await work(client)
        } catch {
            errorMessage = Self.message(for: error)
        }
        isLoading = false
    }

    private static func inferredDisplayName(from user: User) -> String {
        if let name = user.userMetadata["full_name"]?.stringValue?.nilIfEmpty { return name }
        if let name = user.userMetadata["name"]?.stringValue?.nilIfEmpty { return name }
        if let email = user.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "friend"
    }

    private static func message(for error: Error) -> String {
        if let error = error as? AuthFlowError {
            return error.localizedDescription
        }
        let raw = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return "That didn't work. Try again."
        }
        return raw
    }

    private static func googleMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == kGIDSignInErrorDomain {
            switch ns.code {
            case GIDSignInError.canceled.rawValue:
                return "Google sign-in was canceled."
            case GIDSignInError.keychain.rawValue:
                return Self.keychainHelpMessage
            case GIDSignInError.hasNoAuthInKeychain.rawValue:
                return "No saved Google session on this device. Sign in with Google again."
            case GIDSignInError.EMM.rawValue:
                return "This Google account is managed by an organization and couldn't sign in here."
            case GIDSignInError.scopesAlreadyGranted.rawValue:
                return "Google already granted those permissions. Try again."
            case GIDSignInError.mismatchWithCurrentUser.rawValue:
                return "That Google account doesn't match the current user. Sign out and try again."
            default:
                return "Google sign-in didn't complete. Try again."
            }
        }
        let raw = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.localizedCaseInsensitiveContains("keychain") {
            return Self.keychainHelpMessage
        }
        if raw.localizedCaseInsensitiveContains("nonce") || raw.localizedCaseInsensitiveContains("id_token") {
            return "Google sign-in couldn't be verified. Try again."
        }
        return "Google sign-in didn't complete. Try again."
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate a secure nonce.")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let keychainHelpMessage =
        "Couldn't save the Google sign-in on this device. Restart the Simulator and try again."

    private static func isGoogleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue {
            return true
        }
        return ns.localizedDescription.localizedCaseInsensitiveContains("canceled")
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

private enum AuthFlowError: LocalizedError {
    case missingGoogleIDToken

    var errorDescription: String? {
        switch self {
        case .missingGoogleIDToken:
            "Google did not return an ID token. Try again, or confirm the iOS Client ID in Secrets.xcconfig."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let value): value
        default: nil
        }
    }
}
