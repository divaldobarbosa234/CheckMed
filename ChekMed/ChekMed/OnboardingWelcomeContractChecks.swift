#if DEBUG
import Foundation

/// O0 Welcome routing contracts. No SwiftData, DoseLoop, or StoreKit.
enum OnboardingWelcomeContractChecks {
    static func failures() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let firstTime = OnboardingWelcomeRouting.Input(
            hasChosenLanguage: true,
            hasAcknowledgedPrivacy: true,
            hasCompletedSignInThisInstall: true,
            isSessionUnlocked: true,
            hasSeenWelcome: false,
            hasCompletedOnboarding: false,
            isReturningAuthenticated: false,
            needsIdentityProfile: true,
            userDataSettled: true
        )
        expect(
            OnboardingWelcomeRouting.hostPhase(firstTime) == .welcome,
            "O0: first-time signed-in user reaches Welcome"
        )
        expect(
            OnboardingWelcomeRouting.shouldPresentWelcome(firstTime),
            "O0: Welcome is presented for first-time identity"
        )

        expect(
            OnboardingWelcomeRouting.consumeWelcomeAdvance(alreadyFinished: false),
            "O0: first Skip/Continue is accepted"
        )
        expect(
            !OnboardingWelcomeRouting.consumeWelcomeAdvance(alreadyFinished: true),
            "O0: second Skip/Continue is ignored"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true) == .profile,
            "O0: Continue/Skip go to Personal Profile when identity is incomplete"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true)
                == OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true),
            "O0: Skip and Continue share the same destination"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: false) == .addMedication,
            "O0: Continue/Skip go to existing prescription host when identity is complete"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true) != .welcome
                && OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true) != .home
                && OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true) != .restoring,
            "O0: Welcome never jumps to Home, restoring, or back into Welcome"
        )

        var returning = firstTime
        returning.isReturningAuthenticated = true
        returning.hasCompletedOnboarding = true
        returning.hasSeenWelcome = false
        expect(
            OnboardingWelcomeRouting.hostPhase(returning) == .home,
            "O0: returning authenticated user does not replay Welcome"
        )
        expect(
            !OnboardingWelcomeRouting.shouldPresentWelcome(returning),
            "O0: returning identity skips Welcome"
        )

        var sameIdentity = firstTime
        sameIdentity.isReturningAuthenticated = true
        sameIdentity.hasCompletedOnboarding = true
        sameIdentity.hasSeenWelcome = true
        expect(
            OnboardingWelcomeRouting.hostPhase(sameIdentity) == .home,
            "O0: same authenticated identity resumes past Welcome"
        )

        var interrupted = firstTime
        interrupted.hasSeenWelcome = false
        expect(
            OnboardingWelcomeRouting.hostPhase(interrupted) == .welcome,
            "O0: interrupted Welcome resumes on Welcome"
        )

        var loading = firstTime
        loading.userDataSettled = false
        expect(
            OnboardingWelcomeRouting.hostPhase(loading) == .restoring,
            "O0: unsettled/empty store is not a new-user Welcome"
        )

        var unsigned = firstTime
        unsigned.isSessionUnlocked = false
        unsigned.hasCompletedSignInThisInstall = false
        expect(
            OnboardingWelcomeRouting.hostPhase(unsigned) == .signIn,
            "O0: no guest route — unsigned users stay on Sign-in"
        )

        var guestAttempt = firstTime
        guestAttempt.allowsGuest = true
        expect(
            OnboardingWelcomeRouting.hostPhase(guestAttempt) == .signIn,
            "O0: guest flag cannot open a guest destination"
        )

        expect(
            OnboardingWelcomeRouting.hostPhase(
                OnboardingWelcomeRouting.Input(
                    hasChosenLanguage: true,
                    hasAcknowledgedPrivacy: false,
                    hasCompletedSignInThisInstall: false
                )
            ) == .privacy,
            "O0: pre-auth order is language → privacy (Welcome is after Sign-in)"
        )

        expect(
            OnboardingWelcomeRouting.afterWelcome(needsIdentityProfile: true) != .welcome,
            "O0: finishing Welcome does not re-enter Welcome"
        )

        for locale in AppLocale.allCases {
            let title = L10n.string(.welcomeCooperTitle, locale: locale)
            expect(!title.isEmpty && !title.contains("%"), "O0: Welcome title localized for \(locale.rawValue)")
            expect(L10n.onboardingFlowBeats(locale).count == 3, "O0: Welcome uses three beats for \(locale.rawValue)")
        }

        return failures
    }
}
#endif
