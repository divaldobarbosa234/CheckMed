import Foundation

/// Pure first-time funnel routing for O0/O1 Welcome.
/// Does not replace `SessionStore.rootDestination`. Host views call this for
/// the in-`FirstTimeOnboardingView` phase only.
enum OnboardingWelcomeRouting: Equatable {
    enum Step: String, Equatable {
        case language
        case privacy
        case signIn
        case welcome
        case profile
        case addMedication
        case home
        case restoring
    }

    struct Input: Equatable {
        var hasChosenLanguage = false
        var hasAcknowledgedPrivacy = false
        var hasCompletedSignInThisInstall = false
        var isSessionUnlocked = false
        var hasSeenWelcome = false
        var hasCompletedOnboarding = false
        var isReturningAuthenticated = false
        var needsIdentityProfile = true
        var userDataSettled = true
        var allowsGuest = false
    }

    /// Skip and Continue share this destination.
    static func afterWelcome(needsIdentityProfile: Bool) -> Step {
        needsIdentityProfile ? .profile : .addMedication
    }

    static func shouldPresentWelcome(_ input: Input) -> Bool {
        guard !input.allowsGuest else { return false }
        guard input.userDataSettled else { return false }
        guard input.isSessionUnlocked, input.hasCompletedSignInThisInstall else { return false }
        if input.hasCompletedOnboarding || input.isReturningAuthenticated { return false }
        return !input.hasSeenWelcome
    }

    static func hostPhase(_ input: Input) -> Step {
        if input.allowsGuest {
            return .signIn
        }
        if input.isSessionUnlocked, !input.userDataSettled {
            return .restoring
        }
        if !input.hasChosenLanguage {
            return .language
        }
        if !input.hasAcknowledgedPrivacy {
            return .privacy
        }
        if !input.hasCompletedSignInThisInstall || !input.isSessionUnlocked {
            return .signIn
        }
        if input.hasCompletedOnboarding || input.isReturningAuthenticated {
            return .home
        }
        if !input.hasSeenWelcome {
            return .welcome
        }
        return afterWelcome(needsIdentityProfile: input.needsIdentityProfile)
    }

    /// First Skip or Continue wins; a second tap is a no-op.
    static func consumeWelcomeAdvance(alreadyFinished: Bool) -> Bool {
        !alreadyFinished
    }
}
