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
        // Optional preference. Onboarded / returning users go Home (or resume
        // their real unfinished step). Missing Care Context does not restart
        // first-time onboarding.
        if input.hasCompletedOnboarding || input.isReturningAuthenticated { return false }
        guard input.hasSeenWelcome else { return false }
        return !input.hasCareContext
    }

    /// Root `.accountProfile` / Home must not run while Welcome or Care Context is still due
    /// for a first-time user. Must not keep a previously onboarded user on the first-time host
    /// just because the optional Care Context preference is missing.
    static func shouldKeepFirstTimeHost(_ input: Input) -> Bool {
        shouldPresentWelcome(input) || shouldPresentCareContext(input)
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
        if !input.hasSeenWelcome, !input.hasCompletedOnboarding, !input.isReturningAuthenticated {
            return .welcome
        }
        if shouldPresentCareContext(input) {
            return .careContext
        }
        if input.hasCompletedOnboarding || input.isReturningAuthenticated {
            return .home
        }
        return afterCareContext(needsIdentityProfile: input.needsIdentityProfile)
    }

    /// Mirrors `SessionStore.computeRootDestination`. SessionStore must call this;
    /// do not re-implement the ladder elsewhere.
    enum AppRoot: String, Equatable {
        case restoring
        case resolvingPostAuth
        case loadError
        case firstTime
        case resumeSetup
        case returningWelcome
        case accountProfile
        case addPrescription
        case home
    }

    struct RootInput: Equatable {
        var launchRestoreReleased = false
        var isRestoring = true
        var isSessionUnlocked = false
        var userDataFailed = false
        var userDataSettled = false
        var isResolvingPostAuth = false
        var isPlanSurfaceReady = false
        var hasActivePostJourney = false
        var showResumeSetup = false
        var needsReturningWelcomeGate = false
        var needsIdentityProfile = true
        var isReturningConfiguredUser = false
        var startFreshPrescription = false
        var hasCompletedOnboarding = false
        var hasActiveFirstTimeIntake = false
        var funnel = Input()
    }

    static func appRoot(_ input: RootInput) -> AppRoot {
        if !input.launchRestoreReleased, input.isRestoring {
            return .restoring
        }
        if input.isSessionUnlocked, input.userDataFailed {
            return .loadError
        }
        let legalDone = input.funnel.hasChosenLanguage && input.funnel.hasAcknowledgedPrivacy
        if !input.isReturningConfiguredUser,
           (!legalDone || !input.funnel.hasCompletedSignInThisInstall || !input.isSessionUnlocked) {
            return .firstTime
        }
        if !input.isSessionUnlocked {
            return .firstTime
        }
        if input.isResolvingPostAuth {
            return .resolvingPostAuth
        }
        if input.isSessionUnlocked, !input.userDataSettled {
            return .resolvingPostAuth
        }
        if input.isSessionUnlocked, !input.isPlanSurfaceReady {
            return .resolvingPostAuth
        }
        if input.hasActivePostJourney {
            return .resumeSetup
        }
        if input.showResumeSetup {
            return .resumeSetup
        }
        if input.needsReturningWelcomeGate {
            return .returningWelcome
        }
        if input.needsIdentityProfile && !input.isReturningConfiguredUser {
            if shouldKeepFirstTimeHost(input.funnel) {
                return .firstTime
            }
            return .accountProfile
        }
        if input.startFreshPrescription {
            return .addPrescription
        }
        // Confirm / add-medication drafts live on the first-time host. Saving
        // Care Context or marking returning must not unmount that screen.
        if input.hasActiveFirstTimeIntake {
            return .firstTime
        }
        if !input.hasCompletedOnboarding, !input.isReturningConfiguredUser {
            return .firstTime
        }
        if shouldKeepFirstTimeHost(input.funnel) {
            return .firstTime
        }
        return .home
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
