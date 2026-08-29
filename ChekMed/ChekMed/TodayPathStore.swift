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
    case idle, celebrate, skip, complete
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

    var bubble: String {
        if nodes.isEmpty {
            return "I'm Phil. Scan a paper when you want me to organize it with you."
        }
        if pathComplete {
            return "Path complete — that's the loop. I'm Phil, and I'll host tomorrow too."
        }
        if mood == .celebrate, let current {
            return "Logged. That's how we keep the streak warm. Next up: \(current.medicine) at \(current.time)."
        }
        if mood == .skip, let current {
            return "No sweat. We'll try the next one together — \(current.medicine) at \(current.time)."
        }
        if let current {
            return "I'm Phil. Today is a path, not a table. Ready for \(current.medicine) at \(current.time)?"
        }
        return "I'm Phil. Scan a paper when you want me to organize it with you."
    }

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

    func takeCurrent() {
        guard let id = current.flatMap({ UUID(uuidString: $0.id) }) else { return }
        store?.markLog(id: id, status: .taken)
        mood = .celebrate
        reload()
    }

    func skipCurrent() {
        guard let id = current.flatMap({ UUID(uuidString: $0.id) }) else { return }
        store?.markLog(id: id, status: .skipped)
        mood = .skip
        reload()
    }
}
