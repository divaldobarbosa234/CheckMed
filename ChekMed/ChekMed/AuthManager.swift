import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Security
import Supabase
import UIKit

nonisolated struct CheckMedProfile: Codable, Sendable {
    var id: UUID?
    var ownerId: UUID
    var displayName: String?
    var companionName: String
    var dateOfBirth: String?
    var language: String?
    var timeZone: String?
    var pronouns: String?
    var gender: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case displayName = "display_name"
        case companionName = "companion_name"
        case dateOfBirth = "date_of_birth"
        case language
        case timeZone = "time_zone"
        case pronouns
        case gender
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(companionName, forKey: .companionName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(pronouns, forKey: .pronouns)
        try container.encodeIfPresent(gender, forKey: .gender)
    }
}

enum AppleDeletionAuthFailure: Error {
    case cancelled
    case failed
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
    private(set) var hasAppleIdentity = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    var isConfigured: Bool { client != nil }
    /// SyncEngine only. Screens must not call Supabase except through SessionStore auth/profile.
    var supabaseForSync: SupabaseClient? { client }
    var isGoogleConfigured: Bool { AuthConfig.isGoogleConfigured }
    var userId: UUID? { client?.auth.currentUser?.id }

    /// Report only. SessionStore decides restore / navigation after this.
    @ObservationIgnored
    var onAuthenticated: ((_ isRestore: Bool) async -> Void)?
    /// Fired once when the launch session is known (signed in or not). Never waits for SyncEngine.
    @ObservationIgnored
    var onSessionCheckFinished: (() -> Void)?
    private var authEventCount = 0

    private var client: SupabaseClient?
    private var listenerTask: Task<Void, Never>?
    private var didStart = false
    private var sawInitialSession = false
    /// Invalidates leftover Keychain sign-out so it cannot wipe a live Google session.
    private var leftoverSignOutGeneration = 0
    private let appleSignIn = AppleSignInCoordinator()
    private var pendingAppleDisplayName: String?

    func start() {
        guard !didStart else { return }
        didStart = true
        let skipPersistedSession = CheckMedAuthPersistence.prepareLaunch()
        configureClient()
        configureGoogle()
        guard let client else {
            releaseRestoreGate(reason: "no supabase client")
            return
        }
        listen(to: client)
        LaunchLog.auth("checkingSession start skipPersisted=\(skipPersistedSession)")
        if skipPersistedSession {
            leftoverSignOutGeneration += 1
            let generation = leftoverSignOutGeneration
            apply(session: nil)
            releaseRestoreGate(reason: "new install")
            Task { [weak self] in
                GIDSignIn.sharedInstance.signOut()
                guard let self, generation == self.leftoverSignOutGeneration, !self.isAuthenticated else {
                    LaunchLog.auth("skip leftover signOut — Google/session already present")
                    return
                }
                do {
                    try await NetworkDeadline.run(seconds: 12) {
                        try await client.auth.signOut()
                    }
                } catch {
                    LaunchLog.error("signOut during skip-restore: \(error.localizedDescription)")
                }
                guard generation == self.leftoverSignOutGeneration, !self.isAuthenticated else {
                    LaunchLog.auth("skip leftover signOut apply — session already present")
                    return
                }
                self.apply(session: nil)
            }
        }
    }

