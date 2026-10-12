import Foundation
import SwiftUI

/// Presentation rows for Treatment History. Derived from `journeyTreeSnapshot()` only.
struct TreatmentHistoryItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var medicineNames: [String]
    var startDate: Date
    var endDate: Date?
    var kind: TreatmentJourneyKind

    var displayTitle: String {
        let joined = medicineNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !joined.isEmpty { return joined }
        let fallback = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? joined : fallback
    }
}

enum TreatmentHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case completed

    var id: String { rawValue }

    var localizationKey: L10n.Key {
        switch self {
        case .all: .historyFilterAll
        case .active: .treatmentStatusActive
        case .completed: .treatmentStatusCompleted
        }
    }
}

struct TreatmentHistoryYearGroup: Identifiable, Equatable, Sendable {
    var year: Int
    var items: [TreatmentHistoryItem]
    var id: Int { year }
}

/// Pure History overview mapping. Does not read DoseLogs or write SwiftData.
enum TreatmentHistoryLayout {
    static let recentLimit = 3

    static func items(from snapshot: CheckMedStore.JourneyTreeSnapshot) -> [TreatmentHistoryItem] {
        snapshot.current.map { item(from: $0, kind: .current) }
            + snapshot.future.map { item(from: $0, kind: .future) }
            + snapshot.past.map { item(from: $0, kind: .past) }
    }

    static func item(from branch: CheckMedStore.JourneyTreeBranch, kind: TreatmentJourneyKind) -> TreatmentHistoryItem {
        TreatmentHistoryItem(
            id: branch.id,
            title: branch.title,
            medicineNames: branch.medicineNames,
            startDate: branch.startDate,
            endDate: branch.endDate,
            kind: kind
        )
    }

    static func matches(_ item: TreatmentHistoryItem, query: String, locale: Locale) -> Bool {
        let needle = fold(query, locale: locale)
        guard !needle.isEmpty else { return true }
        if fold(item.title, locale: locale).contains(needle) { return true }
        if fold(item.displayTitle, locale: locale).contains(needle) { return true }
        return item.medicineNames.contains { fold($0, locale: locale).contains(needle) }
    }

    static func fold(_ value: String, locale: Locale) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func filtered(
        _ items: [TreatmentHistoryItem],
        filter: TreatmentHistoryFilter,
        query: String,
        locale: Locale
    ) -> [TreatmentHistoryItem] {
        items.filter { item in
            switch filter {
            case .all: break
            case .active: if item.kind != .current { return false }
            case .completed: if item.kind != .past { return false }
            }
            return matches(item, query: query, locale: locale)
        }
    }

    static func recent(from items: [TreatmentHistoryItem]) -> [TreatmentHistoryItem] {
        Array(items.sorted { $0.startDate > $1.startDate }.prefix(recentLimit))
    }

