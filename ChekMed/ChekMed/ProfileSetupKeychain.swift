import Foundation
import Security

/// Survives app delete. Used so reinstall + same Apple/Google account does not
/// replay preferred name → birth → pronouns once setup already finished, and so
/// returning welcome still recognizes an onboarded account after reinstall.
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
        // Completed before we had a user id (guest → later sign-in): claim for this user.
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

    static func clear() {
        delete(completeKey)
        delete(nameKey)
        delete(userKey)
        delete(birthKey)
        delete(pronounsKey)
        delete(genderKey)
        delete(onboardingKey)
        delete(onboardingUserKey)
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
