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
    /// True from just before Google/Apple provider UI is presented until that call returns.
    /// Separate from `isLoading`: Google must keep `isLoading == false` while GID presents
    /// (`SignInView` disables the host when loading). Scene `.background` during that UI
    /// must not restart pre-auth onboarding.
    private(set) var isProviderAuthenticationUIPresented = false
    private(set) var isAuthenticated = false
    private(set) var displayName = "friend"
    private(set) var companionName = "Phil"
    private(set) var email: String?
    private(set) var hasAppleIdentity = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    /// Increments only when `adoptInteractiveSession` runs (email/Google success).
    /// Sign-in UI uses this to ignore leftover sessions, cancels, and failures.
    private(set) var interactiveAdoptCount = 0

    var isConfigured: Bool { client != nil }
    /// SyncEngine only. Screens must not call Supabase except through SessionStore auth/profile.
    var supabaseForSync: SupabaseClient? { client }
    var isGoogleConfigured: Bool { AuthConfig.isGoogleConfigured }
    var userId: UUID? { client?.auth.currentUser?.id }

    /// How `displayName` was inferred from the auth session. Not the Conny Cooper Preferred name.
    /// Profile fetch/upsert may later change `displayName` without changing this provenance.
    enum DisplayNameInference: Equatable {
        case friend
        case emailLocalPart
        case providerMetadata
        case appleFullName
    }

    private(set) var displayNameInference: DisplayNameInference = .friend

    /// Exact local-part used by the email fallback in `inferredDisplayName`. Nil if unsigned or no email.
    var emailLocalPartLabel: String? {
        guard let email, let prefix = email.split(separator: "@").first, !prefix.isEmpty else {
            return nil
        }
        return String(prefix)
    }

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
    #if DEBUG
    private var applySite = "apply"
    #endif
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
            #if DEBUG
            AuthTransitionDiagnostics.record(fields: [
                "site=leftoverSignOut.start",
                "generation=\(generation)",
                "wasAuthenticated=\(isAuthenticated)",
            ])
            applySite = "leftoverSignOut.startApply"
            #endif
            apply(session: nil)
            releaseRestoreGate(reason: "new install")
            #if DEBUG
            if CheckMedLocalIsolation.isRequested(environment: ProcessInfo.processInfo.environment) {
                GIDSignIn.sharedInstance.signOut()
                LaunchLog.auth("isolation skip leftover remote signOut")
                AuthTransitionDiagnostics.record(fields: [
                    "site=leftoverSignOut.isolationSkipRemote",
                    "generation=\(generation)",
                ])
                return
            }
            #endif
            Task { [weak self] in
                GIDSignIn.sharedInstance.signOut()
                guard let self, generation == self.leftoverSignOutGeneration, !self.isAuthenticated else {
                    LaunchLog.auth("skip leftover signOut — Google/session already present")
                    #if DEBUG
                    AuthTransitionDiagnostics.record(fields: [
                        "site=leftoverSignOut.skipBeforeRemote",
                        "generationMatch=\(self?.leftoverSignOutGeneration == generation)",
                        "wasAuthenticated=\(self?.isAuthenticated ?? false)",
                    ])
                    #endif
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
                    #if DEBUG
                    AuthTransitionDiagnostics.record(fields: [
                        "site=leftoverSignOut.skipAfterRemote",
                        "generationMatch=\(generation == self.leftoverSignOutGeneration)",
                        "wasAuthenticated=\(self.isAuthenticated)",
                    ])
                    #endif
                    return
                }
                #if DEBUG
                AuthTransitionDiagnostics.record(fields: [
                    "site=leftoverSignOut.applyAfterRemote",
                    "generation=\(generation)",
                    "wasAuthenticated=\(self.isAuthenticated)",
                ])
                self.applySite = "leftoverSignOut.applyAfterRemote"
                #endif
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
        await run { client in
            let session = try await client.auth.signIn(email: email, password: password)
            self.adoptInteractiveSession(session)
        }
    }

    func signUp(email: String, password: String) async {
        await run { client in
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                self.adoptInteractiveSession(session)
            } else {
                self.statusMessage = "Check your email to confirm the account, then log in."
            }
        }
    }

    func resetPassword(email: String) async {
        await run { client in
            try await client.auth.resetPasswordForEmail(email)
            self.statusMessage = "If that email is registered, Cooper sent a reset link."
        }
    }

    func signOut() async {
        #if DEBUG
        AuthTransitionDiagnostics.record(fields: [
            "site=AuthManager.signOut",
            "wasAuthenticated=\(isAuthenticated)",
            "hasClient=\(client != nil)",
        ])
        applySite = "AuthManager.signOut"
        #endif
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
        #if DEBUG
        applySite = "AuthManager.signOut.afterRemote"
        #endif
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
        #if DEBUG
        AuthTransitionDiagnostics.record(fields: [
            "site=clearSessionAfterRemoteAccountDeletion",
            "wasAuthenticated=\(isAuthenticated)",
        ])
        applySite = "clearSessionAfterRemoteAccountDeletion"
        #endif
        apply(session: nil)
    }

    func signInWithApple() async {
        errorMessage = nil
        statusMessage = nil

        guard let client else {
            errorMessage = "Add SUPABASE_URL and the publishable key to Secrets.xcconfig, then build again."
            return
        }

        isProviderAuthenticationUIPresented = true
        defer {
            isProviderAuthenticationUIPresented = false
            isLoading = false
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

        // Mark in-flight before leftover-generation or GID presents.
        // Do not set isLoading here: SignInView disables the hosting controller
        // while isLoading, which can prevent the Google sheet from appearing.
        isProviderAuthenticationUIPresented = true
        defer {
            isProviderAuthenticationUIPresented = false
            isLoading = false
        }
        leftoverSignOutGeneration += 1
        #if DEBUG
        AuthTransitionDiagnostics.record(fields: [
            "site=signInWithGoogle.bumpLeftoverGeneration",
            "generation=\(leftoverSignOutGeneration)",
            "wasAuthenticated=\(isAuthenticated)",
        ])
        #endif
        LaunchLog.auth("Starting Google sign-in presenter=\(type(of: presenter))")
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
                statusMessage = "Google sign-in was cancelled."
            } else {
                errorMessage = Self.googleMessage(for: error)
            }
        }
    }

    static let missingGoogleClientIDMessage = """
    Google Sign-In needs the iOS OAuth Client ID. In Google Cloud Console → APIs & Services → Credentials, open the iOS client and paste Client ID into GOOGLE_IOS_CLIENT_ID (Info.plist GIDClientID). Then paste iOS URL scheme (reversed client ID) into GOOGLE_IOS_REVERSED_CLIENT_ID and add it as a URL Type.
    """

    private func configureClient() {
        let env = ProcessInfo.processInfo.environment
        #if DEBUG
        if CheckMedLocalIsolation.intentPresent(environment: env) {
            guard CheckMedLocalIsolation.isRequested(environment: env),
                  let url = AuthConfig.supabaseURL,
                  let key = AuthConfig.supabaseAnonKey,
                  AuthConfig.isIsolatedLoopbackEndpoint(url)
            else {
                client = nil
                LaunchLog.auth("isolation fail-closed: hosted Info.plist client refused")
                AuthIsolationDiagnostics.write(
                    intent: true,
                    requested: CheckMedLocalIsolation.isRequested(environment: env),
                    endpoint: AuthConfig.supabaseURL?.absoluteString ?? "nil",
                    hostedFallback: false,
                    probe: "not-sent"
                )
                return
            }
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: SupabaseClientOptions(
                    auth: .init(
                        storage: IsolatedLocalAuthStorage.shared,
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
            LaunchLog.auth("isolation client \(url.host ?? "?"):\(url.port.map(String.init) ?? "-")")
            let constructed = url
            Task { await AuthIsolationDiagnostics.probeHealth(clientURL: constructed) }
            return
        }
        #endif
        guard let url = AuthConfig.supabaseURL, let key = AuthConfig.supabaseAnonKey else {
            client = nil
            return
        }
        #if DEBUG
        if url.host?.contains("supabase.co") == true, CheckMedLocalIsolation.intentPresent(environment: env) {
            client = nil
            LaunchLog.auth("isolation fail-closed: blocked hosted supabase.co client")
            return
        }
        #endif
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
            isLoading = true
            let session = try await exchangeGoogleTokens(
                idToken: result.user.idToken?.tokenString,
                accessToken: result.user.accessToken.tokenString,
                nonce: rawNonce,
                client: client
            )
            adoptInteractiveSession(session)
        } catch {
            if let tokens = Self.liveGoogleTokens() {
                isLoading = true
                let session = try await exchangeGoogleTokens(
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    nonce: rawNonce,
                    client: client
                )
                adoptInteractiveSession(session)
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
    ) async throws -> Session {
        guard let idToken else { throw AuthFlowError.missingGoogleIDToken }
        return try await client.auth.signInWithIdToken(
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
        listenerTask = Self.observeAuthStateChanges(client: client) { [weak self] event, session in
            await self?.handleAuthChange(event, session)
        }
    }

    /// Must not inherit `@MainActor` from `start()` — otherwise `signIn` and the
    /// listener both sit on MainActor and a successful token response never applies.
    nonisolated private static func observeAuthStateChanges(
        client: SupabaseClient,
        onChange: @escaping @Sendable (AuthChangeEvent, Session?) async -> Void
    ) -> Task<Void, Never> {
        Task {
            LaunchLog.auth("listener registered")
            for await (event, session) in client.auth.authStateChanges {
                await onChange(event, session)
            }
            LaunchLog.auth("listener removed")
        }
    }

    /// Publish the SDK session immediately. Failed logins throw and never reach here.
    /// Must enqueue post-auth routing here: applying first makes the later
    /// `.signedIn` listener look like `sameUser` and skip `onAuthenticated`.
    private func adoptInteractiveSession(_ session: Session) {
        leftoverSignOutGeneration += 1
        interactiveAdoptCount += 1
        CheckMedAuthPersistence.skipRestoreThisProcess = false
        #if DEBUG
        AuthTransitionDiagnostics.record(fields: [
            "site=adoptInteractiveSession",
            "wasAuthenticated=\(isAuthenticated)",
            "hasSession=true",
        ])
        applySite = "adoptInteractiveSession"
        #endif
        apply(session: session)
        LaunchLog.auth("interactive session applied user=\(session.user.id.uuidString)")
        Task { [weak self] in
            guard let self else { return }
            LaunchLog.auth("interactive session enqueue post-auth hasUser=true")
            await self.onAuthenticated?(false)
        }
    }

    private func handleAuthChange(_ event: AuthChangeEvent, _ session: Session?) async {
        authEventCount += 1
        LaunchLog.auth(
            "Auth listener fired event=\(event) count=\(authEventCount) hasSession=\(session != nil) "
                + "user=\(session?.user.id.uuidString ?? "nil")"
        )
        #if DEBUG
        AuthTransitionDiagnostics.record(fields: [
            "site=handleAuthChange",
            "event=\(event)",
            "hasSession=\(session != nil)",
            "wasAuthenticated=\(isAuthenticated)",
            "skipRestore=\(CheckMedAuthPersistence.skipRestoreThisProcess)",
        ])
        #endif
        if CheckMedAuthPersistence.skipRestoreThisProcess, event == .initialSession {
            #if DEBUG
            applySite = "handleAuthChange.ignoreLeftoverInitialSession"
            #endif
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
        #if DEBUG
        applySite = "handleAuthChange.\(event)"
        #endif
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
        #if DEBUG
        let site = applySite
        applySite = "apply"
        if wasAuthenticated != (session != nil) {
            AuthTransitionDiagnostics.record(fields: [
                "site=apply",
                "callSite=\(site)",
                "wasAuthenticated=\(wasAuthenticated)",
                "willAuthenticate=\(session != nil)",
                "transition=\(wasAuthenticated && session == nil ? "authenticated->unsigned" : (!wasAuthenticated && session != nil ? "unsigned->authenticated" : "unchanged"))",
            ])
        }
        #endif
        isAuthenticated = session != nil
        email = session?.user.email
        if session != nil, !wasAuthenticated {
            LaunchLog.auth("Session created user=\(session?.user.id.uuidString ?? "nil")")
        }
        if let user = session?.user {
            let inferred = Self.inferredDisplayName(from: user)
            displayName = inferred.value
            displayNameInference = inferred.source
            if displayName == "friend", let pending = pendingAppleDisplayName, !pending.isEmpty {
                displayName = pending
                displayNameInference = .appleFullName
            }
            hasAppleIdentity = Self.userHasAppleIdentity(user)
        } else {
            displayName = "friend"
            displayNameInference = .friend
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

    private static func inferredDisplayName(from user: User) -> (value: String, source: DisplayNameInference) {
        if let name = user.userMetadata["full_name"]?.stringValue?.nilIfEmpty {
            return (name, .providerMetadata)
        }
        if let name = user.userMetadata["name"]?.stringValue?.nilIfEmpty {
            return (name, .providerMetadata)
        }
        if let email = user.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return (String(prefix), .emailLocalPart)
        }
        return ("friend", .friend)
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
                return "Google sign-in was cancelled."
            case GIDSignInError.keychain.rawValue, GIDSignInError.hasNoAuthInKeychain.rawValue:
                return "Google sign-in couldn't save or restore the account on this device. Try again."
            case GIDSignInError.EMM.rawValue:
                return "This Google account is managed by an organization and couldn't sign in here."
            case GIDSignInError.scopesAlreadyGranted.rawValue:
                return "Google already granted those permissions. Try again."
            case GIDSignInError.mismatchWithCurrentUser.rawValue:
                return "That Google account doesn't match the current user. Sign out and try again."
            default:
                let raw = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    return "Google sign-in didn't complete (error \(ns.code)). Try again."
                }
                return "Google sign-in didn't complete (error \(ns.code)): \(raw)"
            }
        }
        let raw = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.localizedCaseInsensitiveContains("nonce") || raw.localizedCaseInsensitiveContains("id_token") {
            return "Google sign-in couldn't be verified. Try again."
        }
        if raw.isEmpty {
            return "Google sign-in didn't complete. Try again."
        }
        return raw
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
        return ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue
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
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first
        let windows = (scene?.windows ?? []).filter { !$0.isHidden && $0.alpha > 0 }
        let ranked = windows.sorted { lhs, rhs in
            if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
            if (lhs.windowLevel == .normal) != (rhs.windowLevel == .normal) {
                return lhs.windowLevel == .normal
            }
            return false
        }
        for window in ranked {
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            guard let controller else { continue }
            if controller.viewIfLoaded?.window != nil || controller.view.window != nil {
                return controller
            }
        }
        return ranked.first?.rootViewController
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

#if DEBUG
/// Unsigned Simulator Keychain hangs or swallows session writes, so `currentUser`
/// stayed nil after HTTP 200. Isolation keeps the session in process memory only
/// (not UserDefaults tokens). Hosted/Release still uses Keychain.
private final class IsolatedLocalAuthStorage: AuthLocalStorage, @unchecked Sendable {
    static let shared = IsolatedLocalAuthStorage()

    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        values[key] = value
        lock.unlock()
        CheckMedAuthPersistence.bindSessionToThisInstall()
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        values[key] = nil
        lock.unlock()
    }
}
#endif

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

#if DEBUG
enum AuthIsolationDiagnostics {
    static let reportName = "checkmed-auth-isolation.txt"

    static func recordLaunch() {
        let env = ProcessInfo.processInfo.environment
        let keys = env.keys.filter { $0.contains("CHECKMED") }.sorted().joined(separator: ",")
        let url = AuthConfig.supabaseURL
        let hosted = url?.host?.contains("supabase.co") == true
        write(
            intent: CheckMedLocalIsolation.intentPresent(environment: env)
                || CheckMedLocalIsolation.intentPresent(environment: ProcessInfo.processInfo.environment),
            requested: CheckMedLocalIsolation.isRequested(environment: env),
            endpoint: url?.absoluteString ?? "nil",
            hostedFallback: hosted,
            probe: "launch-keys=\(keys.isEmpty ? "none" : keys)"
        )
        if CheckMedLocalIsolation.intentPresent(environment: env),
           let url,
           AuthConfig.isIsolatedLoopbackEndpoint(url)
        {
            Task { await probeHealth(clientURL: url) }
        }
    }

    static func write(
        intent: Bool,
        requested: Bool,
        endpoint: String,
        hostedFallback: Bool,
        probe: String
    ) {
        let body = [
            "intent: \(intent)",
            "requested: \(requested)",
            "endpoint: \(endpoint)",
            "hostedFallback: \(hostedFallback)",
            "probe: \(probe)",
        ].joined(separator: "\n")
        LaunchLog.auth("isolation diagnostics endpoint=\(endpoint) probe=\(probe)")
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? body.write(to: docs.appendingPathComponent(reportName), atomically: true, encoding: .utf8)
    }

    static func probeHealth(clientURL: URL) async {
        let hosted = clientURL.host?.contains("supabase.co") == true
        guard AuthConfig.isIsolatedLoopbackEndpoint(clientURL), !hosted else {
            write(
                intent: true,
                requested: true,
                endpoint: clientURL.absoluteString,
                hostedFallback: hosted,
                probe: "refused-non-local"
            )
            return
        }
        var request = URLRequest(url: clientURL.appending(path: "auth/v1/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("ChekMed-IsolationProbe", forHTTPHeaderField: "User-Agent")
        let probe: String
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            probe = "health-status=\(status) reached=\(clientURL.host ?? "?"):\(clientURL.port ?? -1)"
        } catch {
            probe = "health-error"
        }
        write(
            intent: true,
            requested: true,
            endpoint: clientURL.absoluteString,
            hostedFallback: false,
            probe: probe
        )
    }
}
#endif

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