    static func yearGroups(
        from items: [TreatmentHistoryItem],
        excluding recentIDs: Set<UUID>,
        calendar: Calendar
    ) -> [TreatmentHistoryYearGroup] {
        var buckets: [Int: [TreatmentHistoryItem]] = [:]
        for item in items where !recentIDs.contains(item.id) {
            let year = calendar.component(.year, from: item.startDate)
            buckets[year, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { year in
            let rows = (buckets[year] ?? []).sorted { $0.startDate > $1.startDate }
            return TreatmentHistoryYearGroup(year: year, items: rows)
        }
    }

    static func latestYear(in items: [TreatmentHistoryItem], calendar: Calendar) -> Int? {
        items.map { calendar.component(.year, from: $0.startDate) }.max()
    }
}

struct TreatmentHistoryScreen: View {
    var go: (AppRoute) -> Void
    @Environment(CheckMedStore.self) private var treatments
    @Environment(SessionStore.self) private var session
    @State private var query = ""
    @State private var filter: TreatmentHistoryFilter = .all
    @State private var collapsedYears: Set<Int> = []
    @State private var seededCollapseForYears: Set<Int> = []

    var body: some View {
        let _ = HistoryPerf.body()
        let snapshot = treatments.journeyTreeSnapshot()
        let _ = HistoryPerf.source("journeyTreeSnapshot")
        let calendar = session.foundationCalendar
        let locale = session.locale.foundationLocale
        let allItems = TreatmentHistoryLayout.items(from: snapshot)
        let visible = TreatmentHistoryLayout.filtered(
            allItems,
            filter: filter,
            query: query,
            locale: locale
        )
        let recent = TreatmentHistoryLayout.recent(from: visible)
        let recentIDs = Set(recent.map(\.id))
        let years = TreatmentHistoryLayout.yearGroups(
            from: visible,
            excluding: recentIDs,
            calendar: calendar
        )
        let activeCount = allItems.filter { $0.kind == .current }.count
        let completedCount = allItems.filter { $0.kind == .past }.count
        let latestYear = TreatmentHistoryLayout.latestYear(in: allItems, calendar: calendar)

        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if !allItems.isEmpty {
                    statsRow(completed: completedCount, active: activeCount, latestYear: latestYear)
                    searchField
                    filterChips
                }
                if allItems.isEmpty {
                    emptyCard
                } else if visible.isEmpty {
                    noResultsCard
                } else {
                    if !recent.isEmpty {
                        recentSection(recent)
                    }
                    ForEach(years) { group in
                        yearCard(group)
                    }
                    if !years.isEmpty {
                        archiveNote
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.progressHistory))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            HistoryPerf.open()
            seedCollapsedYearsIfNeeded(years.map(\.year))
            #if DEBUG
            let contractFailures = TreatmentHistoryContractChecks.failures()
            if !contractFailures.isEmpty {
                HistoryPerf.log("CONTRACTS FAIL \(contractFailures.joined(separator: "; "))")
            } else {
                HistoryPerf.log("CONTRACTS OK")
            }
            #endif
        }
        .onChange(of: years.map(\.year)) { _, newYears in
            seedCollapsedYearsIfNeeded(newYears)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                CooperLibraryImage(asset: "phil_doctor_2d", size: 92)
                CooperLibraryImage(asset: "phil_heart", size: 28)
                    .offset(x: 10, y: -6)
                    .accessibilityHidden(true)
            }
            .frame(width: 108, height: 100)
            Text(session.t(.historyIntro))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.ink)
                .padding(12)
                .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(CheckMedTheme.hairline, lineWidth: 1)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func statsRow(completed: Int, active: Int, latestYear: Int?) -> some View {
        HStack(spacing: 8) {
            statPill(
                value: "\(completed)",
                label: session.t(.treatmentStatusCompleted),
                wash: CheckMedTheme.mintWash,
                tint: CheckMedTheme.primaryShadow
            )
            statPill(
                value: "\(active)",
                label: session.t(.treatmentStatusActive),
                wash: CheckMedTheme.blueWash,
                tint: CheckMedTheme.flowDot
            )
            if let latestYear {
                statPill(
                    value: "\(latestYear)",
                    label: session.t(.historyLatestYear),
                    wash: CheckMedTheme.lavenderWash,
                    tint: CheckMedTheme.superAccent
                )
            }
        }
    }

    private func statPill(value: String, label: String, wash: Color, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckMedTheme.muted)
            TextField(session.t(.historySearchPlaceholder), text: $query)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("history-search")
        }
        .padding(12)
        .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(TreatmentHistoryFilter.allCases) { option in
                let selected = filter == option
                Button {
                    filter = option
                } label: {
                    Text(session.t(option.localizationKey))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(selected ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selected ? CheckMedTheme.navy : CheckMedTheme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(selected ? Color.clear : CheckMedTheme.hairline, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history-filter-\(option.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    private func recentSection(_ items: [TreatmentHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.t(.historyRecent))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
            ForEach(items) { item in
                historyRow(item)
            }
        }
    }

    private func yearCard(_ group: TreatmentHistoryYearGroup) -> some View {
        let expanded = !collapsedYears.contains(group.year)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if expanded {
                    collapsedYears.insert(group.year)
                } else {
                    collapsedYears.remove(group.year)
                }
            } label: {
                HStack {
                    Text(verbatim: String(group.year))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .accessibilityHidden(true)
                    Spacer()
                    Text(treatmentsCountLabel(group.items.count))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .accessibilityHidden(true)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-year-\(group.year)")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                session.t(
                    .historyYearHeaderA11y,
                    String(group.year),
                    treatmentsCountLabel(group.items.count)
                )
            )
            if expanded {
                ForEach(group.items) { item in
                    historyRow(item)
                }
            }
        }
        .padding(14)
        .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CheckMedTheme.hairline, lineWidth: 1.5)
        )
    }