    /// Launch restore ends when the first auth event (or explicit no-session)
    /// is known. Never set `isRestoring = true` again in this process.
    private func releaseRestoreGate(reason: String) {
        sawInitialSession = true
        guard isRestoring else {
            onSessionCheckFinished?()
            return
        }
        isRestoring = false
        onSessionCheckFinished?()
        LaunchLog.auth("checkingSession complete authenticated=\(isAuthenticated) reason=\(reason)")
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    func presentFacebookUnavailable(_ message: String = "Facebook sign-in is not enabled yet.") {
        errorMessage = nil
        statusMessage = message
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

    /// Deletes only the currently authenticated Auth user via a JWT-gated Edge Function.
    /// Does not take a user id from the client. Does not wipe local data.
    /// `appleAuthorizationCode` is required when the Auth user has an Apple identity.
    func deleteOwnAuthenticatedAccount(appleAuthorizationCode: String? = nil) async -> Bool {
        errorMessage = nil
        statusMessage = nil
        guard let client, isAuthenticated, userId != nil else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            struct Payload: Decodable { let ok: Bool }
            struct Body: Encodable { var appleAuthorizationCode: String? }
            let payload: Payload = try await NetworkDeadline.run(seconds: 30) {
                if let appleAuthorizationCode, !appleAuthorizationCode.isEmpty {
                    return try await client.functions.invoke(
                        "delete-account",
                        options: FunctionInvokeOptions(body: Body(appleAuthorizationCode: appleAuthorizationCode))
                    )
                }
                return try await client.functions.invoke("delete-account")
            }
            guard payload.ok else { return false }
            return true
        } catch {
            LaunchLog.error("delete-account: \(error.localizedDescription)")
            return false
        }
    }

    func refreshAppleIdentityLink() async {
        guard let client, isAuthenticated else {
            hasAppleIdentity = false
            return
        }
        if hasAppleIdentity { return }
        if let user = try? await client.auth.user() {
            hasAppleIdentity = Self.userHasAppleIdentity(user)
        }
    }

    /// Native Apple sheet only to collect a one-time authorization code for server revocation.
    /// Does not create a second Supabase session.
    func appleAuthorizationCodeForDeletion() async -> Result<String, AppleDeletionAuthFailure> {
        do {
            let rawNonce = Self.randomNonce()
            let result = try await appleSignIn.signIn(hashedNonce: Self.sha256Hex(rawNonce))
            guard let code = result.authorizationCode, !code.isEmpty else {
                return .failure(.failed)
            }
            return .success(code)
        } catch {
            if Self.isAppleCancel(error) { return .failure(.cancelled) }
            LaunchLog.error("apple deletion auth: \(error.localizedDescription)")
            return .failure(.failed)
        }
    }

    /// Drop the local Auth/Google session after the Auth user is already gone remotely.
    func clearSessionAfterRemoteAccountDeletion() async {
        leftoverSignOutGeneration += 1
        GIDSignIn.sharedInstance.signOut()
        if let client {
            try? await client.auth.signOut(scope: .local)
        }
        apply(session: nil)
    }

    func signInWithApple() async {
        errorMessage = nil
        statusMessage = nil

        guard let client else {
            errorMessage = "Add SUPABASE_URL and the publishable key to Secrets.xcconfig, then build again."
            return
        }

        isLoading = true
        do {
            let rawNonce = Self.randomNonce()
            let result = try await appleSignIn.signIn(hashedNonce: Self.sha256Hex(rawNonce))
            pendingAppleDisplayName = result.fullName
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: result.idToken,
                    nonce: rawNonce
                )
            )
        } catch {
            pendingAppleDisplayName = nil
            if Self.isAppleCancel(error) {
                errorMessage = nil
                statusMessage = nil
            } else {
                errorMessage = Self.appleMessage(for: error)
            }
        }
        isLoading = false
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

