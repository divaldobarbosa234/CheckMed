import SwiftUI
import UIKit

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var allowsGuest = false
    var onAuthenticated: (() -> Void)? = nil
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mode: Mode = .login
    @State private var showAppleComingSoon = false
    @State private var toast: Banner?
    @State private var toastTask: Task<Void, Never>?
    @State private var readyForBanners = false

    private enum Mode {
        case login, signUp, reset
    }

    private struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                host

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.t(.signInHeadline))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                    Text(allowsGuest ? session.t(.signInBody) : session.t(.signInBodyOnboarding))
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    field(
                        session.t(.email),
                        text: $email,
                        contentType: .emailAddress,
                        keyboard: .emailAddress,
                        secure: false,
                        identifier: "auth-email"
                    )
                    if mode != .reset {
                        field(
                            session.t(.password),
                            text: $password,
                            contentType: mode == .signUp ? .newPassword : .password,
                            keyboard: .default,
                            secure: true,
                            identifier: "auth-password"
                        )
                    }
                    if mode == .signUp {
                        field(
                            session.t(.confirmPassword),
                            text: $confirmPassword,
                            contentType: .newPassword,
                            keyboard: .default,
                            secure: true,
                            identifier: "auth-confirm-password"
                        )
                    }
                    CheckMedButton(title: primaryTitle, action: submit)
                        .disabled(session.isLoading)
                        .accessibilityIdentifier("auth-submit")
                }

                HStack {
                    Button(secondaryTitle) { toggleMode() }
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .accessibilityIdentifier("auth-toggle-mode")
                        .keyboardShortcut("u", modifiers: [.command])
                    Spacer()
                    if mode != .reset {
                        Button(session.t(.forgotPassword)) { mode = .reset }
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                    }
                }
                .foregroundStyle(CheckMedTheme.ink)

                orEmailDivider
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                VStack(spacing: 12) {
                    provider(.google, title: session.t(.continueWithGoogle), identifier: "auth-google") {
                        session.requestProvider(.google)
                    }
                    .keyboardShortcut("g", modifiers: [.command])
                    provider(.facebook, title: session.t(.continueWithFacebook)) {
                        session.requestProvider(.facebook)
                    }
                    provider(.apple, title: session.t(.continueWithApple)) {
                        session.requestProvider(.apple)
                        showAppleComingSoon = true
                    }
                }

                VStack(spacing: 10) {
                    if allowsGuest {
                        CheckMedButton(title: session.t(.continueAsGuest), style: .ghost) {
                            session.continueAsGuest()
                            dismiss()
                        }
                    }
                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.signIn))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(CheckMedTheme.background, for: .navigationBar)
        .animation(.spring(duration: 0.35), value: toast?.text)
        .disabled(session.isLoading)
        .overlay(alignment: .top) { toastBanner }
        .overlay {
            if session.isLoading {
                ProgressView()
                    .tint(CheckMedTheme.primaryShadow)
                    .scaleEffect(1.15)
                    .padding(18)
                    .background(CheckMedTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: CheckMedTheme.ink.opacity(0.12), radius: 12, y: 4)
            }
        }
        .alert(session.t(.appleTitle), isPresented: $showAppleComingSoon) {
            Button(session.t(.ok), role: .cancel) {}
        } message: {
            Text(session.t(.appleComingSoon))
        }
        .onChange(of: session.kind) { _, kind in
            guard kind == .authenticated else { return }
            if let onAuthenticated {
                onAuthenticated()
            } else {
                dismiss()
            }
        }
        .onChange(of: session.auth.errorMessage) { _, message in
            guard readyForBanners, let message, !message.isEmpty else { return }
            showBanner(message, isError: true)
        }
        .onChange(of: session.auth.statusMessage) { _, note in
            guard readyForBanners, let note, !note.isEmpty else { return }
            showBanner(note, isError: false)
        }
        .onAppear {
            session.auth.clearMessages()
            toast = nil
            readyForBanners = true
            applyDebugLaunchHooks()
        }
        .onDisappear {
            toastTask?.cancel()
            readyForBanners = false
        }
    }

    private var host: some View {
        HStack(alignment: .center, spacing: 14) {
            PhilView(size: 100)
            VStack(alignment: .leading, spacing: 8) {
                Text("CHECKMED")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(CheckMedTheme.primaryShadow)
                SpeechBubbleView(text: bubbleText)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast.text)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(toast.isError ? Color.white : CheckMedTheme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    toast.isError ? CheckMedTheme.danger : CheckMedTheme.guestBg,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(toast.isError ? Color.clear : CheckMedTheme.guestBorder, lineWidth: 2)
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var orEmailDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(CheckMedTheme.locked)
                .frame(height: 1)
            Text(session.t(.orEmail))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
                .textCase(.uppercase)
            Rectangle()
                .fill(CheckMedTheme.locked)
                .frame(height: 1)
        }
    }

    private var bubbleText: String {
        switch mode {
        case .login: session.t(.signInBubbleLogin)
        case .signUp: session.t(.signInBubbleSignUp)
        case .reset: session.t(.signInBubbleReset)
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .login: session.t(.logIn)
        case .signUp: session.t(.createAccount)
        case .reset: session.t(.sendResetLink)
        }
    }

    private var secondaryTitle: String {
        switch mode {
        case .login: session.t(.needAccountSignUp)
        case .signUp, .reset: session.t(.alreadyHaveAccount)
        }
    }

    private func applyDebugLaunchHooks() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["CHECKMED_UI_EMAIL"], !value.isEmpty {
            email = value
        }
        if let value = env["CHECKMED_UI_PASSWORD"], !value.isEmpty {
            password = value
            confirmPassword = value
        }
        if env["CHECKMED_UI_SIGNUP"] == "1" {
            mode = .signUp
        }
        if env["CHECKMED_UI_GOOGLE"] == "1" {
            session.requestProvider(.google)
        }
        #endif
    }

    private func toggleMode() {
        session.auth.clearMessages()
        toast = nil
        mode = mode == .login ? .signUp : .login
        confirmPassword = ""
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            session.auth.presentError(session.t(.philNeedsEmail))
            return
        }
        switch mode {
        case .login:
            guard !password.isEmpty else {
                session.auth.presentError(session.t(.enterYourPassword))
                return
            }
            Task { await session.signIn(email: trimmedEmail, password: password) }
        case .signUp:
            guard password.count >= 6 else {
                session.auth.presentError(session.t(.passwordTooShort))
                return
            }
            guard password == confirmPassword else {
                session.auth.presentError(session.t(.passwordsMustMatch))
                return
            }
            Task { await session.signUp(email: trimmedEmail, password: password) }
        case .reset:
            Task { await session.resetPassword(email: trimmedEmail) }
        }
    }

    private func showBanner(_ text: String, isError: Bool) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35)) {
            toast = Banner(text: text, isError: isError)
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                toast = nil
            }
            session.auth.clearMessages()
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        secure: Bool,
        identifier: String
    ) -> some View {
        Group {
            if secure {
                SecureField(title, text: text)
                    .textContentType(contentType)
            } else {
                TextField(title, text: text)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.locked, lineWidth: 2))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }

    private enum ProviderKind {
        case apple, google, facebook
    }

    private func provider(_ kind: ProviderKind, title: String, identifier: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                providerMark(kind)
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .foregroundStyle(kind == .apple ? Color.white : CheckMedTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(kind == .apple ? Color.black : CheckMedTheme.surface, in: Capsule())
            .overlay(
                Capsule().stroke(
                    kind == .apple ? Color.clear : CheckMedTheme.ink.opacity(0.18),
                    lineWidth: 2
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func providerMark(_ kind: ProviderKind) -> some View {
        switch kind {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 16, weight: .semibold))
        case .google:
            Text("G")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(CheckMedTheme.google)
        case .facebook:
            Text("f")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(CheckMedTheme.facebook)
        }
    }
}
