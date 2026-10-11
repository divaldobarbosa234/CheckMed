#if DEBUG
import Foundation

private enum SyncContractError: Error {
    case expected
}

private actor SyncContractGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

/// Transport-only contracts. Uses synthetic values and never contacts Supabase.
enum SyncTransportContractChecks {
    @MainActor
    static func failures() async -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var failedPullWrites = 0
        var failedPullSurfaced = false
        do {
            try await SyncTransportCycle.run {
                throw SyncContractError.expected
            } push: { (_: Int) in
                failedPullWrites += 1
            }
        } catch {
            failedPullSurfaced = true
        }
        expect(failedPullSurfaced, "sync: failed pull is surfaced")
        expect(failedPullWrites == 0, "sync: failed pull performs zero writes")

        var successfulWrites = 0
        var acknowledgementObserved = false
        do {
            try await SyncTransportCycle.run {
                42
            } push: { value in
                successfulWrites += 1
                await Task.yield()
                acknowledgementObserved = value == 42
            }
        } catch {
            failures.append("sync: successful pull/upload unexpectedly failed")
        }
        expect(successfulWrites == 1, "sync: successful pull allows upload")
        expect(acknowledgementObserved, "sync: completion waits for upload acknowledgement")

        var pushFailureSurfaced = false
        do {
            try await SyncTransportCycle.run {
                1
            } push: { (_: Int) in
                throw SyncContractError.expected
            }
        } catch {
            pushFailureSurfaced = true
        }
        expect(pushFailureSurfaced, "sync: push failure is surfaced")

        var completedTables: [String] = []
        var partialFailureSurfaced = false
        do {
            try await SyncTransportCycle.run {
                ()
            } push: {
                completedTables.append("treatments")
                throw SyncContractError.expected
            }
        } catch {
            partialFailureSurfaced = true
        }
        expect(partialFailureSurfaced, "sync: partial upload failure is not success")
        expect(completedTables == ["treatments"], "sync: writes stop at first failed table")

        var localMedicationNames = ["Synthetic medicine"]
        do {
            try await SyncTransportCycle.run {
                throw SyncContractError.expected
            } push: { (_: Void) in
                localMedicationNames.removeAll()
            }
        } catch {
            // Expected: the pull gate must leave the synthetic local cache untouched.
        }
        expect(
            localMedicationNames == ["Synthetic medicine"],
            "sync: failed pull preserves local medication data"
        )

        let gate = SyncContractGate()
        var requests: [SyncCycleCoordinator.Request] = []
        var activeRuns = 0
        var maximumActiveRuns = 0
        let coordinator = SyncCycleCoordinator { request in
            requests.append(request)
            activeRuns += 1
            maximumActiveRuns = max(maximumActiveRuns, activeRuns)
            if requests.count == 1 {
                await gate.wait()
            }
            activeRuns -= 1
            return true
        }

        let restore = coordinator.enqueue(
            SyncCycleCoordinator.Request(
                logSince: Date(timeIntervalSince1970: 100),
                shouldPush: false
            )
        )
        while requests.isEmpty {
            await Task.yield()
        }
        let mutation = coordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        )
        let coalescedMutation = coordinator.enqueue(
            SyncCycleCoordinator.Request(
                logSince: Date(timeIntervalSince1970: 50),
                shouldPush: true
            )
        )
        await gate.open()
        let restoreResult = await restore.value
        let mutationResult = await mutation.value
        let coalescedResult = await coalescedMutation.value

        expect(restoreResult && mutationResult && coalescedResult, "sync: serialized requests complete")
        expect(maximumActiveRuns == 1, "sync: restoration and normal uploads never overlap")
        expect(requests.count == 2, "sync: concurrent mutation requests coalesce into one follow-up")
        if requests.count == 2 {
            expect(!requests[0].shouldPush, "sync: restoration remains pull-only")
            expect(requests[1].shouldPush, "sync: mutation during restoration remains queued for upload")
            expect(requests[1].logSince == nil, "sync: full-log request dominates queued restore windows")
        }

        let failureGate = SyncContractGate()
        var failureRuns = 0
        let failureCoordinator = SyncCycleCoordinator { _ in
            failureRuns += 1
            if failureRuns == 1 {
                await failureGate.wait()
                return false
            }
            return true
        }
        let failedCycle = failureCoordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        )
        while failureRuns == 0 {
            await Task.yield()
        }
        _ = failureCoordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        )
        await failureGate.open()
        expect(!(await failedCycle.value), "sync: a failed cycle cannot report aggregate success")
        expect(failureRuns == 2, "sync: request arriving during failed cycle remains queued")
        let laterRetry = failureCoordinator.enqueue(
            SyncCycleCoordinator.Request(logSince: nil, shouldPush: true)
        )
        expect(await laterRetry.value, "sync: completed failure does not block a later retry")
        expect(failureRuns == 3, "sync: later retry starts a fresh cycle")

        return failures
    }
}
#endif
