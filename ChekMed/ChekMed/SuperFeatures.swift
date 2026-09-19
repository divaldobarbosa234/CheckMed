import AVFoundation
import Foundation
import SwiftUI

enum AlarmTheme: String, CaseIterable, Identifiable, Sendable {
    case philChime
    case gentle
    case bright
    case forest

    var id: String { rawValue }

    var soundFileName: String {
        switch self {
        case .philChime: "phil_chime.wav"
        case .gentle: "alarm_gentle.wav"
        case .bright: "alarm_bright.wav"
        case .forest: "alarm_forest.wav"
        }
    }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .philChime: session.t(.alarmThemePhil)
        case .gentle: session.t(.alarmThemeGentle)
        case .bright: session.t(.alarmThemeBright)
        case .forest: session.t(.alarmThemeForest)
        }
    }

    var tint: Color {
        switch self {
        case .philChime: CheckMedTheme.primary
        case .gentle: CheckMedTheme.current
        case .bright: CheckMedTheme.streak
        case .forest: CheckMedTheme.primaryShadow
        }
    }
}

enum MissedDoseAcknowledgement {
    private static let key = "checkmed.acknowledgedMissedLogs"

    static func contains(_ id: UUID) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }

    static func acknowledge(_ id: UUID) {
        var values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        values.insert(id.uuidString)
        UserDefaults.standard.set(Array(values), forKey: key)
    }
}

enum Engagement {
    private static let lastActiveKey = "checkmed.lastActiveAt"
    static let winBackId = "checkmed.winback"
    static let leaveSetupId = "checkmed.leaveSetup"

    static func ping() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastActiveKey)
    }

    static var lastActive: Date {
        let raw = UserDefaults.standard.double(forKey: lastActiveKey)
        if raw <= 0 { return Date() }
        return Date(timeIntervalSince1970: raw)
    }

    static func winBackDate(now: Date = Date()) -> Date? {
        guard ReminderPreferences.winBackEnabled else { return nil }
        let fire = lastActive.addingTimeInterval(72 * 60 * 60)
        return fire > now.addingTimeInterval(60) ? fire : nil
    }
}

enum ReminderPreferences {
    private enum Keys {
        static let theme = "checkmed.alarmTheme"
        static let quietHours = "checkmed.quietHoursEnabled"
        static let voiceReminders = "checkmed.voiceRemindersEnabled"
        static let advanceHour = "checkmed.advanceHourEnabled"
        static let winBack = "checkmed.winBackEnabled"
        static let graceMinutes = "checkmed.confirmGraceMinutes"
        static let snoozeMinutes = "checkmed.snoozeMinutes"
        static let lowStockDays = "checkmed.lowStockDays"
    }

    static var alarmTheme: AlarmTheme {
        get { AlarmTheme(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "") ?? .philChime }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.theme) }
    }

    static var quietHoursEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.quietHours) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.quietHours)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.quietHours) }
    }

    static var voiceRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.voiceReminders) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.voiceReminders) }
    }

    static var advanceHourEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.advanceHour) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.advanceHour)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.advanceHour) }
    }

    static var winBackEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.winBack) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.winBack)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.winBack) }
    }

    /// Follow-up after Stop/dismiss. Configurable; default 45 minutes (not a medical interval).
    static var confirmationGraceMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Keys.graceMinutes) as? Int
            return min(180, max(10, stored ?? 45))
        }
        set { UserDefaults.standard.set(min(180, max(10, newValue)), forKey: Keys.graceMinutes) }
    }

    static var confirmationGraceInterval: TimeInterval {
        TimeInterval(confirmationGraceMinutes * 60)
    }

    static var snoozeMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Keys.snoozeMinutes) as? Int
            return min(30, max(5, stored ?? 10))
        }
        set { UserDefaults.standard.set(min(30, max(5, newValue)), forKey: Keys.snoozeMinutes) }
    }

    static var snoozeInterval: TimeInterval {
        TimeInterval(snoozeMinutes * 60)
    }

    static var lowStockDaysThreshold: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Keys.lowStockDays) as? Int
            return min(7, max(1, stored ?? 2))
        }
        set { UserDefaults.standard.set(min(7, max(1, newValue)), forKey: Keys.lowStockDays) }
    }
}

