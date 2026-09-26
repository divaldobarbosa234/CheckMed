import Foundation

enum PathStatus {
    case done, current, locked, skipped
}

struct DoseNode: Identifiable {
    let id: String
    let time: String
    let medicine: String
    /// Stable medicine key for Home dashboard grouping (one row per medicine).
    var medicineId: UUID = UUID()
    var detail: String = ""
    var status: PathStatus
    var scheduledAt: Date = Date()
    /// Canonical DoseLog `.takenLate`. Presentation only — still a completed taken dose.
    var isTakenLate: Bool = false
}

enum CompanionMood: Equatable, Hashable {
    case idle, celebrate, skip, complete, sad
}

@Observable
final class TodayPathStore {
    static let offsets: [CGFloat] = [0, 28, -8]

    var nodes: [DoseNode] = []
    var mood: CompanionMood = .idle

    @ObservationIgnored
    private weak var store: CheckMedStore?
    @ObservationIgnored
    private var reloadTask: Task<Void, Never>?

    var current: DoseNode? { nodes.first { $0.status == .current } }
    var takenCount: Int { nodes.filter { $0.status == .done }.count }
    var skippedCount: Int { nodes.filter { $0.status == .skipped }.count }
    var completed: Int { takenCount + skippedCount }
    var total: Int { nodes.count }
    var pathComplete: Bool { !nodes.isEmpty && nodes.allSatisfy { $0.status == .done || $0.status == .skipped } }
    var streakDays: Int { store?.adherence().streakDays ?? 0 }
    var overdue: DoseNode? {
        nodes.first { node in
            (node.status == .current || node.status == .locked)
                && node.scheduledAt.addingTimeInterval(15 * 60) < Date()
        }
    }

    var displayMood: CompanionMood { pathComplete ? .complete : mood }

    func bind(store: CheckMedStore) {
        self.store = store
        reload()
        revealPendingFeeling()
    }

