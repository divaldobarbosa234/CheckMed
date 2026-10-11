#if DEBUG
import Foundation

/// DEBUG-only gate for the disposable isolated Supabase stack.
/// Release builds do not compile this type, so they cannot authorize consumption.
enum SyncProtocolTestActivation {
    static let disposableURL = URL(string: "http://127.0.0.1:54321")!
    static let localDemoIssuer = "supabase-demo"

    /// Public local-demo anon JWT shipped by `supabase start`. Not a production secret.
    static let localDemoAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    /// Public local-demo service-role JWT. Used only to seed disposable history rows.
    static let localDemoServiceRoleKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

    static func authorizes(url: URL, anonKey: String) -> Bool {
        guard url.scheme == "http" else { return false }
        guard url.host == "127.0.0.1" || url.host == "localhost" else { return false }
        guard url.port == 54321 else { return false }
        return isLocalDemoAnonKey(anonKey)
    }

    static func isLocalDemoAnonKey(_ key: String) -> Bool {
        jwtClaims(key)?["iss"] as? String == localDemoIssuer
            && jwtClaims(key)?["role"] as? String == "anon"
    }

    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
#endif
