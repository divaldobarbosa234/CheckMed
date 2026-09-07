import SwiftUI

/// Five overlapping circular Phil stills on the sign-in landing. No speech bubble.
struct PhilWelcomeCluster: View {
    var compact = false

    private let frames = [
        "phil_onboarding_02_photo",
        "phil_onboarding_03_read",
        "phil_onboarding_01_intro",
        "phil_onboarding_04_plan",
        "phil_onboarding_05_healthy",
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let large = compact ? min(w, h) * 0.42 : min(w, h) * 0.48
            let mid = large * 0.78
            let small = large * 0.62

            ZStack {
                phil(frames[0], size: mid)
                    .offset(x: -w * 0.28, y: -h * 0.16)
                phil(frames[1], size: small)
                    .offset(x: w * 0.02, y: -h * 0.28)
                phil(frames[3], size: mid)
                    .offset(x: w * 0.28, y: -h * 0.10)
                phil(frames[2], size: large)
                    .offset(x: -w * 0.14, y: h * 0.18)
                phil(frames[4], size: large * 0.92)
                    .offset(x: w * 0.18, y: h * 0.20)
            }
            .frame(width: w, height: h)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phil")
    }

    private func phil(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
