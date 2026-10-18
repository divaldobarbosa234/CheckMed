import Darwin
import Foundation

/// Launch-only Debug gate. Ordinary Debug and Release never set this.
enum CheckMedLocalIsolation {
    static let environmentKey = "CHECKMED_LOCAL_ISOLATION"
    static let simctlChildKey = "SIMCTL_CHILD_" + environmentKey
    static let requiredValue = "1"

    /// True when a launch asked for isolation, even if the value is not `1`
    /// or simctl left the `SIMCTL_CHILD_` prefix on the process environment.
    static func intentPresent(environment: [String: String]) -> Bool {
        flagValue(environment: environment) != nil
    }

    static func isRequested(environment: [String: String]) -> Bool {
        flagValue(environment: environment) == requiredValue
    }

    static func flagValue(environment: [String: String]) -> String? {
        if let value = environment[environmentKey] { return value }
        if let value = environment[simctlChildKey] { return value }
        if let value = posixValue(environmentKey) { return value }
        if let value = posixValue(simctlChildKey) { return value }
        return nil
    }

    private static func posixValue(_ key: String) -> String? {
        guard let pointer = getenv(key) else { return nil }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }
}

enum AuthConfig {

    static var supabaseURL: URL? {
        supabaseURL(environment: ProcessInfo.processInfo.environment)
    }

    static var supabaseAnonKey: String? {
        supabaseAnonKey(environment: ProcessInfo.processInfo.environment)
    }

    /// Isolated Debug: localhost only, never Info.plist / hosted Secrets.
    /// Isolation intent (unprefixed or `SIMCTL_CHILD_` key) never falls through
    /// to hosted Info.plist — invalid isolation fails closed with no client.
    /// All other launches: HTTPS Info.plist URL only.
    static func supabaseURL(environment: [String: String]) -> URL? {
        if CheckMedLocalIsolation.intentPresent(environment: environment) {
            #if DEBUG
            guard CheckMedLocalIsolation.isRequested(environment: environment) else { return nil }
            return isolatedLocalSupabaseURL()
            #else
            return nil
            #endif
        }
        guard let raw = string("SUPABASE_URL"), raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    static func supabaseAnonKey(environment: [String: String]) -> String? {
        if CheckMedLocalIsolation.intentPresent(environment: environment) {
            #if DEBUG
            guard CheckMedLocalIsolation.isRequested(environment: environment) else { return nil }
            return isolatedLocalAnonKey()
            #else
            return nil
            #endif
        }
        return string("SUPABASE_ANON_KEY")
    }

    #if DEBUG
    static func isIsolatedLoopbackEndpoint(_ url: URL) -> Bool {
        url.scheme == "http" && url.host == "127.0.0.1" && url.port == 54321
    }
    #endif

    /// Google Cloud Console → APIs & Services → Credentials → iOS OAuth 2.0 Client ID → **Client ID**.
    static var googleClientID: String? {
        string("GIDClientID")
    }

    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    static var isGoogleConfigured: Bool {
        googleClientID != nil
    }

    static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$(") { return nil }
        if trimmed.contains("YOUR_PROJECT") || trimmed.contains("YOUR_PUBLISHABLE") || trimmed.contains("YOUR_ANON") {
            return nil
        }
        return trimmed
    }

    #if DEBUG
    /// Fail-closed: local demo host + local-demo anon JWT, or no client.
    /// Never reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from Info.plist.
    private static func isolatedLocalSupabaseURL() -> URL? {
        let url = SyncProtocolTestActivation.disposableURL
        let key = SyncProtocolTestActivation.localDemoAnonKey
        guard SyncProtocolTestActivation.authorizes(url: url, anonKey: key) else { return nil }
        guard url.scheme == "http", url.host == "127.0.0.1", url.port == 54321 else { return nil }
        return url
    }

    private static func isolatedLocalAnonKey() -> String? {
        let url = SyncProtocolTestActivation.disposableURL
        let key = SyncProtocolTestActivation.localDemoAnonKey
        guard SyncProtocolTestActivation.authorizes(url: url, anonKey: key) else { return nil }
        return key
    }
    #endif
}
