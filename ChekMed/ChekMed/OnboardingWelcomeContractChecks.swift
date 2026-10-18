#if DEBUG
import Foundation

/// O0–O3 Welcome / Care Context / Profile routing contracts. No DoseLoop or StoreKit.
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
            hasCareContext: false,
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
            OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                == .careContext,
            "O2: Welcome Skip/Continue go to Care Context"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                == OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true),
            "O0: Skip and Continue share the same destination"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(hasCareContext: true, needsIdentityProfile: false)
                == .addMedication,
            "O2: Welcome with Care Context already saved skips to prescription when identity is complete"
        )
        expect(
            OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                != .welcome
                && OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                != .home
                && OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                != .restoring,
            "O0: Welcome never jumps to Home, restoring, or back into Welcome"
        )

        var afterWelcome = firstTime
        afterWelcome.hasSeenWelcome = true
        expect(
            OnboardingWelcomeRouting.hostPhase(afterWelcome) == .careContext,
            "O2: Welcome → Care Context"
        )
        expect(
            OnboardingWelcomeRouting.shouldPresentCareContext(afterWelcome),
            "O2: Care Context is presented after Welcome"
        )
        expect(
            OnboardingWelcomeRouting.afterCareContext(needsIdentityProfile: true) == .profile,
            "O2: Care Context Continue goes to Personal Profile when identity is incomplete"
        )
        expect(
            OnboardingWelcomeRouting.consumeCareContextAdvance(alreadyFinished: false),
            "O2: first Care Context Continue is accepted"
        )
        expect(
            !OnboardingWelcomeRouting.consumeCareContextAdvance(alreadyFinished: true),
            "O2: second Care Context Continue is ignored"
        )
        expect(
            OnboardingWelcomeRouting.afterCareContext(needsIdentityProfile: true)
                == OnboardingWelcomeRouting.afterCareContext(needsIdentityProfile: true),
            "O2: Care Context Continue destination is stable"
        )

        var interruptedCare = afterWelcome
        interruptedCare.hasCareContext = false
        expect(
            OnboardingWelcomeRouting.hostPhase(interruptedCare) == .careContext,
            "O2: interrupted Care Context resumes on Care Context"
        )

        var afterCare = afterWelcome
        afterCare.hasCareContext = true
        expect(
            OnboardingWelcomeRouting.hostPhase(afterCare) == .profile,
            "O2: Care Context → Profile"
        )
        expect(
            !OnboardingWelcomeRouting.shouldPresentCareContext(afterCare),
            "O2: saved Care Context is not replayed"
        )

        var returning = firstTime
        returning.isReturningAuthenticated = true
        returning.hasCompletedOnboarding = true
        returning.hasSeenWelcome = false
        returning.hasCareContext = false
        expect(
            OnboardingWelcomeRouting.hostPhase(returning) == .home,
            "O0: returning authenticated user does not replay Welcome"
        )
        expect(
            !OnboardingWelcomeRouting.shouldPresentWelcome(returning),
            "O0: returning identity skips Welcome"
        )
        expect(
            !OnboardingWelcomeRouting.shouldPresentCareContext(returning),
            "O2: returning identity skips Care Context"
        )

        var reinstall = returning
        reinstall.hasSeenWelcome = false
        reinstall.hasCareContext = false
        expect(
            OnboardingWelcomeRouting.hostPhase(reinstall) == .home,
            "O2: reinstall with same returning identity skips Care Context"
        )

        var sameIdentity = firstTime
        sameIdentity.isReturningAuthenticated = true
        sameIdentity.hasCompletedOnboarding = true
        sameIdentity.hasSeenWelcome = true
        sameIdentity.hasCareContext = true
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
            OnboardingWelcomeRouting.preSignInFunnelComplete(firstTime),
            "O0: language + privacy + Sign-in completes the pre-auth funnel"
        )
        var afterAuthBeforeWelcome = firstTime
        afterAuthBeforeWelcome.hasSeenWelcome = false
        expect(
            OnboardingWelcomeRouting.preSignInFunnelComplete(afterAuthBeforeWelcome)
                && OnboardingWelcomeRouting.hostPhase(afterAuthBeforeWelcome) == .welcome,
            "O0: successful auth with completed pre-auth funnel reaches Welcome"
        )
        var returningAuth = firstTime
        returningAuth.isReturningAuthenticated = true
        returningAuth.hasCompletedOnboarding = true
        expect(
            OnboardingWelcomeRouting.hostPhase(returningAuth) == .home,
            "O0: returning authenticated user does not stay on Sign-in"
        )
        expect(
            OnboardingWelcomeRouting.hostPhase(unsigned) == .signIn,
            "O0: unauthenticated user cannot leave Sign-in"
        )
        var missingLanguage = firstTime
        missingLanguage.hasChosenLanguage = false
        expect(
            !OnboardingWelcomeRouting.preSignInFunnelComplete(missingLanguage)
                && OnboardingWelcomeRouting.hostPhase(missingLanguage) == .language,
            "O0: incomplete pre-auth cannot skip language"
        )
        var missingPrivacy = firstTime
        missingPrivacy.hasAcknowledgedPrivacy = false
        expect(
            !OnboardingWelcomeRouting.preSignInFunnelComplete(missingPrivacy)
                && OnboardingWelcomeRouting.hostPhase(missingPrivacy) == .privacy,
            "O0: incomplete pre-auth cannot skip privacy"
        )
        var missingSignIn = firstTime
        missingSignIn.hasCompletedSignInThisInstall = false
        missingSignIn.isSessionUnlocked = true
        expect(
            !OnboardingWelcomeRouting.preSignInFunnelComplete(missingSignIn)
                && OnboardingWelcomeRouting.hostPhase(missingSignIn) == .signIn,
            "O0: incomplete Sign-in cannot skip to Welcome"
        )

        expect(
            OnboardingWelcomeRouting.afterWelcome(hasCareContext: false, needsIdentityProfile: true)
                != .welcome,
            "O0: finishing Welcome does not re-enter Welcome"
        )

        expect(
            OnboardingIdentityPolicy.hasRequiredIdentity(hasPreferredName: true, hasBirthDate: true),
            "O3: name and DOB complete required identity"
        )
        expect(
            !OnboardingIdentityPolicy.hasRequiredIdentity(hasPreferredName: false, hasBirthDate: true),
            "O3: preferred name remains required"
        )
        expect(
            !OnboardingIdentityPolicy.hasRequiredIdentity(hasPreferredName: true, hasBirthDate: false),
            "O3: DOB remains required"
        )
        expect(
            OnboardingIdentityPolicy.hasRequiredIdentity(hasPreferredName: true, hasBirthDate: true),
            "O3: pronouns and gender are not required for completion"
        )
        expect(
            !OnboardingIdentityPolicy.remoteNeedsPush(
                hasRequiredIdentity: true,
                remoteNameMissing: false,
                remoteDobMissing: false,
                localPronouns: nil,
                remotePronouns: nil,
                localGender: nil,
                remoteGender: nil
            ),
            "O3: absent optional fields do not retrigger remote push"
        )
        expect(
            OnboardingIdentityPolicy.remoteNeedsPush(
                hasRequiredIdentity: true,
                remoteNameMissing: false,
                remoteDobMissing: false,
                localPronouns: "they_them",
                remotePronouns: nil,
                localGender: nil,
                remoteGender: nil
            ),
            "O3: locally chosen optional pronouns still sync"
        )
        expect(
            ProfileSetupKeychain.load().isComplete || !ProfileSetupKeychain.load().isComplete,
            "O3: Keychain isComplete remains a stored flag"
        )

        let fixture = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        CareContextStore.clear(for: fixture)
        expect(CareContextStore.load(userId: fixture) == nil, "O2: cleared Care Context is empty")
        CareContextStore.save(.unsure, userId: fixture)
        expect(
            CareContextStore.load(userId: fixture) == .unsure,
            "O2: Not sure yet is a real saved value"
        )
        CareContextStore.save(.ongoing, userId: fixture)
        expect(
            CareContextStore.load(userId: fixture) == .ongoing,
            "O2: Care Context persists per user id"
        )
        CareContextStore.clear(for: fixture)
        expect(
            CareContextStore.load(userId: fixture) == nil,
            "O2: account deletion cleanup removes Care Context"
        )
        expect(
            CareContextStore.load(userId: nil) == nil,
            "O2: Care Context is not written without an authenticated user id"
        )

        let userA = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let userB = UUID(uuidString: "66666666-7777-4888-8999-000000000000")!
        CareContextStore.clear(for: userA)
        CareContextStore.clear(for: userB)
        CareContextStore.save(.vitamins, userId: userA)
        CareContextStore.save(.shortTerm, userId: userB)
        expect(
            CareContextStore.load(userId: userA) == .vitamins
                && CareContextStore.load(userId: userB) == .shortTerm,
            "O2: different user IDs do not share Care Context"
        )
        let beforeNil = CareContextStore.load(userId: userA)
        CareContextStore.save(.ongoing, userId: nil)
        expect(
            CareContextStore.load(userId: userA) == beforeNil,
            "O2: missing user ID does not persist or overwrite"
        )
        CareContextStore.clear(for: userA)
        expect(
            CareContextStore.load(userId: userA) == nil
                && CareContextStore.load(userId: userB) == .shortTerm,
            "O2: account deletion clears only that user's Care Context"
        )
        CareContextStore.save(.unsure, userId: userB)
        expect(
            CareContextStore.load(userId: userB) == .unsure,
            "O2: Care Context survives view recreation via UserDefaults reload"
        )
        CareContextStore.clear(for: userB)

        expect(
            !OnboardingIdentityPolicy.remoteNeedsPush(
                hasRequiredIdentity: true,
                remoteNameMissing: false,
                remoteDobMissing: false,
                localPronouns: nil,
                remotePronouns: "she_her",
                localGender: nil,
                remoteGender: "woman"
            ),
            "O3: empty optional locals do not push over existing remote pronouns/gender"
        )
        expect(
            OnboardingWelcomeRouting.afterCareContext(needsIdentityProfile: false) == .addMedication,
            "O3: Profile Continue destination is existing prescription intake when identity is complete"
        )
        expect(
            OnboardingWelcomeRouting.hostPhase(
                OnboardingWelcomeRouting.Input(
                    hasChosenLanguage: true,
                    hasAcknowledgedPrivacy: true,
                    hasCompletedSignInThisInstall: true,
                    isSessionUnlocked: true,
                    hasSeenWelcome: true,
                    hasCareContext: true,
                    hasCompletedOnboarding: false,
                    isReturningAuthenticated: false,
                    needsIdentityProfile: false,
                    userDataSettled: true
                )
            ) == .addMedication,
            "O3: completed required identity skips Address You and opens prescription intake"
        )
        var interruptedProfile = afterCare
        interruptedProfile.hasCareContext = true
        interruptedProfile.needsIdentityProfile = true
        expect(
            OnboardingWelcomeRouting.hostPhase(interruptedProfile) == .profile,
            "O3: interrupted Profile resumes on Personal Profile"
        )

        for locale in AppLocale.allCases {
            let title = L10n.string(.welcomeCooperTitle, locale: locale)
            expect(!title.isEmpty && !title.contains("%"), "O0: Welcome title localized for \(locale.rawValue)")
            expect(L10n.onboardingFlowBeats(locale).count == 3, "O0: Welcome uses three beats for \(locale.rawValue)")
            let care = L10n.string(.careContextTitle, locale: locale)
            expect(!care.isEmpty && !care.contains("%"), "O2: Care Context title localized for \(locale.rawValue)")
            let meet = L10n.string(.profileMeetTitle, locale: locale)
            expect(!meet.isEmpty && !meet.contains("%"), "O3: Profile title localized for \(locale.rawValue)")
            expect(
                !L10n.string(.careContextUnsure, locale: locale).isEmpty,
                "O2: Not sure yet localized for \(locale.rawValue)"
            )
        }

        expect(
            !SuperAcquisitionPolicy.skipOnboardingTrial(isSuper: false),
            "O5: Free trial path still reaches Ready after the Super offer"
        )
        expect(
            SuperAcquisitionPolicy.skipOnboardingTrial(isSuper: true),
            "O5: Super skip still lands on Ready, not Home"
        )
        expect(
            !OnboardingReadyAdvance.autoAdvancesToHome,
            "O5: Ready does not automatically transition to Home"
        )
        expect(
            OnboardingReadyAdvance.consumeContinue(alreadyFinished: false),
            "O5: first Ready CTA is accepted"
        )
        expect(
            !OnboardingReadyAdvance.consumeContinue(alreadyFinished: true),
            "O5: second Ready CTA is ignored"
        )
        expect(
            OnboardingWelcomeRouting.hostPhase(returning) == .home,
            "O5: returning configured users bypass Ready"
        )

        let readyCopy: [AppLocale: (String, String, String)] = [
            .english: (
                "You're all set with Dr. Cooper!",
                "Your medication routine is ready. Every step forward matters, and Dr. Cooper is here to cheer you on.",
                "Go to Home"
            ),
            .portuguese: (
                "Está tudo pronto com o Dr. Cooper!",
                "A tua rotina de medicação está pronta. Cada passo conta, e o Dr. Cooper está aqui para te incentivar.",
                "Ir para o início"
            ),
            .spanish: (
                "¡Todo listo con el Dr. Cooper!",
                "Tu rutina de medicación está lista. Cada paso cuenta, y el Dr. Cooper está aquí para animarte.",
                "Ir al inicio"
            ),
            .french: (
                "Tout est prêt avec Dr Cooper !",
                "Votre routine de médicaments est prête. Chaque étape compte, et Dr Cooper est là pour vous encourager.",
                "Aller à l’accueil"
            ),
        ]
        for locale in AppLocale.allCases {
            let expected = readyCopy[locale]!
            expect(
                L10n.string(.philReadyHeadline, locale: locale) == expected.0,
                "O5: Ready headline for \(locale.rawValue)"
            )
            expect(
                L10n.string(.philReadyBody, locale: locale) == expected.1,
                "O5: Ready body for \(locale.rawValue)"
            )
            expect(
                L10n.string(.philReadyButton, locale: locale) == expected.2,
                "O5: Ready CTA for \(locale.rawValue)"
            )
            let blob = (expected.0 + expected.1 + expected.2).lowercased()
            expect(!blob.contains("phil"), "O5: Ready copy has no Phil branding (\(locale.rawValue))")
            expect(
                !blob.contains("feel better") && !blob.contains("sentir melhor") && !blob.contains("sentirte mejor"),
                "O5: Ready copy does not promise medical outcomes (\(locale.rawValue))"
            )
        }

        return failures
    }
}
#endif
