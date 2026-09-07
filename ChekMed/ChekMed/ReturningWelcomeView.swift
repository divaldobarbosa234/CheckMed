import AVFoundation
import SwiftUI
import UIKit

/// After a returning sign-in: Phil missed them, then Progress or add a prescription.
struct ReturningWelcomeFlow: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var addingPrescription = false
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var showHeadline = false
    @State private var showBody = false

    var body: some View {
        Group {
            if addingPrescription {
                if session.needsUnfinishedPlan(treatments: treatments) {
                    UnfinishedPlanPromptView(kind: .beforeAdd)
                        .transition(.opacity)
                } else {
                    AddPrescriptionIntakeHost(
                        onFinished: { session.finishReturningWelcome(select: .treatments) },
                        onCancel: { addingPrescription = false }
                    )
                    .transition(.opacity)
                }
            } else {
                missYou
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: addingPrescription)
        .environment(\.locale, session.locale.foundationLocale)
    }

    private var missYou: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            sadMedia
                .frame(maxWidth: 260, maxHeight: 260)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(session.t(.missYouHeadline))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CheckMedTheme.ink)
                    .opacity(showHeadline ? 1 : 0)
                    .offset(y: showHeadline ? 0 : 12)
                Text(session.t(.missYouBody))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                    .opacity(showBody ? 1 : 0)
                    .offset(y: showBody ? 0 : 10)
            }
            .padding(.horizontal, 8)
            .padding(.top, 20)
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                CheckMedButton(title: session.t(.myProgress)) {
                    session.finishReturningWelcome(select: .progress)
                }
                CheckMedButton(title: session.t(.scanAddTitle), style: .secondary) {
                    addingPrescription = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.philSadCanvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.t(.missYouHeadline)) \(session.t(.missYouBody))")
        .onAppear {
            startPlayback()
            playText()
        }
        .onDisappear { stopPlayback() }
    }

    @ViewBuilder
    private var sadMedia: some View {
        if let player {
            PhilSadPlayerLayer(player: player)
        } else if Bundle.main.url(forResource: "phil_sad", withExtension: "mp4") == nil {
            PhilView(size: 168, mood: .sad, smiling: false)
        } else {
            CheckMedTheme.philSadCanvas
        }
    }

    private func playText() {
        showHeadline = false
        showBody = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.spring(duration: 0.7, bounce: 0.18)) {
                showHeadline = true
            }
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            withAnimation(.spring(duration: 0.7, bounce: 0.16)) {
                showBody = true
            }
        }
    }

    private func startPlayback() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "phil_sad", withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak avPlayer] _ in
            avPlayer?.seek(to: .zero) { _ in
                avPlayer?.play()
            }
        }
        player = avPlayer
        avPlayer.play()
    }

    private func stopPlayback() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

private struct PhilSadPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = CheckMedTheme.philSadCanvasUIColor
        view.playerLayer.backgroundColor = CheckMedTheme.philSadCanvasUIColor.cgColor
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
        if player.timeControlStatus != .playing {
            player.play()
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
