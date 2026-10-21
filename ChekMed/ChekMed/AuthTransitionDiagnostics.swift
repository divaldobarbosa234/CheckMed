#if DEBUG
import Foundation
import os

/// DEBUG-only auth transition trace. Never records IDs, emails, tokens, or medicines.
enum AuthTransitionDiagnostics {
    static let reportName = "checkmed-auth-transition.txt"
    private static let maxRecords = 80
    private static let logger = Logger(subsystem: "com.checkmed.app", category: "AuthTransition")

    static func record(fields: [String]) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = ([stamp] + fields).joined(separator: " ")
        logger.info("\(line, privacy: .public)")
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
