import Foundation

/// On-device essential catalog loaded from `MedicationCatalog.json` (~900 names, ~1400 aliases, ~144 KB).
/// Filter locally; never hit an unbounded remote dump on each keystroke.
struct MedicationCatalogEntry: Codable, Identifiable, Sendable, Hashable {
    var name: String
    var aliases: [String]
    var formHint: String
    var strengthHint: String

    var id: String { name }

    var subtitle: String {
        [formHint, strengthHint].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var searchableTokens: [String] {
        ([name] + aliases).map(Self.fold)
    }

    static func fold(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MedicationCatalog {
    private struct File: Codable {
        var version: Int
        var description: String
        var entryCount: Int
        var aliasCount: Int
        var items: [MedicationCatalogEntry]
    }

    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "MedicationCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(File.self, from: data)
        else {
            return File(version: 0, description: "", entryCount: 0, aliasCount: 0, items: [])
        }
        return decoded
    }()

    static var entries: [MedicationCatalogEntry] { file.items }
    static var entryCount: Int { file.entryCount }
    static var aliasCount: Int { file.aliasCount }
    /// Approximate on-disk size of the bundled JSON (bytes). Documented so the list can grow without a 50 MB download.
    static let bundledJSONBytes = 147_000

    static func suggestions(matching query: String, limit: Int = 8) -> [MedicationCatalogEntry] {
        let needle = MedicationCatalogEntry.fold(query)
        guard needle.count >= 1 else { return [] }
        var scored: [(Int, MedicationCatalogEntry)] = []
        scored.reserveCapacity(min(64, entries.count))
        for entry in entries {
            var best: Int?
            for token in entry.searchableTokens {
                guard !token.isEmpty else { continue }
                if token == needle {
                    best = 0
                    break
                }
                if token.hasPrefix(needle) {
                    best = min(best ?? 1, 1)
                } else if token.contains(needle) {
                    best = min(best ?? 2, 2)
                }
            }
            if let best {
                scored.append((best, entry))
            }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1.name.localizedCaseInsensitiveCompare(rhs.1.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.1)
    }

    /// Whole-token catalog hits in OCR text only.
    /// Uses the word as printed. Never remap an INN onto a brand (Amoxicilina → Amoxidal).
    static func wholeWordHits(in raw: String) -> [String] {
        let foldedRaw = MedicationCatalogEntry.fold(raw)
        guard foldedRaw.count >= 4 else { return [] }
        var hits: [String] = []
        var seen = Set<String>()
        let words = foldedRaw.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        for word in words {
            guard word.count >= 5, let name = exactNameIndex[word] else { continue }
            let key = MedicationCatalogEntry.fold(name.split(separator: " ").first.map(String.init) ?? name)
            guard seen.insert(key).inserted else { continue }
            hits.append(name)
            if hits.count >= 12 { break }
        }
        return hits
    }

    /// First token of `entry.name` only. Aliases must not replace a printed INN with a brand.
    private static let exactNameIndex: [String: String] = {
        var map: [String: String] = [:]
        for entry in entries {
            let folded = MedicationCatalogEntry.fold(entry.name)
            let first = folded.split(whereSeparator: { !$0.isLetter && $0 != "'" }).first.map(String.init) ?? folded
            guard first.count >= 5 else { continue }
            if first == folded {
                map[first] = entry.name
            } else if map[first] == nil {
                map[first] = entry.name
            }
        }
        return map
    }()
}
