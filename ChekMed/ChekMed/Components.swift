import SwiftUI

struct CheckMedButton: View {
    @Environment(\.locale) private var locale
    let title: String
    var style: Style = .primary
    let action: () -> Void

    enum Style { case primary, secondary, ghost }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased(with: locale))
                .font(.system(.body, design: .rounded).weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(style == .primary ? CheckMedTheme.onPrimary : CheckMedTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CheckMedTheme.ink, lineWidth: style == .secondary ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .background(alignment: .bottom) {
            if style == .primary {
                Capsule()
                    .fill(CheckMedTheme.primaryShadow)
                    .offset(y: 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, style == .primary ? 4 : 0)
        .contentShape(Capsule())
        .accessibilityLabel(title)
        .modifier(PrimaryReturnKey(enabled: style == .primary))
    }

    private var background: Color {
        switch style {
        case .primary: CheckMedTheme.primary
        case .secondary: CheckMedTheme.surface
        case .ghost: Color.clear
        }
    }
}

private struct PrimaryReturnKey: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CheckMedTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CheckMedTheme.ink, lineWidth: 2.5)
            )
    }
}

struct SafetyCaption: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Text(session.t(.safetyCaption))
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.safety)
            .multilineTextAlignment(.center)
    }
}

enum CheckMedTimeZones {
    static let all = [
        "UTC",
        "Europe/Madrid",
        "Europe/Lisbon",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "America/New_York",
        "America/Chicago",
        "America/Los_Angeles",
        "America/Sao_Paulo",
        "America/Mexico_City",
        "America/Argentina/Buenos_Aires",
        "Asia/Tokyo",
        "Asia/Shanghai",
        "Asia/Dubai",
        "Australia/Sydney",
        "Africa/Lagos",
        "Africa/Johannesburg",
        "Pacific/Auckland",
    ]

    static var preferred: String {
        resolved(TimeZone.current.identifier)
    }

    static func resolved(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Europe/Madrid" }
        return trimmed
    }

    static func options(including extra: String?) -> [String] {
        var items = all
        for candidate in [extra, TimeZone.current.identifier] {
            guard let candidate, !candidate.isEmpty, !items.contains(candidate) else { continue }
            items.insert(candidate, at: 1)
        }
        return items
    }
}

private struct SelectFieldChrome<Label: View>: View {
    let title: String
    var isPlaceholder = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CheckMedTheme.muted)
            Button(action: action) {
                HStack {
                    label()
                        .foregroundStyle(isPlaceholder ? CheckMedTheme.muted : CheckMedTheme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CheckMedTheme.ink.opacity(0.45))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckMedTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct WheelSheetChrome<Content: View>: View {
    @Environment(SessionStore.self) private var session
    var title: String?
    var showsCancel = true
    var detentHeight: CGFloat = 292
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsCancel {
                    Button(session.t(.cancel), action: onCancel)
                } else if let title {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                }
                Spacer()
                Button(session.t(.done), action: onDone)
                    .fontWeight(.semibold)
            }
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(CheckMedTheme.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CheckMedTheme.background)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(CheckMedTheme.background)
        .interactiveDismissDisabled(false)
    }
}

struct LanguageSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var locale: AppLocale
    var onCommit: ((AppLocale) -> Void)? = nil

    @State private var showPicker = false

    var body: some View {
        SelectFieldChrome(title: session.t(.language), action: { showPicker = true }) {
            Text(locale.displayName)
        }
        .accessibilityValue(locale.displayName)
        .sheet(isPresented: $showPicker) {
            LanguageWheelSheet(locale: $locale, onCommit: onCommit)
                .environment(session)
                .environment(\.locale, session.locale.foundationLocale)
        }
    }
}

