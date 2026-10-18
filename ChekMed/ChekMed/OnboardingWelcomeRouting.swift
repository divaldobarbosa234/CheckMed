import Foundation

/// Pure first-time funnel routing for Welcome + Care Context + Profile.
/// Does not replace `SessionStore.rootDestination`. Host views call this for
/// the in-`FirstTimeOnboardingView` phase only.
enum OnboardingWelcomeRouting: Equatable {
    enum Step: String, Equatable {
        case language
        case privacy
        case signIn
        case welcome
        case careContext
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
        var hasCareContext = false
        var hasCompletedOnboarding = false
        var isReturningAuthenticated = false
        var needsIdentityProfile = true
        var userDataSettled = true
        var allowsGuest = false
    }

    /// Skip and Continue from Welcome share this destination.
    static func afterWelcome(hasCareContext: Bool, needsIdentityProfile: Bool) -> Step {
        if !hasCareContext { return .careContext }
        return afterCareContext(needsIdentityProfile: needsIdentityProfile)
    }

    static func afterCareContext(needsIdentityProfile: Bool) -> Step {
        needsIdentityProfile ? .profile : .addMedication
    }

    static func shouldPresentWelcome(_ input: Input) -> Bool {
        guard !input.allowsGuest else { return false }
        guard input.userDataSettled else { return false }
        guard input.isSessionUnlocked, input.hasCompletedSignInThisInstall else { return false }
        if input.hasCompletedOnboarding || input.isReturningAuthenticated { return false }
        return !input.hasSeenWelcome
    }

    static func shouldPresentCareContext(_ input: Input) -> Bool {
        guard !input.allowsGuest else { return false }
        guard input.userDataSettled else { return false }
        guard input.isSessionUnlocked, input.hasCompletedSignInThisInstall else { return false }
        if input.hasCompletedOnboarding || input.isReturningAuthenticated { return false }
        guard input.hasSeenWelcome else { return false }
        return !input.hasCareContext
    }

    /// Language → privacy → this-install Sign-in. Welcome is not part of this funnel.
    static func preSignInFunnelComplete(_ input: Input) -> Bool {
        input.hasChosenLanguage && input.hasAcknowledgedPrivacy && input.hasCompletedSignInThisInstall
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
        if !input.hasCareContext {
            return .careContext
        }
        return afterCareContext(needsIdentityProfile: input.needsIdentityProfile)
    }

    /// First Skip or Continue on Welcome wins; a second tap is a no-op.
    static func consumeWelcomeAdvance(alreadyFinished: Bool) -> Bool {
        !alreadyFinished
    }

    /// First Continue on Care Context wins; a second tap is a no-op.
    static func consumeCareContextAdvance(alreadyFinished: Bool) -> Bool {
        !alreadyFinished
    }

    /// First Continue on Personal Profile wins; a second tap is a no-op.
    static func consumeProfileAdvance(alreadyFinished: Bool) -> Bool {
        !alreadyFinished
    }
}
