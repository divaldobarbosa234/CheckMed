import Foundation
import Observation

/// Temporary launch-lifecycle breadcrumbs. Prefixes make restore/auth loops obvious in Console.
enum LaunchLog {
    static let launchId = String(UUID().uuidString.prefix(8))
    private static let processStart = Date()

    static func app(_ message: String) { log("APP", message) }
    static func auth(_ message: String) { log("AUTH", message) }
    static func restore(_ message: String) { log("RESTORE", message) }
    static func data(_ message: String) { log("DATA", message) }
    static func nav(_ message: String) { log("NAV", message) }
    static func plan(_ message: String) { log("PLAN", message) }
    static func home(_ message: String) { log("HOME", message) }
    static func sync(_ message: String) { log("SYNC", message) }
    static func alarm(_ message: String) { log("ALARM", message) }
    static func error(_ message: String) { log("ERROR", message) }

    private static func log(_ tag: String, _ message: String) {
        let ms = Int(Date().timeIntervalSince(processStart) * 1000)
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(tag)] \(stamp) +\(ms)ms Launch ID: \(launchId) \(message)")
    }
}

/// Temporary freeze investigation. Remove after the Dashboard interaction cause is proven.
enum FreezeDiag {
    private static let processStart = Date()
    private static var homeBodyCount = 0
    private static var lastHomeBodyAt: Date?
    private static var lastRevision = Int.min
    private static var lastNodeIds = ""
    private static var lastHasChanges: Bool?

    static func log(_ message: String) {
        let now = Date()
        let ms = Int(now.timeIntervalSince(processStart) * 1000)
        print("[FREEZE-DIAG] +\(ms)ms \(message)")
    }

    static func context(_ label: String, hasChanges: Bool) {
        if lastHasChanges == false, hasChanges == true {
            log("CONTEXT FALSE→TRUE at \(label)")
        } else if lastHasChanges == true, hasChanges == false {
            log("CONTEXT TRUE→FALSE at \(label)")
        }
        lastHasChanges = hasChanges
        log("CONTEXT \(label) hasChanges=\(hasChanges)")
    }

    static func caller() -> String {
        Thread.callStackSymbols
            .dropFirst(2)
            .prefix(10)
            .compactMap { frame -> String? in
                guard frame.contains("ChekMed") || frame.contains("CheckMed") else { return nil }
                return frame
                    .replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
            }
            .joined(separator: " ← ")
    }

    static func watch(_ name: String, _ read: () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            log("OBS INVALIDATE \(name)")
        }
    }

    static func homeBody(revision: Int, nodeIds: String, hasChanges: Bool) {
        homeBodyCount += 1
        let now = Date()
        let gap: String
        if let lastHomeBodyAt {
            gap = String(format: "%.0fms since prior body", now.timeIntervalSince(lastHomeBodyAt) * 1000)
        } else {
            gap = "first"
        }
        lastHomeBodyAt = now
        let revNote: String
        if lastRevision == Int.min {
            revNote = "revision=\(revision)"
        } else if lastRevision == revision {
            revNote = "revision UNCHANGED=\(revision)"
        } else {
            revNote = "revision CHANGED \(lastRevision)->\(revision)"
        }
        lastRevision = revision
        let nodeNote: String
        if lastNodeIds.isEmpty {
            nodeNote = "nodes=\(nodeIds)"
        } else if lastNodeIds == nodeIds {
            nodeNote = "nodes UNCHANGED count=\(nodeIds.split(separator: ",").count)"
        } else {
            nodeNote = "nodes CHANGED"
        }
        lastNodeIds = nodeIds
        log("HOME BODY #\(homeBodyCount) (\(gap)) \(revNote) \(nodeNote) swiftDataHasChanges=\(hasChanges)")
    }
}

/// DEBUG-only Report-tab timing. No production behavior.
enum ReportPerf {
    private static let clock = ContinuousClock()
    private static var tapAt: ContinuousClock.Instant?
    private static var bodyCount = 0
    private static var didReady = false

    static func tap() {
        #if DEBUG
        tapAt = clock.now
        bodyCount = 0
        didReady = false
        log("TAP")
        #endif
    }

    static func log(_ message: String) {
        #if DEBUG
        let now = clock.now
        let since: String
        if let tapAt {
            since = "+\(milliseconds(now - tapAt))ms"
        } else {
            since = "+?ms"
        }
        print("[REPORT-PERF] \(since) \(message) main=\(Thread.isMainThread)")
        #endif
    }

    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        #if DEBUG
        let start = clock.now
        log("START \(name)")
        let result = work()
        log("END \(name) duration=\(milliseconds(clock.now - start))ms")
        return result
        #else
        return work()
        #endif
    }

    static func reportBody() {
        #if DEBUG
        bodyCount += 1
        log("REPORT VIEW BODY #\(bodyCount)")
        #endif
    }

    static func ready() {
        #if DEBUG
        guard !didReady else { return }
        didReady = true
        log("REPORT READY")
        #endif
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000) + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

enum NetworkTimeoutError: Error, Sendable {
    case timedOut(TimeInterval)
}

enum NetworkDeadline {
    /// Timeout belongs on the network operation itself, then the caller sets `.error` / retry.
    static func run<T: Sendable>(
        seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                let ns = UInt64(max(1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw NetworkTimeoutError.timedOut(seconds)
            }
            guard let value = try await group.next() else {
                throw NetworkTimeoutError.timedOut(seconds)
            }
            group.cancelAll()
            return value
        }
    }
}
