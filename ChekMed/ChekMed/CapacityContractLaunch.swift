#if DEBUG
import Darwin
import Foundation
import SwiftUI

/// Launch-only DEBUG runner for `MedicationCapacitySafetyContractChecks`.
/// Interactive Debug and Release never set `CHECKMED_CAPACITY_CONTRACTS`.
enum CapacityContractLaunch {
    static let environmentKey = "CHECKMED_CAPACITY_CONTRACTS"
    static let simctlChildKey = "SIMCTL_CHILD_" + environmentKey
    static let reportName = "checkmed-capacity-contracts.txt"

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

    /// UIKit calls `didFinishLaunching` on the main thread. Do not wait for SwiftUI.
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
        MedicationCapacitySafetyContractChecks.lastExecutedCheckCount = 0
        let failures = MedicationCapacitySafetyContractChecks.failures()
        let count = MedicationCapacitySafetyContractChecks.lastExecutedCheckCount
        let result: String
        if count == 0 {
            result = "BLOCKED"
        } else if failures.isEmpty {
            result = "PASS"
        } else {
            result = "FAIL"
        }
        var lines = [
            "result: \(result)",
            "suite: MedicationCapacitySafetyContractChecks",
            "count: \(count)",
            "failures: \(failures.count)",
        ]
        if count == 0 {
            lines.append("blocked: contract-returned-zero-checks")
        }
        lines.append(contentsOf: failures.map { "failure: \($0)" })
        write(lines.joined(separator: "\n"))
        print("[CAPACITY-CONTRACT] \(result) checks=\(count) failures=\(failures.count)")
    }

    static func writeBlocked(_ reason: String) {
        write(
            [
                "result: BLOCKED",
                "suite: MedicationCapacitySafetyContractChecks",
                "count: 0",
                "blocked: \(reason)",
            ].joined(separator: "\n")
        )
    }

    private static func write(_ body: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[CAPACITY-CONTRACT] BLOCKED no Documents directory")
            return
        }
        try? body.write(
            to: docs.appendingPathComponent(reportName),
            atomically: true,
            encoding: .utf8
        )
    }
}

struct CapacityContractHost: View {
    var body: some View {
        Text("MedicationCapacitySafetyContractChecks")
            .padding()
    }
}
#endif
