import SwiftUI

struct SplashView: View {
    var seconds: Double = 3
    var onFinished: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            CheckMedTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    CheckMedTheme.belly.opacity(0.95),
                    CheckMedTheme.primary.opacity(0.14),
                    CheckMedTheme.background,
                ],
                center: .center,
                startRadius: 24,
                endRadius: 420
            )
            .ignoresSafeArea()

            PhilView(size: 228, mood: .celebrate)
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.72, bounce: 0.32)) {
                appeared = true
            }
        }
        .task {
            let nanos = UInt64(max(0.4, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .accessibilityLabel("Phil")
        .accessibilityAddTraits(.isImage)
    }
}
