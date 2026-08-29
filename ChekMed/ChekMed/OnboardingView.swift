import PhotosUI
import SwiftUI

enum FirstTimePhase: String, Equatable {
    case splash
    case language
    case howItWorks
    case privacy
    case signIn
    case profile
    case addMedication
    case camera
    case manualEntry
    case analysing
    case confirm
    case organize
    case notifications
    case ready

    var requiresAuth: Bool {
        switch self {
        case .splash, .language, .howItWorks, .privacy, .signIn:
            false
        default:
            true
        }
    }

    var persistable: Bool { self != .splash && self != .analysing }
}

struct FirstTimeOnboardingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @Environment(TodayPathStore.self) private var path
    @Environment(EntitlementStore.self) private var entitlements

    @State private var phase: FirstTimePhase = .splash
    @State private var addMethod: OnboardingAddMethod = .photo
    @State private var draft = OnboardingPrescriptionDraft.empty
    @State private var pendingImport: PendingPrescriptionImport = .none
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var afterSplash: FirstTimePhase = .language

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    advance(to: afterSplash, persist: afterSplash.persistable)
                }
                .transition(.opacity)
            case .language:
                LanguageOnboardingView {
                    advance(to: .howItWorks)
                }
                .transition(insert)
            case .howItWorks:
                HowItWorksView(onGetStarted: { advance(to: .privacy) })
                    .transition(insert)
            case .privacy:
                PrivacyConsentView(onAccept: { advance(to: .signIn) })
                    .transition(insert)
            case .signIn:
                NavigationStack {
                    SignInView(allowsGuest: false, onAuthenticated: {})
                }
                .transition(insert)
            case .profile:
                AccountProfileSetupView(
                    showsSignOut: true,
                    onFinished: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .addMedication:
                OnboardingAddMedicationView(
                    onPhoto: {
                        startImport(.photo) { advance(to: .camera) }
                    },
                    onChoosePhotos: {
                        startImport(.photo) { showPhotosPicker = true }
                    },
                    onPDF: {
                        startImport(.pdf) { showPDFImporter = true }
                    },
                    onManual: {
                        startImport(.manual) {
                            draft = .empty
                            pendingImport = .none
                            advance(to: .manualEntry)
                        }
                    },
                    onBack: { advance(to: .profile) }
                )
                .transition(insert)
            case .camera:
                OnboardingCameraView(
                    onCaptured: { data in
                        pendingImport = .image(data)
                        draft = .empty
                        advance(to: .analysing)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .manualEntry:
                OnboardingManualEntryView(
                    draft: $draft,
                    onContinue: { advance(to: .analysing) },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .analysing:
                OnboardingAnalysingView(isShort: addMethod == .manual, work: runImport) {
                    advance(to: .confirm)
                }
                .transition(insert)
            case .confirm:
                OnboardingConfirmView(
                    draft: $draft,
                    isManual: addMethod == .manual,
                    onConfirm: {
                        treatments.seedFromDraft(
                            draft,
                            ownerId: session.auth.userId,
                            profileId: session.profileId
                        )
                        if addMethod == .photo || addMethod == .pdf {
                            ImportUsage.incrementPhotoPDF(ownerId: session.auth.userId)
                        }
                        path.reload()
                        advance(to: .organize)
                    },
                    onBack: { advance(to: addMethod == .manual ? .manualEntry : .addMedication) }
                )
                .transition(insert)
            case .organize:
                OnboardingOrganizeView(
                    onContinue: { advance(to: .notifications) },
                    onBack: { advance(to: .confirm) }
                )
                .transition(insert)
            case .notifications:
                NotificationsPermissionView(
                    secondaryTitle: session.t(.skip),
                    onEnable: { advance(to: .ready) },
                    onSecondary: { advance(to: .ready) },
                    onBack: { advance(to: .organize) }
                )
                .transition(insert)
            case .ready:
                OnboardingPhilReadyView {
                    session.markOnboardingComplete()
                }
                .transition(insert)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pendingImport = .image(PrescriptionReader.downsampledJPEG(from: data))
                    draft = .empty
                    photoItem = nil
                    advance(to: .analysing)
                }
            }
        }
        .prescriptionPDFImporter(isPresented: $showPDFImporter) { url in
            pendingImport = .pdf(url)
            draft = .empty
            advance(to: .analysing)
        }
        .overlay {
            if session.isResolvingPostAuth {
                resolving
            }
        }
        .onAppear {
            afterSplash = destinationAfterSplash()
            routeAfterAuthIfNeeded()
        }
        .onChange(of: session.kind) { _, kind in
            if kind != .authenticated, phase != .splash {
                afterSplash = .language
                advance(to: .splash, persist: false)
            }
        }
        .onChange(of: session.postAuthKind) { _, _ in
            routeAfterAuthIfNeeded()
        }
    }

    private var resolving: some View {
        VStack(spacing: 16) {
            PhilView(size: 120)
            ProgressView()
            Text(session.t(.restoring))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background.opacity(0.94))
    }

    private func routeAfterAuthIfNeeded() {
        guard session.kind == .authenticated else { return }
        guard session.postAuthKind == .newAccount else { return }
        guard phase == .signIn || phase == .splash else { return }
        let next: FirstTimePhase = session.needsIdentityProfile ? .profile : .addMedication
        advance(to: next)
    }

    private var insert: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity
        )
    }

    private func advance(to next: FirstTimePhase, persist: Bool = true) {
        withAnimation(.easeInOut(duration: 0.45)) {
            phase = next
        }
        if persist, next.persistable {
            session.setFirstTimePhaseRaw(next.rawValue)
        }
    }

    private func destinationAfterSplash() -> FirstTimePhase {
        var saved = FirstTimePhase(rawValue: session.firstTimePhaseRaw) ?? .language
        if saved == .splash || saved == .analysing { saved = .language }
        if session.kind != .authenticated, saved.requiresAuth {
            return .signIn
        }
        if session.kind == .authenticated {
            if !saved.requiresAuth || saved == .signIn {
                return session.needsIdentityProfile ? .profile : .addMedication
            }
            if saved == .profile, !session.needsIdentityProfile {
                return .addMedication
            }
        }
        return saved
    }

    private func startImport(_ next: OnboardingAddMethod, proceed: () -> Void) {
        guard entitlements.gatePrescriptionAdd(
            method: next,
            existingCount: treatments.activeTreatmentCount,
            photoPDFUsed: ImportUsage.photoPDFCount(ownerId: session.auth.userId)
        ) else { return }
        addMethod = next
        proceed()
    }

    private func runImport() async {
        switch pendingImport {
        case .none:
            break
        case .image(let data):
            draft = await PrescriptionReader.draft(fromImageData: data)
            pendingImport = .none
        case .pdf(let url):
            draft = await PrescriptionReader.draft(fromPDF: url)
            pendingImport = .none
        }
    }
}

