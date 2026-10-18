import AVFoundation
import SwiftUI
import UIKit

/// Branded intro only. Never a blank yellow fill — that was the stuck launch screen.
/// The video plays once and holds. Language / How it works must not crossfade through this screen.
struct SplashView: View {
    @Environment(SessionStore.self) private var session
    var onFinished: () -> Void

    @State private var didFinish = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            CheckMedTheme.primary.ignoresSafeArea()
            PhilView(size: 228, mood: .celebrate)
            splashVideo
                .allowsHitTesting(false)
            VStack {
                Spacer()
                Text(session.t(.splashTagline))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.onPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .shadow(color: CheckMedTheme.primary.opacity(0.8), radius: 8)
                CheckMedButton(title: session.t(.splashOpen), action: finishIfNeeded)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .padding(.top, 12)
            }
        }
        .onAppear { startPlayback() }
        .onDisappear { stopPlayback() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item == player?.currentItem else { return }
            player?.pause()
        }
        .accessibilityLabel("Cooper")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var splashVideo: some View {
        if let player {
            SplashPlayerLayer(player: player)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    private func startPlayback() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "SplashPhil", withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .pause
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        avPlayer.audiovisualBackgroundPlaybackPolicy = .pauses
        player = avPlayer
        avPlayer.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        stopPlayback()
        onFinished()
    }
}

private struct SplashPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = UIColor(red: 69 / 255, green: 185 / 255, blue: 79 / 255, alpha: 1)
        view.isOpaque = true
        view.playerLayer.player = player
        view.playerLayer.backgroundColor = UIColor(red: 69 / 255, green: 185 / 255, blue: 79 / 255, alpha: 1).cgColor
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.isUserInteractionEnabled = false
        let ended = player.currentItem.map { $0.currentTime() >= $0.duration && $0.duration.isNumeric } ?? false
        if player.timeControlStatus != .playing, !ended {
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