private struct LanguageWheelSheet: View {
    @Environment(SessionStore.self) private var session
    @Binding var locale: AppLocale
    var onCommit: ((AppLocale) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppLocale

    init(locale: Binding<AppLocale>, onCommit: ((AppLocale) -> Void)? = nil) {
        self._locale = locale
        self.onCommit = onCommit
        self._draft = State(initialValue: locale.wrappedValue)
    }

    var body: some View {
        WheelSheetChrome(
            onCancel: { dismiss() },
            onDone: {
                locale = draft
                onCommit?(draft)
                dismiss()
            }
        ) {
            Picker(session.t(.language), selection: $draft) {
                ForEach(AppLocale.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 216)
        }
    }
}

struct LanguageWheelPicker: View {
    @Environment(SessionStore.self) private var session
    @Binding var locale: AppLocale
    var onChange: ((AppLocale) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            chevron("chevron.left") { shift(-1) }
            Picker(session.t(.language), selection: $locale) {
                ForEach(AppLocale.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 216)
            .onChange(of: locale) { _, next in
                onChange?(next)
            }
            chevron("chevron.right") { shift(1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.language))
        .accessibilityValue(locale.displayName)
    }

    private func shift(_ delta: Int) {
        let all = AppLocale.allCases
        guard let index = all.firstIndex(of: locale) else { return }
        let next = all[(index + delta + all.count) % all.count]
        locale = next
        onChange?(next)
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CheckMedTheme.primaryShadow)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

struct TimeZoneSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var timeZone: String
    var onCommit: ((String) -> Void)? = nil

    @State private var showPicker = false

    var body: some View {
        SelectFieldChrome(title: session.t(.timeZone), action: { showPicker = true }) {
            Text(timeZone)
        }
        .accessibilityValue(timeZone)
        .sheet(isPresented: $showPicker) {
            TimeZoneWheelSheet(timeZone: $timeZone, onCommit: onCommit)
                .environment(session)
                .environment(\.locale, session.locale.foundationLocale)
        }
    }
}

private struct TimeZoneWheelSheet: View {
    @Environment(SessionStore.self) private var session
    @Binding var timeZone: String
    var onCommit: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    private var options: [String] { CheckMedTimeZones.options(including: timeZone) }

    init(timeZone: Binding<String>, onCommit: ((String) -> Void)? = nil) {
        self._timeZone = timeZone
        self.onCommit = onCommit
        let current = CheckMedTimeZones.resolved(timeZone.wrappedValue)
        self._draft = State(initialValue: current)
    }

    var body: some View {
        WheelSheetChrome(
            onCancel: { dismiss() },
            onDone: {
                timeZone = draft
                onCommit?(draft)
                dismiss()
            }
        ) {
            Picker(session.t(.timeZone), selection: $draft) {
                ForEach(options, id: \.self) { zone in
                    Text(zone).tag(zone)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 216)
        }
    }
}

struct DateOfBirthSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var date: Date?
    var onCommit: ((Date) -> Void)? = nil

    @State private var showPicker = false

    var body: some View {
        SelectFieldChrome(
            title: session.t(.dateOfBirth),
            isPlaceholder: date == nil,
            action: { showPicker = true }
        ) {
            Text(date.map(BirthDateWheels.displayString) ?? session.t(.dateOfBirthPlaceholder))
                .monospacedDigit()
        }
        .accessibilityValue(date.map(BirthDateWheels.displayString) ?? session.t(.dateOfBirthPlaceholder))
        .sheet(isPresented: $showPicker) {
            DateOfBirthWheelSheet(date: $date, onCommit: onCommit)
                .environment(session)
                .environment(\.locale, session.locale.foundationLocale)
        }
    }
}

private struct DateOfBirthWheelSheet: View {
    @Environment(SessionStore.self) private var session
    @Binding var date: Date?
    var onCommit: ((Date) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var day: Int
    @State private var month: Int
    @State private var year: Int
    @State private var ageClampNote = false

    init(date: Binding<Date?>, onCommit: ((Date) -> Void)? = nil) {
        self._date = date
        self.onCommit = onCommit
        let parts = BirthDateWheels.parts(from: date.wrappedValue)
        self._day = State(initialValue: parts.day)
        self._month = State(initialValue: parts.month)
        self._year = State(initialValue: parts.year)
    }

    var body: some View {
        WheelSheetChrome(
            title: session.t(.dateOfBirth),
            showsCancel: false,
            detentHeight: 372,
            onCancel: { dismiss() },
            onDone: {
                commit()
                dismiss()
            }
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("Day", selection: $day) {
                        ForEach(BirthDateWheels.days(month: month, year: year), id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Month", selection: $month) {
                        ForEach(BirthDateWheels.months(year: year), id: \.self) { value in
                            Text(BirthDateWheels.monthName(value, locale: session.locale.foundationLocale)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Year", selection: $year) {
                        ForEach(BirthDateWheels.years, id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .labelsHidden()
                .frame(height: 216)
                .onChange(of: month) { _, _ in clampAndPublish() }
                .onChange(of: year) { _, _ in clampAndPublish() }
                .onChange(of: day) { _, _ in clampAndPublish() }

                Text(ageClampNote ? session.t(.dateOfBirthAgeClamped) : session.t(.dateOfBirthAgeHint))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(ageClampNote ? CheckMedTheme.ink : CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    private func clampAndPublish() {
        let result = BirthDateWheels.clampResult(day: day, month: month, year: year)
        if result.kind == .tooYoung || result.kind == .tooOld {
            ageClampNote = true
        }
        if day != result.day { day = result.day }
        if month != result.month { month = result.month }
        if year != result.year { year = result.year }
        commit()
    }

    private func commit() {
        let result = BirthDateWheels.clampResult(day: day, month: month, year: year)
        if result.kind == .tooYoung || result.kind == .tooOld {
            ageClampNote = true
        }
        day = result.day
        month = result.month
        year = result.year
        guard let next = BirthDateWheels.date(day: day, month: month, year: year) else { return }
        date = next
        onCommit?(next)
    }
}

enum BirthDateWheels {
    static let minAgeYears = 16
    static let maxAgeYears = 90

    enum ClampKind: Equatable {
        case none
        case calendarDay
        case tooYoung
        case tooOld
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static var years: [Int] {
        let oldest = rawParts(from: oldestAllowed())
        let youngest = rawParts(from: youngestAllowed())
        return Array(oldest.year...youngest.year)
    }

    static func months(year: Int) -> [Int] {
        let oldest = rawParts(from: oldestAllowed())
        let youngest = rawParts(from: youngestAllowed())
        var start = 1
        var end = 12
        if year <= oldest.year { start = oldest.month }
        if year >= youngest.year { end = youngest.month }
        return Array(start...max(start, end))
    }

    static func days(month: Int, year: Int) -> [Int] {
        let oldest = rawParts(from: oldestAllowed())
        let youngest = rawParts(from: youngestAllowed())
        let maxDay = dayCount(month: month, year: year)
        var start = 1
        var end = maxDay
        if year == oldest.year, month == oldest.month { start = oldest.day }
        if year == youngest.year, month == youngest.month { end = youngest.day }
        return Array(start...max(start, min(end, maxDay)))
    }

    static func youngestAllowed(on today: Date = Date()) -> Date {
        addingYears(-minAgeYears, to: today)
    }

    static func oldestAllowed(on today: Date = Date()) -> Date {
        addingYears(-maxAgeYears, to: today)
    }

    static func dayCount(month: Int, year: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = gregorian.date(from: components),
              let range = gregorian.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }

    static func monthName(_ month: Int, locale: Locale) -> String {
        var calendar = gregorian
        calendar.locale = locale
        let symbols = calendar.monthSymbols
        let index = month - 1
        guard symbols.indices.contains(index) else { return String(month) }
        return symbols[index]
    }

    static func displayString(from date: Date) -> String {
        let parts = rawParts(from: date)
        return String(format: "%02d / %02d / %04d", parts.day, parts.month, parts.year)
    }

    static func stamp(from date: Date) -> String {
        let parts = rawParts(from: date)
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    static func date(fromStamp stamp: String) -> Date? {
        let bits = stamp.split(separator: "-")
        guard bits.count == 3,
              let year = Int(bits[0]),
              let month = Int(bits[1]),
              let day = Int(bits[2]) else { return nil }
        return rawDate(day: day, month: month, year: year)
    }

    static func parts(from date: Date?) -> (day: Int, month: Int, year: Int) {
        let source = date ?? addingYears(-25, to: Date())
        let raw = rawParts(from: source)
        let clamped = clampResult(day: raw.day, month: raw.month, year: raw.year)
        return (clamped.day, clamped.month, clamped.year)
    }

    static func date(day: Int, month: Int, year: Int) -> Date? {
        let clamped = clampResult(day: day, month: month, year: year)
        return rawDate(day: clamped.day, month: clamped.month, year: clamped.year)
    }

    static func clamped(day: Int, month: Int, year: Int) -> (day: Int, month: Int, year: Int) {
        let result = clampResult(day: day, month: month, year: year)
        return (result.day, result.month, result.year)
    }

    static func clampedDate(_ date: Date) -> Date {
        let raw = rawParts(from: date)
        return self.date(day: raw.day, month: raw.month, year: raw.year) ?? date
    }

    static func clampResult(day: Int, month: Int, year: Int) -> (day: Int, month: Int, year: Int, kind: ClampKind) {
        var nextMonth = min(max(month, 1), 12)
        var nextYear = year
        let yearRange = years
        if let first = yearRange.first, let last = yearRange.last {
            nextYear = min(max(nextYear, first), last)
        }
        let allowedMonths = months(year: nextYear)
        if let first = allowedMonths.first, let last = allowedMonths.last {
            nextMonth = min(max(nextMonth, first), last)
        }
        var nextDay = min(max(day, 1), dayCount(month: nextMonth, year: nextYear))
        let allowedDays = days(month: nextMonth, year: nextYear)
        if let first = allowedDays.first, let last = allowedDays.last {
            nextDay = min(max(nextDay, first), last)
        }

        var kind: ClampKind = .none
        if nextDay != day || nextMonth != month || nextYear != year {
            kind = .calendarDay
        }

        guard let date = rawDate(day: nextDay, month: nextMonth, year: nextYear) else {
            let fallback = rawParts(from: youngestAllowed())
            return (fallback.day, fallback.month, fallback.year, .tooYoung)
        }

        let youngest = youngestAllowed()
        let oldest = oldestAllowed()
        if date > youngest {
            let parts = rawParts(from: youngest)
            return (parts.day, parts.month, parts.year, .tooYoung)
        }
        if date < oldest {
            let parts = rawParts(from: oldest)
            return (parts.day, parts.month, parts.year, .tooOld)
        }
        return (nextDay, nextMonth, nextYear, kind)
    }

    private static func addingYears(_ years: Int, to date: Date) -> Date {
        let raw = rawParts(from: date)
        guard let base = rawDate(day: raw.day, month: raw.month, year: raw.year) else { return date }
        return gregorian.date(byAdding: .year, value: years, to: base) ?? base
    }

    private static func rawParts(from date: Date) -> (day: Int, month: Int, year: Int) {
        let components = gregorian.dateComponents([.day, .month, .year], from: date)
        return (components.day ?? 1, components.month ?? 1, components.year ?? 2000)
    }

    private static func rawDate(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return gregorian.date(from: components)
    }
}

enum ProfilePronoun: String, CaseIterable, Identifiable {
    case sheHer = "she_her"
    case heHim = "he_him"
    case theyThem = "they_them"
    case preferNot = "prefer_not"
    case custom = "custom"

    var id: String { rawValue }

    var labelKey: L10n.Key {
        switch self {
        case .sheHer: .pronounShe
        case .heHim: .pronounHe
        case .theyThem: .pronounThey
        case .preferNot: .pronounPreferNot
        case .custom: .pronounCustom
        }
    }

    static func parsed(from stored: String?) -> (choice: ProfilePronoun, custom: String) {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (.theyThem, "")
        }
        if let match = ProfilePronoun(rawValue: stored) { return (match, "") }
        return (.custom, stored)
    }

    static func encoded(choice: ProfilePronoun, custom: String) -> String {
        if choice == .custom {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? choice.rawValue : trimmed
        }
        return choice.rawValue
    }
}

enum ProfileGender: String, CaseIterable, Identifiable {
    case woman = "woman"
    case man = "man"
    case nonBinary = "non_binary"
    case preferNot = "prefer_not"
    case custom = "custom"

    var id: String { rawValue }

    var labelKey: L10n.Key {
        switch self {
        case .woman: .genderWoman
        case .man: .genderMan
        case .nonBinary: .genderNonBinary
        case .preferNot: .genderPreferNot
        case .custom: .genderSelfDescribe
        }
    }

    static func parsed(from stored: String?) -> (choice: ProfileGender, custom: String) {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (.preferNot, "")
        }
        if let match = ProfileGender(rawValue: stored) { return (match, "") }
        return (.custom, stored)
    }

    static func encoded(choice: ProfileGender, custom: String) -> String {
        if choice == .custom {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? choice.rawValue : trimmed
        }
        return choice.rawValue
    }
}

struct PronounSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var value: String
    var onCommit: ((String) -> Void)? = nil

    @State private var showPicker = false

    private var parsed: (choice: ProfilePronoun, custom: String) { ProfilePronoun.parsed(from: value) }
    private var isPlaceholder: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        SelectFieldChrome(
            title: session.t(.pronouns),
            isPlaceholder: isPlaceholder,
            action: { showPicker = true }
        ) {
            Text(isPlaceholder ? session.t(.choosePlaceholder) : displayedLabel)
        }
        .sheet(isPresented: $showPicker) {
            IdentityWheelSheet(
                title: session.t(.pronouns),
                options: ProfilePronoun.allCases.map { ($0.rawValue, session.t($0.labelKey)) },
                customOptionID: ProfilePronoun.custom.rawValue,
                customPlaceholder: session.t(.customPronounsPlaceholder),
                initialID: isPlaceholder ? ProfilePronoun.theyThem.rawValue : parsed.choice.rawValue,
                initialCustom: parsed.custom,
                onCommit: { id, custom in
                    let choice = ProfilePronoun(rawValue: id) ?? .theyThem
                    let encoded = ProfilePronoun.encoded(choice: choice, custom: custom)
                    value = encoded
                    onCommit?(encoded)
                }
            )
            .environment(session)
            .environment(\.locale, session.locale.foundationLocale)
        }
    }

    private var displayedLabel: String {
        if parsed.choice == .custom, !parsed.custom.isEmpty { return parsed.custom }
        return session.t(parsed.choice.labelKey)
    }
}

struct GenderSelectField: View {
    @Environment(SessionStore.self) private var session
    @Binding var value: String
    var onCommit: ((String) -> Void)? = nil

    @State private var showPicker = false

    private var parsed: (choice: ProfileGender, custom: String) { ProfileGender.parsed(from: value) }
    private var isPlaceholder: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        SelectFieldChrome(
            title: session.t(.gender),
            isPlaceholder: isPlaceholder,
            action: { showPicker = true }
        ) {
            Text(isPlaceholder ? session.t(.choosePlaceholder) : displayedLabel)
        }
        .sheet(isPresented: $showPicker) {
            IdentityWheelSheet(
                title: session.t(.gender),
                options: ProfileGender.allCases.map { ($0.rawValue, session.t($0.labelKey)) },
                customOptionID: ProfileGender.custom.rawValue,
                customPlaceholder: session.t(.customGenderPlaceholder),
                initialID: isPlaceholder ? ProfileGender.preferNot.rawValue : parsed.choice.rawValue,
                initialCustom: parsed.custom,
                onCommit: { id, custom in
                    let choice = ProfileGender(rawValue: id) ?? .preferNot
                    let encoded = ProfileGender.encoded(choice: choice, custom: custom)
                    value = encoded
                    onCommit?(encoded)
                }
            )
            .environment(session)
            .environment(\.locale, session.locale.foundationLocale)
        }
    }

    private var displayedLabel: String {
        if parsed.choice == .custom, !parsed.custom.isEmpty { return parsed.custom }
        return session.t(parsed.choice.labelKey)
    }
}

private struct IdentityWheelSheet: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let options: [(id: String, label: String)]
    let customOptionID: String
    let customPlaceholder: String
    var onCommit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftID: String
    @State private var customText: String

    init(
        title: String,
        options: [(id: String, label: String)],
        customOptionID: String,
        customPlaceholder: String,
        initialID: String,
        initialCustom: String,
        onCommit: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.options = options
        self.customOptionID = customOptionID
        self.customPlaceholder = customPlaceholder
        self.onCommit = onCommit
        self._draftID = State(initialValue: initialID)
        self._customText = State(initialValue: initialCustom)
    }

    var body: some View {
        WheelSheetChrome(
            title: title,
            showsCancel: true,
            detentHeight: draftID == customOptionID ? 400 : 320,
            onCancel: { dismiss() },
            onDone: {
                onCommit(draftID, customText)
                dismiss()
            }
        ) {
            VStack(spacing: 12) {
                Picker(title, selection: $draftID) {
                    ForEach(options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 216)

                if draftID == customOptionID {
                    TextField(customPlaceholder, text: $customText)
                        .padding(14)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.ink, lineWidth: 2))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

struct GuestBanner: View {
    @Environment(SessionStore.self) private var session
    let onCreateAccount: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.t(.guestBannerTitle))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(session.t(.guestBannerBody))
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            .foregroundStyle(CheckMedTheme.ink)
            Spacer(minLength: 8)
            Button(session.t(.signIn), action: onCreateAccount)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(CheckMedTheme.ink, in: Capsule())
        }
        .padding(12)
        .background(CheckMedTheme.guestBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckMedTheme.guestBorder, lineWidth: 2)
        )
    }
}
