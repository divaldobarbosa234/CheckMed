import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: FirstTimePhase = .splash
    @State private var addMethod: OnboardingAddMethod = .photo
    @State private var draft = OnboardingPrescriptionDraft.empty
    @State private var drafts = [OnboardingPrescriptionDraft.empty]
    @State private var pendingImport: PendingPrescriptionImport = .none
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var afterSplash: FirstTimePhase = .language
    @State private var didBootstrapPhase = false
    @State private var importToken = 0

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    session.markIntroSplashSeen()
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
                    SignInView(onAuthenticated: {})
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
                            drafts = [.empty]
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
                        drafts = [.empty]
                        advance(to: .analysing)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .manualEntry:
                OnboardingManualEntryView(
                    draft: $draft,
                    onContinue: {
                        drafts = [draft]
                        advance(to: .analysing)
                    },
                    onBack: { advance(to: .addMedication) }
                )
                .transition(insert)
            case .analysing:
                OnboardingAnalysingView(
                    isShort: addMethod == .manual,
                    work: runImport,
                    onFinished: { advance(to: .confirm) },
                    importToken: importToken
                )
                .transition(insert)
            case .confirm:
                OnboardingConfirmView(
                    drafts: $drafts,
                    isManual: addMethod == .manual,
                    onConfirm: {
                        treatments.seedFromDrafts(
                            Array(drafts.filter(\.hasMedicineName).prefix(
                                entitlements.isSuper ? drafts.count : SuperLimits.freePrescriptions
                            )),
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
                    drafts = [.empty]
                    photoItem = nil
                    advance(to: .analysing)
                }
            }
        }
        .prescriptionPDFImporter(isPresented: $showPDFImporter) { url in
            pendingImport = .pdf(url)
            draft = .empty
            drafts = [.empty]
            advance(to: .analysing)
        }
        .overlay {
            if session.isResolvingPostAuth {
                resolving
            }
        }
        .onAppear {
            bootstrapPhase()
            routeAfterAuthIfNeeded()
        }
        .task {
            bootstrapPhase()
        }
        .onChange(of: session.kind) { oldKind, kind in
            if oldKind == .authenticated, kind != .authenticated, phase != .splash {
                afterSplash = .language
                didBootstrapPhase = false
                advance(to: .splash, persist: false)
            } else if kind == .authenticated {
                didBootstrapPhase = false
                bootstrapPhase()
            }
        }
        .onChange(of: session.postAuthKind) { _, _ in
            routeAfterAuthIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            replayOnboardingIfUnsignedAfterLeaving(phase)
        }
    }

    private func replayOnboardingIfUnsignedAfterLeaving(_ phase: ScenePhase) {
        guard session.kind != .authenticated else { return }
        guard !session.auth.isRestoring, !session.isLoading else { return }
        if phase == .background {
            session.restartPreAuthOnboarding()
            afterSplash = .language
            didBootstrapPhase = false
        } else if phase == .active, !didBootstrapPhase {
            bootstrapPhase()
        }
    }

    private var resolving: some View {
        VStack(spacing: 16) {
            PhilReadingImage(size: 112)
            ProgressView()
                .tint(CheckMedTheme.flowDot)
            Text(session.t(.restoring))
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
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
        if next == .analysing {
            importToken += 1
        }
        withAnimation(.easeInOut(duration: 0.45)) {
            phase = next
        }
        if persist, next.persistable {
            session.setFirstTimePhaseRaw(next.rawValue)
        }
    }

    private func bootstrapPhase() {
        afterSplash = destinationAfterSplash()
        if session.kind == .authenticated, phase == .signIn || phase == .splash || phase == .language || phase == .howItWorks || phase == .privacy {
            didBootstrapPhase = false
        }
        guard !didBootstrapPhase else { return }
        if session.kind != .authenticated, !session.auth.isRestoring, !session.isLoading {
            session.restartPreAuthOnboarding()
            afterSplash = .language
        }
        didBootstrapPhase = true
        let skipIntro = session.kind == .authenticated
        if session.shouldPlayIntroSplash, !skipIntro {
            phase = .splash
        } else {
            session.markIntroSplashSeen()
            phase = afterSplash
        }
        routeAfterAuthIfNeeded()
    }

    private func destinationAfterSplash() -> FirstTimePhase {
        var saved = FirstTimePhase(rawValue: session.firstTimePhaseRaw) ?? .language
        if saved == .splash || saved == .analysing { saved = .language }
        if session.kind == .authenticated {
            if session.hasCompletedOnboarding {
                return session.needsIdentityProfile ? .profile : .ready
            }
            if !saved.requiresAuth || saved == .signIn {
                return session.needsIdentityProfile ? .profile : .addMedication
            }
            if saved == .profile, !session.needsIdentityProfile {
                return .addMedication
            }
            return saved
        }
        return .language
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
            if drafts.filter(\.hasMedicineName).isEmpty {
                drafts = [draft]
            }
        case .image(let data):
            let parsed = await PrescriptionReader.drafts(fromImageData: data)
            if parsed.contains(where: \.hasMedicineName) {
                drafts = parsed
                draft = parsed[0]
            }
        case .pdf(let url):
            let parsed = await PrescriptionReader.drafts(fromPDF: url)
            if parsed.contains(where: \.hasMedicineName) {
                drafts = parsed
                draft = parsed[0]
            }
        }
        if drafts.isEmpty {
            drafts = [.empty]
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
            PhilGlassesImage(size: 108)
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

    @State private var playback = HowItWorksPlayback()
    @State private var appeared = false

    private var beats: [L10n.FlowBeat] { L10n.onboardingFlowBeats(session.locale) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            mediaCentered
                .frame(maxWidth: 340)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { playback.advance(beatCount: beats.count) }
                .gesture(
                    DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.width < -20 { playback.advance(beatCount: beats.count) }
                        if value.translation.width > 20 { playback.retreat(beatCount: beats.count) }
                    }
                )
            Spacer(minLength: 8)
            VStack(spacing: 14) {
                captionText
                beatDots
                CheckMedButton(title: session.t(.letsGetStarted), action: onGetStarted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.philFlowCanvas.ignoresSafeArea())
        .accessibilityLabel(session.t(.howTitle))
        .onAppear {
            playEntrance()
            playback.start(beatCount: beats.count)
        }
        .onDisappear { playback.stop() }
        .onChange(of: playback.beat) { _, _ in playEntrance() }
        .task(id: playback.beat) {
            guard playback.player == nil else { return }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            playback.advance(beatCount: beats.count, seekVideo: false)
        }
    }

    @ViewBuilder
    private var mediaCentered: some View {
        Group {
            if let player = playback.player {
                OnboardingFlowPlayerLayer(player: player, rate: HowItWorksPlayback.playbackRate)
            } else if playback.hasBundledVideo {
                CheckMedTheme.philFlowCanvas
            } else if beats.indices.contains(playback.beat) {
                Image(beats[playback.beat].imageName)
                    .resizable()
                    .scaledToFit()
                    .id(playback.beat)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var captionText: some View {
        if beats.indices.contains(playback.beat) {
            Text(beats[playback.beat].caption)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(CheckMedTheme.onPrimary)
                .padding(.horizontal, 12)
                .id(playback.beat)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var beatDots: some View {
        HStack(spacing: 8) {
            ForEach(beats.indices, id: \.self) { index in
                Capsule()
                    .fill(index == playback.beat ? CheckMedTheme.flowDot : CheckMedTheme.flowDotIdle)
                    .frame(width: index == playback.beat ? 22 : 8, height: 8)
                    .animation(.spring(duration: 0.35), value: playback.beat)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 4)
    }

    private func playEntrance() {
        appeared = false
        withAnimation(.spring(duration: 0.55, bounce: 0.28)) {
            appeared = true
        }
    }
}

@MainActor
@Observable
private final class HowItWorksPlayback {
    /// Cropped clip length after last-frame hold (ffprobe).
    static let convertedDuration = 8.25
    static let playbackRate: Float = 0.58
    static let videoResource = "phil_onboarding_flow"

    var beat = 0
    var player: AVPlayer?
    var hasBundledVideo: Bool {
        Bundle.main.url(forResource: Self.videoResource, withExtension: "mp4") != nil
    }

    private var duration = HowItWorksPlayback.convertedDuration
    private var beatCount = 5
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var ignoringPlayerSync = false

    func start(beatCount: Int) {
        self.beatCount = max(1, beatCount)
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: Self.videoResource, withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        avPlayer.audiovisualBackgroundPlaybackPolicy = .pauses
        let interval = CMTime(seconds: 0.08, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                self?.syncBeat(to: seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero) { _ in
                    Task { @MainActor in
                        self?.playSlow()
                    }
                }
            }
        }
        player = avPlayer
        playSlow()
        Task { await loadDuration(from: url) }
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
    }

    func advance(beatCount: Int, seekVideo: Bool = true) {
        guard beat < beatCount - 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat += 1
        }
        if seekVideo { seekPlayer(toBeat: beat, beatCount: beatCount) }
    }

    func retreat(beatCount: Int) {
        guard beat > 0 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat -= 1
        }
        seekPlayer(toBeat: beat, beatCount: beatCount)
    }

    func playSlow() {
        player?.playImmediately(atRate: Self.playbackRate)
    }

    private func loadDuration(from url: URL) async {
        if let loaded = try? await AVURLAsset(url: url).load(.duration),
           loaded.seconds.isFinite,
           loaded.seconds > 0 {
            duration = loaded.seconds
        }
    }

    private func syncBeat(to seconds: Double) {
        guard !ignoringPlayerSync else { return }
        guard duration > 0, beatCount > 0 else { return }
        guard seconds.isFinite, seconds >= 0 else { return }
        let slice = duration / Double(beatCount)
        let index = min(beatCount - 1, max(0, Int(seconds / slice)))
        guard index != beat else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            beat = index
        }
    }

    private func seekPlayer(toBeat index: Int, beatCount: Int) {
        guard let player, duration > 0, beatCount > 0 else { return }
        ignoringPlayerSync = true
        let slice = duration / Double(beatCount)
        let seconds = slice * Double(index)
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.04, preferredTimescale: 600)
        ) { [weak self] _ in
            Task { @MainActor in
                self?.ignoringPlayerSync = false
                self?.playSlow()
            }
        }
    }
}

private struct OnboardingFlowPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    var rate: Float = HowItWorksPlayback.playbackRate

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = CheckMedTheme.philFlowCanvasUIColor
        view.playerLayer.backgroundColor = CheckMedTheme.philFlowCanvasUIColor.cgColor
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.backgroundColor = CheckMedTheme.philFlowCanvasUIColor
        uiView.playerLayer.backgroundColor = CheckMedTheme.philFlowCanvasUIColor.cgColor
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspect
        if player.timeControlStatus != .playing || abs(player.rate - rate) > 0.02 {
            player.playImmediately(atRate: rate)
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
