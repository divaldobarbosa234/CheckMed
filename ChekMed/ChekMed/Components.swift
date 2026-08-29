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
                .foregroundStyle(style == .primary ? Color.white : CheckMedTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(CheckMedTheme.ink, lineWidth: style == .secondary ? 2 : 0)
                )
                .shadow(color: style == .primary ? CheckMedTheme.primaryShadow : .clear, radius: 0, y: 4)
        }
        .buttonStyle(.plain)
        .modifier(PrimaryReturnKey(enabled: style == .primary))
    }

    @ViewBuilder
    private var background: some View {
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
            detentHeight: 320,
            onCancel: { dismiss() },
            onDone: {
                commit()
                dismiss()
            }
        ) {
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
                    ForEach(BirthDateWheels.months, id: \.self) { value in
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
        }
    }

    private func clampAndPublish() {
        let clamped = BirthDateWheels.clamped(day: day, month: month, year: year)
        if day != clamped.day { day = clamped.day }
        if month != clamped.month { month = clamped.month }
        if year != clamped.year { year = clamped.year }
        commit()
    }

    private func commit() {
        let clamped = BirthDateWheels.clamped(day: day, month: month, year: year)
        day = clamped.day
        month = clamped.month
        year = clamped.year
        guard let next = BirthDateWheels.date(day: day, month: month, year: year) else { return }
        date = next
        onCommit?(next)
    }
}

private enum BirthDateWheels {
    static let months = Array(1...12)
    static var years: [Int] {
        Array(1920...Calendar(identifier: .gregorian).component(.year, from: Date()))
    }

    static func days(month: Int, year: Int) -> [Int] {
        Array(1...dayCount(month: month, year: year))
    }

    static func dayCount(month: Int, year: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }

    static func monthName(_ month: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.monthSymbols
        let index = month - 1
        guard symbols.indices.contains(index) else { return String(month) }
        return symbols[index]
    }

    static func displayString(from date: Date) -> String {
        let parts = parts(from: date)
        return String(format: "%02d / %02d / %04d", parts.day, parts.month, parts.year)
    }

    static func parts(from date: Date?) -> (day: Int, month: Int, year: Int) {
        let calendar = Calendar(identifier: .gregorian)
        if let date {
            let c = calendar.dateComponents([.day, .month, .year], from: date)
            return clamped(day: c.day ?? 15, month: c.month ?? 8, year: c.year ?? 2001)
        }
        return (15, 8, 2001)
    }

    static func date(day: Int, month: Int, year: Int) -> Date? {
        let clamped = clamped(day: day, month: month, year: year)
        var components = DateComponents()
        components.year = clamped.year
        components.month = clamped.month
        components.day = clamped.day
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)
    }

    static func clamped(day: Int, month: Int, year: Int) -> (day: Int, month: Int, year: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let maxYear = calendar.component(.year, from: today)
        let maxMonthToday = calendar.component(.month, from: today)
        let maxDayToday = calendar.component(.day, from: today)

        var nextYear = min(max(year, 1920), maxYear)
        var nextMonth = min(max(month, 1), 12)
        if nextYear == maxYear {
            nextMonth = min(nextMonth, maxMonthToday)
        }
        var nextDay = min(max(day, 1), dayCount(month: nextMonth, year: nextYear))
        if nextYear == maxYear, nextMonth == maxMonthToday {
            nextDay = min(nextDay, maxDayToday)
        }
        return (nextDay, nextMonth, nextYear)
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
