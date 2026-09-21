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
        #if DEBUG
        print("[PHASE4A-REGRESSION] confirmDoseTaken")
        #endif
        store?.confirmDoseTaken(id: uuid)
        MissedDoseAcknowledgement.acknowledge(uuid)
        ReminderScheduler.shared.handleTakenSideEffects(logId: uuid)
        pendingFeeling = (uuid, node.medicine)
        mood = .celebrate
        reload()
        #if DEBUG
        print("[PHASE4A-REGRESSION] takenCount changed \(takenCount)")
        #endif
    }

    func clearPendingFeeling() {
        pendingFeeling = nil
    }

    func skipCurrent() {
        guard let id = current.flatMap({ UUID(uuidString: $0.id) }) else { return }
        store?.applyDoseAction(id: id, action: .didNotTake)
        MissedDoseAcknowledgement.acknowledge(id)
        mood = .skip
        reload()
    }
}
