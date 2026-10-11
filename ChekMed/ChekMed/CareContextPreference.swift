import Foundation

/// Persistent first-time Care Context preference. Not identity. Not medication.
/// UserDefaults keyed by authenticated user id — never Keychain or SwiftData.
enum CareContextChoice: String, CaseIterable, Equatable {
    case ongoing
    case vitamins
    case shortTerm
    case unsure

    var titleKey: L10n.Key {
        switch self {
        case .ongoing: .careContextOngoing
        case .vitamins: .careContextVitamins
        case .shortTerm: .careContextShortTerm
        case .unsure: .careContextUnsure
        }
    }
}

enum CareContextStore {
    static func defaultsKey(for userId: UUID) -> String {
        "checkmed.careContext.\(userId.uuidString)"
    }

    static func load(userId: UUID?) -> CareContextChoice? {
        guard let userId else { return nil }
        let raw = UserDefaults.standard.string(forKey: defaultsKey(for: userId)) ?? ""
        return CareContextChoice(rawValue: raw)
    }

    static func save(_ choice: CareContextChoice, userId: UUID?) {
        guard let userId else { return }
        UserDefaults.standard.set(choice.rawValue, forKey: defaultsKey(for: userId))
    }

    static func clear(for userId: UUID) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(for: userId))
    }
}

/// Required identity for leaving Personal Profile. Pronouns/gender are optional.
enum OnboardingIdentityPolicy {
    static func hasRequiredIdentity(hasPreferredName: Bool, hasBirthDate: Bool) -> Bool {
        hasPreferredName && hasBirthDate
    }

    /// Push when required remote fields are missing, or when optional local
    /// values exist and differ. Empty optional locals must not retrigger push.
    static func remoteNeedsPush(
        hasRequiredIdentity: Bool,
        remoteNameMissing: Bool,
        remoteDobMissing: Bool,
        localPronouns: String?,
        remotePronouns: String?,
        localGender: String?,
        remoteGender: String?
    ) -> Bool {
        guard hasRequiredIdentity else { return false }
        if remoteNameMissing || remoteDobMissing { return true }
        if let local = nonempty(localPronouns), local != nonempty(remotePronouns) {
            return true
        }
        if let local = nonempty(localGender), local != nonempty(remoteGender) {
            return true
        }
        return false
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
