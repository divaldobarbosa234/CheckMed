import Foundation
import Security

/// Survives app delete. Used so reinstall + same Apple/Google account does not
/// replay preferred name → birth once setup already finished (`isComplete` is a
/// stored flag, not a four-field check). Optional pronouns/gender may be empty.
/// Returning welcome still recognizes an onboarded account after reinstall.
///
/// Do not store language / how-it-works / privacy here — those are UserDefaults
/// and must start false after app delete.
enum ProfileSetupKeychain {
    private static let service = "app.checkmed.profileSetup"
    private static let completeKey = "checkmed.profileSetupComplete"
    private static let nameKey = "checkmed.profileSetupName"
    private static let userKey = "checkmed.profileSetupUserId"
    private static let birthKey = "checkmed.profileSetupBirth"
    private static let pronounsKey = "checkmed.profileSetupPronouns"
    private static let genderKey = "checkmed.profileSetupGender"
    private static let onboardingKey = "checkmed.onboardingComplete"
    private static let onboardingUserKey = "checkmed.onboardingCompleteUserId"
    private static let planConfirmedKey = "checkmed.medicationPlanConfirmed"
    private static let planConfirmedUserKey = "checkmed.medicationPlanConfirmedUserId"
    private static let postJourneyKey = "checkmed.postJourneyStep"
    private static let postJourneyUserKey = "checkmed.postJourneyStepUserId"
    private static let philPlanKey = "checkmed.philPlanStatus"
    private static let philPlanUserKey = "checkmed.philPlanStatusUserId"

    struct Snapshot: Equatable {
        var isComplete: Bool
        var userId: String?
        var displayName: String?
        var birthStamp: String?
        var pronouns: String?
        var gender: String?
    }

    static func load() -> Snapshot {
        Snapshot(
            isComplete: string(for: completeKey) == "1",
            userId: string(for: userKey),
            displayName: string(for: nameKey),
            birthStamp: string(for: birthKey),
            pronouns: string(for: pronounsKey),
            gender: string(for: genderKey)
        )
    }

    /// True when this device previously finished identity setup for `userId`
    /// (or an unscoped completion when `userId` is still unknown).
    static func isComplete(for userId: UUID?) -> Bool {
        let snap = load()
        guard snap.isComplete else { return false }
        guard let userId else {
            return snap.userId == nil
        }
        if let stored = snap.userId, !stored.isEmpty {
            return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
        }
        // Completed before we had a user id (leftover device flags → later sign-in): claim for this user.
        return true
    }

    static func markComplete(
        userId: UUID?,
        displayName: String?,
        birthStamp: String?,
        pronouns: String?,
        gender: String?
    ) {
        setString("1", for: completeKey)
        if let userId {
            setString(userId.uuidString, for: userKey)
        }
        if let displayName, !displayName.isEmpty, displayName != "there", displayName != "friend" {
            setString(displayName, for: nameKey)
        }
        if let birthStamp, !birthStamp.isEmpty {
            setString(birthStamp, for: birthKey)
        }
        if let pronouns, !pronouns.isEmpty {
            setString(pronouns, for: pronounsKey)
        }
        if let gender, !gender.isEmpty {
            setString(gender, for: genderKey)
        }
    }

    /// Bind an unscoped completion to the signed-in user without clearing the flag.
    static func associateUserIfNeeded(_ userId: UUID) {
        let snap = load()
        if snap.isComplete {
            if snap.userId == nil || snap.userId?.isEmpty == true {
                setString(userId.uuidString, for: userKey)
            }
        }
        // Same for onboarding flag so re-sign-in matches this Apple/Google user.
        if string(for: onboardingKey) == "1" {
            let stored = string(for: onboardingUserKey)
            if stored == nil || stored?.isEmpty == true {
                setString(userId.uuidString, for: onboardingUserKey)
            }
        }
        if string(for: planConfirmedKey) == "1" {
            let stored = string(for: planConfirmedUserKey)
            if stored == nil || stored?.isEmpty == true {
                setString(userId.uuidString, for: planConfirmedUserKey)
            }
        }
        if string(for: postJourneyKey) != nil {
            let stored = string(for: postJourneyUserKey)
            if stored == nil || stored?.isEmpty == true {
                setString(userId.uuidString, for: postJourneyUserKey)
            }
        }
        if string(for: philPlanKey) != nil {
            let stored = string(for: philPlanUserKey)
            if stored == nil || stored?.isEmpty == true {
                setString(userId.uuidString, for: philPlanUserKey)
            }
        }
    }

