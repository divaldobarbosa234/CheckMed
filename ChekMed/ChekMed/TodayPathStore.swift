import Foundation

enum PathStatus {
    case done, current, locked, skipped
}

struct DoseNode: Identifiable {
    let id: String
    let time: String
    let medicine: String
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

    func reload() {
        nodes = store?.todayNodes() ?? []
        if pathComplete {
            mood = .complete
        } else if current != nil, mood == .complete {
            mood = .idle
        }
    }

    var pendingFeeling: (logId: UUID, medicine: String)?

    func takeCurrent() {
        guard let current, let id = UUID(uuidString: current.id) else { return }
        store?.markLog(id: id, status: .taken)
        pendingFeeling = (id, current.medicine)
        mood = .celebrate
        reload()
    }

    func clearPendingFeeling() {
        pendingFeeling = nil
    }

    func skipCurrent() {
        guard let id = current.flatMap({ UUID(uuidString: $0.id) }) else { return }
        store?.markLog(id: id, status: .skipped)
        mood = .skip
        reload()
    }
}