        leftoverSignOutGeneration += 1
        isLoading = true
        LaunchLog.auth("Starting Google sign-in")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)

        do {
            try await completeGoogleSignIn(
                client: client,
                presenter: presenter,
                retryOnKeychain: true
            )
            LaunchLog.auth(
                "Google callback user=\(client.auth.currentUser?.id.uuidString ?? "nil")"
            )
        } catch {
            if Self.isGoogleCancel(error) {
                errorMessage = nil
                statusMessage = nil
            } else if Self.isGoogleKeychainNoise(error) {
                errorMessage = "Google sign-in didn't complete. Try again."
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
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: CheckMedAuthStorage(),
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    private func configureGoogle() {
        if let clientID = AuthConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        // Interactive Google sign-in does not restore from the keychain. Skip
        // restorePreviousSignIn — Simulator keychain misses must not become UI errors.
    }

    private func completeGoogleSignIn(
        client: SupabaseClient,
        presenter: UIViewController,
        retryOnKeychain: Bool
    ) async throws {
        let rawNonce = Self.randomNonce()
        let hashedNonce = Self.sha256Hex(rawNonce)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            try await exchangeGoogleTokens(
                idToken: result.user.idToken?.tokenString,
                accessToken: result.user.accessToken.tokenString,
                nonce: rawNonce,
                client: client
            )
        } catch {
            if let tokens = Self.liveGoogleTokens() {
                try await exchangeGoogleTokens(
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    nonce: rawNonce,
                    client: client
                )
                return
            }
            guard retryOnKeychain, Self.isGoogleKeychainNoise(error) else { throw error }
            try await Task.sleep(nanoseconds: 400_000_000)
            try await completeGoogleSignIn(
                client: client,
                presenter: presenter,
                retryOnKeychain: false
            )
        }
    }

    private func exchangeGoogleTokens(
        idToken: String?,
        accessToken: String,
        nonce: String,
        client: SupabaseClient
    ) async throws {
        guard let idToken else { throw AuthFlowError.missingGoogleIDToken }
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nonce
            )
        )
    }

    private func listen(to client: SupabaseClient) {
        if listenerTask != nil {
            LaunchLog.auth("listener removed")
            listenerTask?.cancel()
        }
        listenerTask = Task { [weak self] in
            LaunchLog.auth("listener registered")
            for await (event, session) in client.auth.authStateChanges {
                await self?.handleAuthChange(event, session)
            }
            LaunchLog.auth("listener removed")
        }
    }

    private func handleAuthChange(_ event: AuthChangeEvent, _ session: Session?) async {
        authEventCount += 1
        LaunchLog.auth(
            "Auth listener fired event=\(event) count=\(authEventCount) hasSession=\(session != nil) "
                + "user=\(session?.user.id.uuidString ?? "nil")"
        )
        if CheckMedAuthPersistence.skipRestoreThisProcess, event == .initialSession {
            apply(session: nil)
            releaseRestoreGate(reason: "ignore leftover session")
            LaunchLog.auth("checkingSession ignore leftover session (new install)")
            if session != nil, let client {
                do {
                    try await client.auth.signOut()
                } catch {}
            }
            return
        }
        if event == .signedIn {
            CheckMedAuthPersistence.skipRestoreThisProcess = false
        }
        let wasAuthenticated = isAuthenticated
        let sameUser = wasAuthenticated && session?.user.id != nil && session?.user.id == userId
        apply(session: session)
        // Session known — leave the branded restore screen before any profile/replica work.
        if event == .initialSession || event == .signedOut || session != nil {
            releaseRestoreGate(reason: "event=\(event)")
        }
        if event == .signedIn, sameUser {
            LaunchLog.auth("signedIn same user — report only, no restore")
            return
        }
        let isRestore: Bool
        switch event {
        case .initialSession:
            isRestore = true
        case .signedIn:
            isRestore = wasAuthenticated
        default:
            isRestore = wasAuthenticated
        }
        if session != nil {
            switch event {
            case .initialSession:
                LaunchLog.auth("session found restore=true")
                await onAuthenticated?(true)
            case .signedIn:
                LaunchLog.auth("signedIn restore=\(isRestore)")
                await onAuthenticated?(isRestore)
            default:
                break
            }
        } else if event == .initialSession || event == .signedOut {
            LaunchLog.auth("no session event=\(event)")
        }
    }

    private func apply(session: Session?) {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = session != nil
        email = session?.user.email
        if session != nil, !wasAuthenticated {
            LaunchLog.auth("Session created user=\(session?.user.id.uuidString ?? "nil")")
        }
        if let user = session?.user {
            displayName = Self.inferredDisplayName(from: user)
            if displayName == "friend", let pending = pendingAppleDisplayName, !pending.isEmpty {
                displayName = pending
            }
            hasAppleIdentity = Self.userHasAppleIdentity(user)
        } else {
            displayName = "friend"
            companionName = "Phil"
            pendingAppleDisplayName = nil
            hasAppleIdentity = false
        }
        if session != nil {
            errorMessage = nil
        }
    }

    func fetchProfile() async -> CheckMedProfile? {
        guard let client, let userId else { return nil }
        do {
            let rows: [CheckMedProfile] = try await NetworkDeadline.run(seconds: 15) {
                try await client
                    .from("profiles")
                    .select("id, owner_id, display_name, companion_name, date_of_birth, language, time_zone, pronouns, gender")
                    .eq("owner_id", value: userId.uuidString)
                    .limit(1)
                    .execute()
                    .value
            }
            if let profile = rows.first {
                displayName = profile.displayName?.nilIfEmpty ?? displayName
                companionName = profile.companionName.nilIfEmpty ?? "Phil"
                return profile
            }
        } catch {
            LaunchLog.error("profile fetch: \(error.localizedDescription)")
        }
        return nil
    }

    @discardableResult
    func upsertProfile(_ profile: CheckMedProfile) async -> Bool {
        guard let client else { return false }
        do {
            try await client
                .from("profiles")
                .upsert(profile, onConflict: "owner_id")
                .execute()
            if let name = profile.displayName?.nilIfEmpty {
                displayName = name
            }
            if let companion = profile.companionName.nilIfEmpty {
                companionName = companion
            }
            return true
        } catch {
            return false
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

    private static func userHasAppleIdentity(_ user: User) -> Bool {
        if user.identities?.contains(where: { $0.provider.lowercased() == "apple" }) == true {
            return true
        }
        if user.appMetadata["provider"]?.stringValue?.lowercased() == "apple" {
            return true
        }
        if let providers = user.appMetadata["providers"]?.arrayValue {
            return providers.contains { $0.stringValue?.lowercased() == "apple" }
        }
        return false
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
            case GIDSignInError.canceled.rawValue,
                 GIDSignInError.keychain.rawValue,
                 GIDSignInError.hasNoAuthInKeychain.rawValue:
                return "Google sign-in didn't complete. Try again."
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

    private static func isAppleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        let raw = ns.localizedDescription.lowercased()
        return raw.contains("canceled") || raw.contains("cancelled")
    }

    private static func appleMessage(for error: Error) -> String {
        if let error = error as? AppleSignInError {
            return error.localizedDescription
        }
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain {
            switch ns.code {
            case ASAuthorizationError.canceled.rawValue:
                return "Apple sign-in didn't complete. Try again."
            case ASAuthorizationError.failed.rawValue,
                 ASAuthorizationError.invalidResponse.rawValue,
                 ASAuthorizationError.notHandled.rawValue,
                 ASAuthorizationError.unknown.rawValue:
                return "Apple sign-in didn't complete. Try again."
            default:
                break
            }
        }
        let raw = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return "Apple sign-in didn't complete. Try again."
        }
        if raw.localizedCaseInsensitiveContains("is not enabled") {
            return "Sign in with Apple is on in the app, but it is still off in Supabase. Enable the Apple provider (Team ID, Key ID, and .p8) and add client ID com.checkmed.app."
        }
        if raw.localizedCaseInsensitiveContains("provider") || raw.localizedCaseInsensitiveContains("apple") {
            return raw
        }
        return "Apple sign-in didn't complete. Try again."
    }

    private static func isGoogleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue {
            return true
        }
        let raw = ns.localizedDescription.lowercased()
        return raw.contains("canceled") || raw.contains("cancelled")
    }

    /// Keychain save/restore failures are SDK persistence, not a user-facing Sign in error.
    private static func isGoogleKeychainNoise(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == kGIDSignInErrorDomain {
            switch ns.code {
            case GIDSignInError.keychain.rawValue, GIDSignInError.hasNoAuthInKeychain.rawValue:
                return true
            default:
                break
            }
        }
        return ns.localizedDescription.localizedCaseInsensitiveContains("keychain")
    }

    private static func liveGoogleTokens() -> (idToken: String, accessToken: String)? {
        guard let user = GIDSignIn.sharedInstance.currentUser,
              let idToken = user.idToken?.tokenString else { return nil }
        return (idToken, user.accessToken.tokenString)
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

/// UserDefaults is wiped on app delete; Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
/// is not. Gate Keychain session restore on an install token so delete → signed out.
enum CheckMedAuthPersistence {
    static let hasLaunchedThisInstallKey = "checkmed.hasLaunchedThisInstall"
    static let installSessionTokenKey = "checkmed.installSessionToken"
    private static let userDefaultsPrefix = "checkmed.auth."

    /// When true, ignore leftover Keychain session tokens for this process.
    static var skipRestoreThisProcess = false

    /// Stamp this install. Discard happens in SessionStore when
    /// `preAuthInstallStamp` is missing (true new container after delete).
    /// Do not treat a missing `hasLaunchedThisInstall` alone as delete — that
    /// would sign existing users out on this update.
    @discardableResult
    static func prepareLaunch() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hasLaunchedThisInstallKey) == nil {
            defaults.set(true, forKey: hasLaunchedThisInstallKey)
        }
        return skipRestoreThisProcess
    }

    static func discardPersistedSession() {
        skipRestoreThisProcess = true
        let defaults = UserDefaults.standard
        let prefixed = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(userDefaultsPrefix) }
        var sessionKeys: Set<String> = [
            "supabase.auth.token",
            "supabase.session",
            "supabase.auth.token-code-verifier"
        ]
        for key in prefixed {
            sessionKeys.insert(String(key.dropFirst(userDefaultsPrefix.count)))
        }
        if let host = AuthConfig.supabaseURL?.host {
            let project = host.split(separator: ".").first.map(String.init) ?? ""
            if !project.isEmpty {
                sessionKeys.insert("sb-\(project)-auth-token")
                sessionKeys.insert("sb-\(project)-auth-token-code-verifier")
            }
        }
        defaults.removeObject(forKey: installSessionTokenKey)
        for key in prefixed {
            defaults.removeObject(forKey: key)
        }
        let keychain = KeychainLocalStorage()
        for key in sessionKeys {
            try? keychain.remove(key: key)
        }
    }

    fileprivate static func bindSessionToThisInstall() {
        skipRestoreThisProcess = false
        UserDefaults.standard.set(UUID().uuidString, forKey: installSessionTokenKey)
    }

    fileprivate static var mayRestoreKeychainSession: Bool {
        !skipRestoreThisProcess
            && UserDefaults.standard.object(forKey: installSessionTokenKey) != nil
    }
}

/// Persists the Supabase session in UserDefaults for this install and mirrors
/// into Keychain. Keychain is only read back when `installSessionToken` exists
/// (UserDefaults — wiped on delete), so uninstall cannot silently log the user in.
private struct CheckMedAuthStorage: AuthLocalStorage {
    private let prefix = "checkmed.auth."
    private let keychain = KeychainLocalStorage()

    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: prefix + key)
        try? keychain.store(key: key, value: value)
        CheckMedAuthPersistence.bindSessionToThisInstall()
    }

    func retrieve(key: String) throws -> Data? {
        if CheckMedAuthPersistence.skipRestoreThisProcess { return nil }
        if let data = UserDefaults.standard.data(forKey: prefix + key) {
            return data
        }
        guard CheckMedAuthPersistence.mayRestoreKeychainSession else { return nil }
        if let data = try? keychain.retrieve(key: key) {
            UserDefaults.standard.set(data, forKey: prefix + key)
            return data
        }
        return nil
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
        try? keychain.remove(key: key)
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
