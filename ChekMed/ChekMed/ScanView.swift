import SwiftUI

struct ScanView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showGate = false
    @State private var showSignIn = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                Spacer()
                PhilView(size: 112)
                SpeechBubbleView(
                    text: session.canSync
                        ? "You are signed in. Photo and PDF import land next — I will read with you, you verify, then we organize."
                        : "You can look around. A prescription photo or PDF only syncs after you create an account."
                )
                Text("Scan hub")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                Text("Camera on iPhone. Extract → verify → organize comes after auth. I never recommend a medicine or a dose.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                CheckMedButton(title: "Take a photo") { requestCloudScan() }
                CheckMedButton(title: "Choose PDF", style: .secondary) { requestCloudScan() }
                CheckMedButton(title: "Back to today's path", style: .ghost) { dismiss() }
                SafetyCaption()
            }
            .padding(24)
            .background(CheckMedTheme.background)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProductRoute.self) { route in
                ProductRouteView(route: route, path: $path)
            }
            .overlay {
                if showGate {
                    AccountGateView(
                        onCreateAccount: {
                            showGate = false
                            showSignIn = true
                        },
                        onDismiss: { showGate = false }
                    )
                }
            }
            .sheet(isPresented: $showSignIn) {
                NavigationStack { SignInView() }
            }
        }
        .onChange(of: session.canSync) { _, canSync in
            if canSync { showGate = false }
        }
    }

    private func requestCloudScan() {
        if session.canSync {
            path.append(ProductRoute.review)
        } else {
            showGate = true
        }
    }
}