    private func historyRow(_ item: TreatmentHistoryItem) -> some View {
        Button {
            HistoryPerf.log("OPEN DETAIL \(item.id.uuidString)")
            go(.treatmentDetail(item.id))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                MedicationLibraryImage(form: .other, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dateLine(item))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                statusChip(item.kind)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CheckMedTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-treatment-\(item.id.uuidString)")
        .accessibilityHint(session.t(.historyOpenDetailHint))
    }

    private func statusChip(_ kind: TreatmentJourneyKind) -> some View {
        let title: String
        let wash: Color
        let tint: Color
        switch kind {
        case .current:
            title = session.t(.treatmentStatusActive)
            wash = CheckMedTheme.mintWash
            tint = CheckMedTheme.primaryShadow
        case .past:
            title = session.t(.treatmentStatusCompleted)
            wash = CheckMedTheme.mintWash
            tint = CheckMedTheme.primaryShadow
        case .future:
            title = session.t(.treatmentsUpcomingTitle)
            wash = CheckMedTheme.blueWash
            tint = CheckMedTheme.flowDot
        }
        return Text(title)
            .font(.system(.caption2, design: .rounded).weight(.heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(wash, in: Capsule())
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                CooperLibraryImage(asset: "phil_onboarding_01_intro", size: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.t(.historyEmptyHeadline))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                    Text(session.t(.historyEmptyBody))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("history-empty")
    }

    private var noResultsCard: some View {
        Text(session.t(.historyNoResults))
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(CheckMedTheme.muted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityIdentifier("history-no-results")
    }

    private var archiveNote: some View {
        HStack(alignment: .center, spacing: 12) {
            CooperLibraryImage(asset: "phil_reading", size: 72)
            Text(session.t(.historyArchiveNote))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.ink)
                .padding(12)
                .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func treatmentsCountLabel(_ count: Int) -> String {
        count == 1
            ? session.t(.historyTreatmentsOne, count)
            : session.t(.historyTreatmentsMany, count)
    }

    private func dateLine(_ item: TreatmentHistoryItem) -> String {
        let start = formatted(item.startDate)
        if let end = item.endDate {
            return "\(start) – \(formatted(end))"
        }
        return "\(session.t(.progressTreatmentStarted)) · \(start)"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = session.foundationCalendar
        formatter.locale = session.locale.foundationLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return formatter.string(from: date)
    }

    private func seedCollapsedYearsIfNeeded(_ years: [Int]) {
        let incoming = Set(years)
        guard incoming != seededCollapseForYears else { return }
        let newest = years.first
        var collapsed = incoming
        if let newest {
            collapsed.remove(newest)
        }
        collapsedYears = collapsed
        seededCollapseForYears = incoming
    }
}

#if DEBUG
enum TreatmentHistoryContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day: (Int, Int, Int) -> Date = { y, m, d in
            calendar.date(from: DateComponents(year: y, month: m, day: d))!
        }
        let locale = Locale(identifier: "en")
        let a = TreatmentHistoryItem(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "Winter course",
            medicineNames: ["Amoxicilina 500mg", "Ibuprofeno"],
            startDate: day(2026, 10, 1),
            endDate: day(2026, 10, 3),
            kind: .current
        )
        let b = TreatmentHistoryItem(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: "Past plan",
            medicineNames: ["Paracetamol"],
            startDate: day(2025, 2, 10),
            endDate: day(2025, 2, 15),
            kind: .past
        )
        let c = TreatmentHistoryItem(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: "Older",
            medicineNames: ["Metformina"],
            startDate: day(2024, 1, 10),
            endDate: nil,
            kind: .past
        )
        let d = TreatmentHistoryItem(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            title: "Soon",
            medicineNames: ["Vitamina D"],
            startDate: day(2026, 12, 1),
            endDate: nil,
            kind: .future
        )
        let all = [a, b, c, d]

        expect(
            TreatmentHistoryLayout.matches(a, query: "amoxicilina", locale: locale),
            "history: case-insensitive medicine match"
        )
        expect(
            TreatmentHistoryLayout.matches(a, query: "AMOXICILINA", locale: locale),
            "history: uppercase query matches"
        )
        expect(
            TreatmentHistoryLayout.matches(
                TreatmentHistoryItem(
                    id: a.id, title: a.title, medicineNames: ["Paracétamol"],
                    startDate: a.startDate, endDate: a.endDate, kind: .past
                ),
                query: "paracetamol",
                locale: locale
            ),
            "history: accent-insensitive medicine match"
        )
        expect(
            TreatmentHistoryLayout.filtered(all, filter: .active, query: "", locale: locale).map(\.id) == [a.id],
            "history: Active filter is current only"
        )
        expect(
            TreatmentHistoryLayout.filtered(all, filter: .completed, query: "", locale: locale).map(\.id) == [b.id, c.id],
            "history: Completed filter is past only"
        )
        expect(
            !TreatmentHistoryLayout.filtered(all, filter: .all, query: "", locale: locale).contains { $0.kind == .current && $0.id != a.id }
                && TreatmentHistoryLayout.filtered(all, filter: .all, query: "", locale: locale).contains { $0.kind == .future },
            "history: All includes upcoming without inventing paused"
        )

        let recent = TreatmentHistoryLayout.recent(from: all)
        expect(recent.count == 3, "history: recent cap is 3")
        expect(recent.map(\.id) == [d.id, a.id, b.id], "history: recent is newest startDate first")
        let years = TreatmentHistoryLayout.yearGroups(
            from: all,
            excluding: Set(recent.map(\.id)),
            calendar: calendar
        )
        expect(years.allSatisfy { group in group.items.allSatisfy { item in !recent.map(\.id).contains(item.id) } },
               "history: year groups exclude recent ids")
        expect(years.map(\.year) == [2024], "history: leftover year is older only")
        expect(
            TreatmentHistoryLayout.latestYear(in: all, calendar: calendar) == 2026,
            "history: latest year from real start dates"
        )
        return failures
    }
}
#endif
