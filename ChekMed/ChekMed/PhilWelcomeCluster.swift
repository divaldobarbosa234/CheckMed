import SwiftUI

/// Overlapping circular Phil stills on the sign-in landing. No speech bubble.
struct PhilWelcomeCluster: View {
    var compact = false

    /// Three frames (not five) — each onboarding PNG is ~1MB compressed / ~4MB decoded; five at once spiked memory on sign-in.
    private let frames = [
        "phil_onboarding_02_photo",
        "phil_onboarding_01_intro",
        "phil_onboarding_05_healthy",
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let large = compact ? min(w, h) * 0.34 : min(w, h) * 0.48
            let mid = large * (compact ? 0.86 : 0.78)

            ZStack {
                phil(frames[0], size: mid)
                    .offset(x: compact ? -w * 0.22 : -w * 0.28, y: compact ? -h * 0.10 : -h * 0.16)
                phil(frames[2], size: mid)
                    .offset(x: compact ? w * 0.22 : w * 0.28, y: compact ? -h * 0.06 : -h * 0.10)
                phil(frames[1], size: large)
                    .offset(x: compact ? -w * 0.02 : 0, y: compact ? h * 0.06 : h * 0.14)
            }
            .frame(width: w, height: h)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cooper")
    }

    private func phil(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
