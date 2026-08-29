import SwiftUI

struct SplashView: View {
    @Environment(SessionStore.self) private var session
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            PhilView(size: 180, mood: .celebrate)
            Text("CHECKMED")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(1)
            Text(session.t(.splashTagline))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
            Spacer()
            CheckMedButton(title: session.t(.splashOpen), action: onOpen)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            onOpen()
        }
        .accessibilityLabel("Splash")
    }
}
