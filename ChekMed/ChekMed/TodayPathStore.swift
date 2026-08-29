import Foundation

enum PathStatus {
    case done, current, locked, skipped
}

struct DoseNode: Identifiable {
    let id: String
    let time: String
    let medicine: String
    var status: PathStatus
}

enum CompanionMood: Equatable, Hashable {
    case idle, celebrate, skip, complete
}

@Observable
final class TodayPathStore {
    static let streakDays = 3
    static let offsets: [CGFloat] = [0, 28, -8]

    var nodes: [DoseNode] = [
        .init(id: "dose-1", time: "08:00", medicine: "Vitamin D 1000 IU", status: .done),
        .init(id: "dose-2", time: "13:00", medicine: "Metformin 500 mg", status: .current),
        .init(id: "dose-3", time: "21:00", medicine: "Atorvastatin 20 mg", status: .locked),
    ]
    var mood: CompanionMood = .idle

    var current: DoseNode? { nodes.first { $0.status == .current } }
    var completed: Int { nodes.filter { $0.status == .done || $0.status == .skipped }.count }
    var total: Int { nodes.count }
    var pathComplete: Bool { nodes.allSatisfy { $0.status == .done || $0.status == .skipped } }

    var displayMood: CompanionMood { pathComplete ? .complete : mood }

    var bubble: String {
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

    func takeCurrent() {
        advance(to: .done)
        mood = .celebrate
    }

    func skipCurrent() {
        advance(to: .skipped)
        mood = .skip
    }

    private func advance(to status: PathStatus) {
        guard let index = nodes.firstIndex(where: { $0.status == .current }) else { return }
        nodes[index].status = status
        let next = index + 1
        if next < nodes.count, nodes[next].status == .locked {
            nodes[next].status = .current
        }
    }
}
