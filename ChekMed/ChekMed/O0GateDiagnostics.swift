#if DEBUG
import Foundation

/// DEBUG-only O0 Sign-in advance trace. No credentials, tokens, emails, or user IDs.
enum O0GateDiagnostics {
    static let reportName = "checkmed-o0-gate.txt"
    private static let maxRecords = 24

    static func record(
        authenticated: Bool,
        restorationComplete: Bool,
        postAuthKind: String,
        phase: String,
        blockedBy: String?,
        advanced: Bool
    ) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = [
            stamp,
            "authenticated=\(authenticated)",
            "restorationComplete=\(restorationComplete)",
            "postAuthKind=\(postAuthKind)",
            "phase=\(phase)",
            "blockedBy=\(blockedBy ?? "none")",
            "advanced=\(advanced)",
        ].joined(separator: " ")
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = docs.appendingPathComponent(reportName)
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []
        lines.append(line)
        if lines.count > maxRecords {
            lines = Array(lines.suffix(maxRecords))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