struct LanguageOnboardingView: View {
    @Environment(SessionStore.self) private var session
    var onContinue: () -> Void

    @State private var locale: AppLocale = .english

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            PhilView(size: 128, mood: .idle, pose: .pointingDown, smiling: true)
            Text(session.t(.languageHeadline))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
            Text(session.t(.languageSubhead))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            LanguageWheelPicker(locale: $locale) { session.setLocale($0) }
            Spacer(minLength: 8)
            CheckMedButton(title: session.t(.continueButton)) {
                session.setLocale(locale)
                onContinue()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .onAppear { locale = session.locale }
        .accessibilityLabel(session.t(.language))
    }
}

struct HowItWorksView: View {
    @Environment(SessionStore.self) private var session
    var onGetStarted: () -> Void

    @State private var beat = 0
    @State private var appeared = false

    private var features: [L10n.HowFeature] { L10n.howFeatures(session.locale) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                PhilView(
                    size: 112,
                    mood: beat == features.count - 1 ? .celebrate : .idle,
                    pose: beat == 0 ? .pointingDown : .idle,
                    smiling: true
                )
                .padding(.top, 8)

                Text(session.t(.howHeadline))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CheckMedTheme.ink)

                if features.indices.contains(beat) {
                    beatCard(features[beat])
                        .id(beat)
                }

                HStack(spacing: 8) {
                    ForEach(features.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == beat ? CheckMedTheme.primary : CheckMedTheme.locked)
                            .frame(width: index == beat ? 22 : 8, height: 8)
                            .animation(.spring(duration: 0.35), value: beat)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { advanceBeat() }
            .gesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    if value.translation.width < -20 { advanceBeat() }
                    if value.translation.width > 20 { retreatBeat() }
                }
            )

            CheckMedButton(title: session.t(.letsGetStarted), action: onGetStarted)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .accessibilityLabel(session.t(.howTitle))
        .onAppear { playEntrance() }
        .onChange(of: beat) { _, _ in playEntrance() }
        .task(id: beat) {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            advanceBeat()
        }
    }

    private func beatCard(_ item: L10n.HowFeature) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(CheckMedTheme.belly)
                    .frame(width: 88, height: 88)
                Image(systemName: item.icon)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: beat)
                    .symbolEffect(.pulse, value: beat)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .scaleEffect(appeared ? 1 : 0.86)

            Text(item.short)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.ink)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Text(item.body)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .padding(.horizontal, 24)
    }

    private func playEntrance() {
        appeared = false
        withAnimation(.spring(duration: 0.55, bounce: 0.28)) {
            appeared = true
        }
    }

    private func advanceBeat() {
        guard beat < features.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat += 1
        }
    }

    private func retreatBeat() {
        guard beat > 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat -= 1
        }
    }
}
