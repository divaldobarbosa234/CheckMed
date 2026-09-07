import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    @Environment(SessionStore.self) private var session
    var seconds: Double = 3
    var onFinished: () -> Void

    @State private var didFinish = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            CheckMedTheme.primary.ignoresSafeArea()
            splashMedia
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
        .task {
            let nanos = UInt64(max(0.4, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            finishIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item == player?.currentItem else { return }
            finishIfNeeded()
        }
        .accessibilityLabel("Phil")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var splashMedia: some View {
        if let player {
            SplashPlayerLayer(player: player)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else if Bundle.main.url(forResource: "SplashPhil", withExtension: "mp4") == nil {
            PhilView(size: 228, mood: .celebrate)
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
        view.backgroundColor = UIColor(red: 251 / 255, green: 214 / 255, blue: 4 / 255, alpha: 1)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
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