    /// Debounce observation churn from `notify()` so Home is not reloaded on every replica save.
    func scheduleReload() {
        FreezeDiag.log("path.scheduleReload() CALLED \(FreezeDiag.caller())")
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    func reload() {
        FreezeDiag.log("path.reload() START before=\(nodes.count)")
        LaunchLog.home("path.reload before=\(nodes.count)")
        let next = store?.todayNodes() ?? []
        let oldIds = nodes.map(\.id).joined(separator: ",")
        let newIds = next.map(\.id).joined(separator: ",")
        if oldIds != newIds {
            FreezeDiag.log("nodes WILL CHANGE oldCount=\(nodes.count) newCount=\(next.count)")
        } else {
            FreezeDiag.log("nodes assignment same ids count=\(next.count) (Observable still publishes)")
        }
        nodes = next
        FreezeDiag.log("path.reload() END after=\(nodes.count)")
        if pathComplete {
            mood = .complete
        } else if current != nil, mood == .complete {
            mood = .idle
        }
    }

    var pendingFeeling: (logId: UUID, medicine: String)?

    /// Home dashboard can show a Phil overlay now (tab + empty nav). Not medication state.
    @ObservationIgnored
    var dashboardPresentsPhil = false

    var shouldDeferFeelingPresentation: Bool {
        heldSheetPhil != nil || philPresentation != nil
    }

    @ObservationIgnored
    private var heldSheetPhil: (id: String, wasMissedLike: Bool)?

    /// Incremented when Challenge/Home should reopen the missed-dose sheet for remaining events.
    var missedSheetRequestNonce: UInt = 0
    /// Incremented when an external confirm should present Phil. Home consumes it once.
    var philPresentationNonce: UInt = 0
    @ObservationIgnored
    private var philPresentation: (id: String, wasMissedLike: Bool)?

    func preConfirmWasMissedLike(id: String) -> Bool {
        PhilCoach.wasMissedLikeBeforeConfirm(
            id: id,
            pathNodes: nodes,
            storeNodes: store?.todayNodes() ?? []
        )
    }

    /// Missed Challenge/Home taps must not confirm Taken. Re-present the existing sheet instead.
    func requestMissedSheetPresentation() {
        missedSheetRequestNonce &+= 1
    }

    /// Notification / AlarmKit Taken while Home can present. Discarded if Home is covered or away.
    func offerImmediatePhil(id: String, wasMissedLike: Bool) {
        guard dashboardPresentsPhil, heldSheetPhil == nil else { return }
        publishPhil(id: id, wasMissedLike: wasMissedLike)
    }

    /// Missed sheet confirm: remember one event, present only after the sheet closes.
    func holdPhilForMissedSheet(id: String, wasMissedLike: Bool) {
        heldSheetPhil = (id, wasMissedLike)
    }

    func noteMissedSheetClosed() {
        let held = heldSheetPhil
        heldSheetPhil = nil
        if let held, dashboardPresentsPhil {
            publishPhil(id: held.id, wasMissedLike: held.wasMissedLike)
        }
        revealPendingFeeling()
    }

    func takePhilPresentation() -> (id: String, wasMissedLike: Bool)? {
        let value = philPresentation
        philPresentation = nil
        return value
    }

    private func publishPhil(id: String, wasMissedLike: Bool) {
        philPresentation = (id, wasMissedLike)
        philPresentationNonce &+= 1
    }

    func takeCurrent() {
        guard let current else { return }
        take(id: current.id)
    }

    /// Mark a specific dose taken (Home trailing swipe).
    func take(id: String) {
        #if DEBUG
        print("[PHASE4A-REGRESSION] path.take id=\(id) pathCount=\(nodes.count)")
        #endif
        guard let uuid = UUID(uuidString: id) else {
            #if DEBUG
            print("[PHASE4A-REGRESSION] path.take STOP invalid uuid")
            #endif
            return
        }
        let node = nodes.first(where: { $0.id == id })
            ?? store?.todayNodes().first(where: { $0.id == id })
        guard let node else {
            #if DEBUG
            print("[PHASE4A-REGRESSION] path.take STOP node missing")
            #endif
            return
        }
        if node.status == .done {
            #if DEBUG
            print("[PHASE4A-REGRESSION] path.take STOP already confirmed")
            #endif
            return
        }
        if node.status == .skipped {
            #if DEBUG
            print("[PHASE4A-REGRESSION] path.take STOP missed — request sheet")
            #endif
            requestMissedSheetPresentation()
            return
        }
        #if DEBUG
        print("[PHASE4A-REGRESSION] confirmDoseTaken")
        #endif
        guard let store else { return }
        let revisionBefore = store.revision
        store.confirmDoseTaken(id: uuid)
        if store.revision == revisionBefore { return }
        MissedDoseAcknowledgement.acknowledge(uuid)
        ReminderScheduler.shared.handleTakenSideEffects(logId: uuid)
        queueFeelingAfterCompletion(logId: uuid, medicine: node.medicine)
        mood = .celebrate
        reload()
        #if DEBUG
        print("[PHASE4A-REGRESSION] takenCount changed \(takenCount)")
        #endif
    }

    func clearPendingFeeling() {
        FeelingCheckInQueue.clear()
        pendingFeeling = nil
    }

    /// Persist a feeling prompt without presenting (Take Late while the missed sheet is open).
    func persistFeelingRequest(logId: UUID, medicine: String) {
        FeelingCheckInQueue.enqueue(logId: logId, medicine: medicine)
    }

    /// Persist + restore into `pendingFeeling` for the existing Home sheet.
    func queueFeelingAfterCompletion(logId: UUID, medicine: String) {
        persistFeelingRequest(logId: logId, medicine: medicine)
        revealPendingFeeling()
    }

    func revealPendingFeeling() {
        guard let item = FeelingCheckInQueue.peek() else { return }
        if store?.hasFeelingRecord(forLogId: item.logId) == true {
            FeelingCheckInQueue.clearIfLogId(item.logId)
            if pendingFeeling?.logId == item.logId {
                pendingFeeling = nil
            }
            return
        }
        pendingFeeling = (item.logId, item.medicine)
    }

    func skipCurrent() {
        guard let id = current.flatMap({ UUID(uuidString: $0.id) }) else { return }
        store?.applyDoseAction(id: id, action: .didNotTake)
        MissedDoseAcknowledgement.acknowledge(id)
        mood = .skip
        reload()
    }
}