    /// True when this device previously finished full onboarding for `userId`.
    static func isOnboardingComplete(for userId: UUID?) -> Bool {
        guard string(for: onboardingKey) == "1" else { return false }
        guard let userId else {
            return string(for: onboardingUserKey) == nil
        }
        if let stored = string(for: onboardingUserKey), !stored.isEmpty {
            return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
        }
        return true
    }

    static func markOnboardingComplete(userId: UUID?) {
        setString("1", for: onboardingKey)
        if let userId {
            setString(userId.uuidString, for: onboardingUserKey)
        }
    }

    static func isPlanConfirmed(for userId: UUID?) -> Bool {
        guard string(for: planConfirmedKey) == "1" else { return false }
        guard let userId else {
            return string(for: planConfirmedUserKey) == nil
        }
        if let stored = string(for: planConfirmedUserKey), !stored.isEmpty {
            return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
        }
        return true
    }

    static func markPlanConfirmed(userId: UUID?) {
        setString("1", for: planConfirmedKey)
        if let userId {
            setString(userId.uuidString, for: planConfirmedUserKey)
        }
    }

    static func persistedPostJourneyStep(for userId: UUID?) -> String? {
        guard let raw = string(for: postJourneyKey), !raw.isEmpty, raw != "done" else { return nil }
        guard let userId else { return raw }
        if let stored = string(for: postJourneyUserKey), !stored.isEmpty {
            guard stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame else { return nil }
        }
        return raw
    }

    static func philPlanStatus(for userId: UUID?) -> String? {
        guard let raw = string(for: philPlanKey), !raw.isEmpty else { return nil }
        guard let userId else { return raw }
        if let stored = string(for: philPlanUserKey), !stored.isEmpty {
            guard stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame else { return nil }
        }
        return raw
    }

    static func persistPhilPlanStatus(_ status: String?, userId: UUID?) {
        if let status, !status.isEmpty {
            setString(status, for: philPlanKey)
            if let userId {
                setString(userId.uuidString, for: philPlanUserKey)
            }
        } else {
            delete(philPlanKey)
            delete(philPlanUserKey)
        }
    }

    static func persistPostJourneyStep(_ step: String?, userId: UUID?) {
        if let step, step != "done", !step.isEmpty {
            setString(step, for: postJourneyKey)
            if let userId {
                setString(userId.uuidString, for: postJourneyUserKey)
            }
        } else {
            delete(postJourneyKey)
            delete(postJourneyUserKey)
        }
    }

    static func clear() {
        delete(completeKey)
        delete(nameKey)
        delete(userKey)
        delete(birthKey)
        delete(pronounsKey)
        delete(genderKey)
        delete(onboardingKey)
        delete(onboardingUserKey)
        delete(planConfirmedKey)
        delete(planConfirmedUserKey)
        delete(postJourneyKey)
        delete(postJourneyUserKey)
        delete(philPlanKey)
        delete(philPlanUserKey)
    }

    /// Clear only when the stored user matches (account deletion).
    static func clear(for userId: UUID) {
        let snap = load()
        let profileMatches: Bool = {
            if let stored = snap.userId, !stored.isEmpty {
                return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
            }
            return true
        }()
        let onboardingMatches: Bool = {
            if let stored = string(for: onboardingUserKey), !stored.isEmpty {
                return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
            }
            return true
        }()
        if profileMatches {
            delete(completeKey)
            delete(nameKey)
            delete(userKey)
            delete(birthKey)
            delete(pronounsKey)
            delete(genderKey)
        }
        if onboardingMatches {
            delete(onboardingKey)
            delete(onboardingUserKey)
        }
        let planMatches: Bool = {
            if let stored = string(for: planConfirmedUserKey), !stored.isEmpty {
                return stored.caseInsensitiveCompare(userId.uuidString) == .orderedSame
            }
            return true
        }()
        if planMatches {
            delete(planConfirmedKey)
            delete(planConfirmedUserKey)
            delete(postJourneyKey)
            delete(postJourneyUserKey)
            delete(philPlanKey)
            delete(philPlanUserKey)
        }
    }

    // MARK: - Keychain primitives

    private static func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func setString(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
