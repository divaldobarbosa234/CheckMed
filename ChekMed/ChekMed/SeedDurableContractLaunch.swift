#if DEBUG
import Darwin
import Foundation
import SwiftUI

/// Launch-only DEBUG runner for `SeedFromDraftsDurableContractChecks`.
/// Interactive Debug and Release never set `CHECKMED_SEED_DURABLE_CONTRACT`.
enum SeedDurableContractLaunch {
    static let environmentKey = "CHECKMED_SEED_DURABLE_CONTRACT"
    static let simctlChildKey = "SIMCTL_CHILD_" + environmentKey
    static let reportName = "checkmed-seed-durable-contract.txt"

    static var isRequested: Bool {
        flagValue() == "1"
    }

    private static func flagValue() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env[environmentKey], !value.isEmpty { return value }
        if let value = env[simctlChildKey], !value.isEmpty { return value }
        if let pointer = getenv(environmentKey) {
            let value = String(cString: pointer)
            if !value.isEmpty { return value }
        }
        if let pointer = getenv(simctlChildKey) {
            let value = String(cString: pointer)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static var shouldIsolateProcess: Bool { isRequested }

    static func runFromAppDelegate() {
        guard Thread.isMainThread else {
            writeBlocked("app-delegate-not-main")
            return
        }
        MainActor.assumeIsolated {
            runAndWriteReport()
        }
    }

    @MainActor
    static func runAndWriteReport() {
        let failures = SeedFromDraftsDurableContractChecks.failures()
        let result = failures.isEmpty ? "PASS" : "FAIL"
        var lines = [
            "result: \(result)",
            "suite: SeedFromDraftsDurableContractChecks",
            "executed: true",
            "writer: CheckMedStore.seedFromDrafts",
            "store: file-backed contractStoreURL",
            "reopenMode: same-process-new-container",
            "limitation: not a separate-process SQLite restart",
            "failures: \(failures.count)",
        ]
        lines.append(contentsOf: failures.map { "failure: \($0)" })
        write(lines.joined(separator: "\n"))
        print("[SEED-DURABLE-CONTRACT] \(result) failures=\(failures.count)")
    }

    static func writeBlocked(_ reason: String) {
        write(
            [
                "result: BLOCKED",
                "suite: SeedFromDraftsDurableContractChecks",
                "executed: false",
                "blocked: \(reason)",
            ].joined(separator: "\n")
        )
    }

    private static func write(_ body: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[SEED-DURABLE-CONTRACT] BLOCKED no Documents directory")
            return
        }
        try? body.write(
            to: docs.appendingPathComponent(reportName),
            atomically: true,
            encoding: .utf8
        )
    }
}

struct SeedDurableContractHost: View {
    var body: some View {
        Text("SeedFromDraftsDurableContractChecks")
            .padding()
    }
}
#endif
