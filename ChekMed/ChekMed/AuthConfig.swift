import Foundation

enum AuthConfig {

    static var supabaseURL: URL? {
        guard let raw = string("SUPABASE_URL"), raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String? {
        string("SUPABASE_ANON_KEY")
    }

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
}