@MainActor
@Observable
final class PhilVoice {
    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String, locale: AppLocale) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: locale.rawValue)
        utterance.rate = 0.44
        utterance.pitchMultiplier = 1.05
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

struct FamilyMember: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
}

@MainActor
@Observable
final class FamilyStore {
    private(set) var extra: FamilyMember?
    private(set) var activeId: UUID?
    private var ownerId: UUID?

    @ObservationIgnored
    var onCloudSync: (() async -> Void)?

    var occupiedSlots: Int { extra == nil ? 1 : 2 }
    var isViewingExtra: Bool {
        guard let extra, let activeId else { return false }
        return extra.id == activeId
    }

    func load(ownerId: UUID?) {
        self.ownerId = ownerId
        extra = Self.read(ownerId: ownerId)
        let storedActive = Self.readActive(ownerId: ownerId)
        if let extra, storedActive == extra.id {
            activeId = extra.id
        } else {
            activeId = nil
        }
    }

    @discardableResult
    func addExtra(name: String, allowed: Bool) -> Bool {
        guard allowed else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        extra = FamilyMember(id: extra?.id ?? UUID(), name: trimmed)
        persist()
        Task { await onCloudSync?() }
        return true
    }

    func removeExtra() {
        extra = nil
        activeId = nil
        persist()
        persistActive()
        Task { await onCloudSync?() }
    }

    func selectPrimary() {
        activeId = nil
        persistActive()
    }

    func selectExtra() -> Bool {
        guard let extra else { return false }
        activeId = extra.id
        persistActive()
        return true
    }

    func applyScope(to store: CheckMedStore, primaryProfileId: UUID?) {
        if let extra, extra.id == activeId {
            store.setActiveScope(profileId: extra.id, includeUnscoped: false)
        } else {
            store.setActiveScope(profileId: primaryProfileId, includeUnscoped: true)
        }
    }

    func applyRemote(id: UUID?, name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let id, !trimmed.isEmpty {
            extra = FamilyMember(id: id, name: trimmed)
        } else {
            extra = nil
        }
        persist()
    }

    private func persist() {
        guard let ownerId else { return }
        let key = Self.extraKey(ownerId)
        if let extra, let data = try? JSONEncoder().encode(extra) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func persistActive() {
        guard let ownerId else { return }
        let key = Self.activeKey(ownerId)
        if let activeId {
            UserDefaults.standard.set(activeId.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func read(ownerId: UUID?) -> FamilyMember? {
        guard let ownerId,
              let data = UserDefaults.standard.data(forKey: extraKey(ownerId))
        else { return nil }
        return try? JSONDecoder().decode(FamilyMember.self, from: data)
    }

    private static func readActive(ownerId: UUID?) -> UUID? {
        guard let ownerId,
              let raw = UserDefaults.standard.string(forKey: activeKey(ownerId))
        else { return nil }
        return UUID(uuidString: raw)
    }

    private static func extraKey(_ ownerId: UUID) -> String {
        "checkmed.family.extra.\(ownerId.uuidString)"
    }

    private static func activeKey(_ ownerId: UUID) -> String {
        "checkmed.family.active.\(ownerId.uuidString)"
    }
}

struct SuperLockBadge: View {
    var body: some View {
        Text("SUPER")
            .font(.system(.caption2, design: .rounded).weight(.black))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CheckMedTheme.superAccent, in: Capsule())
    }
}

struct VoiceReadButton: View {
    @Environment(SessionStore.self) private var session
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PhilVoice.self) private var voice
    let text: String

    var body: some View {
        CheckMedButton(
            title: session.t(.voiceReadAloud),
            style: entitlements.canUseVoiceReading ? .secondary : .ghost
        ) {
            if entitlements.canUseVoiceReading {
                voice.speak(text, locale: session.locale)
            } else {
                entitlements.presentPaywall()
            }
        }
    }
}
