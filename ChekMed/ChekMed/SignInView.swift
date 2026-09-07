import SwiftUI
import UIKit

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onAuthenticated: (() -> Void)? = nil
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mode: Mode = .login
    @State private var page: Page = .landing
    @State private var showPassword = false
    @State private var toast: Banner?
    @State private var toastTask: Task<Void, Never>?
    @State private var readyForBanners = false

    private enum Mode {
        case login, signUp, reset
    }

    private enum Page {
        case landing, form
    }

    private struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    var body: some View {
        ZStack {
            CheckMedTheme.philFlowCanvas.ignoresSafeArea()
            if page == .landing {
                landing
                    .transition(.opacity.combined(with: .offset(y: 12)))
            } else {
                form
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: page)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
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

    private var landing: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("checkmed")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(CheckMedTheme.ink)
                    .padding(.top, 12)
                PhilWelcomeCluster()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 16) {
                Text(session.t(.signInToGetStarted))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
                provider(.apple, title: session.t(.signInWithApple), identifier: "auth-apple") {
                    session.requestProvider(.apple)
                }
                provider(.google, title: session.t(.signInWithGoogle), identifier: "auth-google") {
                    session.requestProvider(.google)
                }
                Button(session.t(.continueWithEmail)) {
                    page = .form
                    mode = .login
                }
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.ink)
                .padding(.top, 4)
                .accessibilityIdentifier("auth-continue-email")
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
            .background(CheckMedTheme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PhilWelcomeCluster(compact: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 28)
                Button {
                    page = .landing
                    mode = .login
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CheckMedTheme.ink)
                        .padding(10)
                        .background(.white.opacity(0.7), in: Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                .accessibilityLabel(session.t(.back))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formTitle)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(formSubhead)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                    iconField(
                        session.t(.emailAddress),
                        text: $email,
                        systemImage: "envelope",
                        contentType: .emailAddress,
                        keyboard: .emailAddress,
                        secure: false,
                        identifier: "auth-email"
                    )
                    if mode != .reset {
                        iconField(
                            session.t(.password),
                            text: $password,
                            systemImage: "lock",
                            contentType: mode == .signUp ? .newPassword : .password,
                            keyboard: .default,
                            secure: !showPassword,
                            identifier: "auth-password",
                            trailing: {
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(CheckMedTheme.muted)
                                }
                                .accessibilityLabel(session.t(.password))
                            }
                        )
                    }
                    if mode == .signUp {
                        iconField(
                            session.t(.confirmPassword),
                            text: $confirmPassword,
                            systemImage: "lock",
                            contentType: .newPassword,
                            keyboard: .default,
                            secure: true,
                            identifier: "auth-confirm-password"
                        )
                    }

                    if mode == .login {
                        HStack {
                            Spacer()
                            Button(session.t(.forgotPassword)) { mode = .reset }
                                .font(.system(.footnote, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                        }
                    }

                    Button(action: submit) {
                        Text(primaryTitle)
                            .font(.system(.body, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isLoading)
                    .accessibilityIdentifier("auth-submit")

                    if mode != .reset {
                        orContinueDivider
                        VStack(spacing: 12) {
                            provider(.apple, title: session.t(.continueWithApple), identifier: "auth-apple-form") {
                                session.requestProvider(.apple)
                            }
                            provider(.google, title: session.t(.continueWithGoogle), identifier: "auth-google-form") {
                                session.requestProvider(.google)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Spacer()
                        Text(mode == .login ? session.t(.noAccountPrompt) : session.t(.alreadyHaveAccount))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(CheckMedTheme.muted)
                        Button(mode == .login ? session.t(.signUpShort) : session.t(.logIn)) { toggleMode() }
                            .font(.system(.footnote, design: .rounded).weight(.heavy))
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                            .accessibilityIdentifier("auth-toggle-mode")
                        Spacer()
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }
                .scrollClipDisabled()
            }
            .background(
                CheckMedTheme.surface
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 36,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 36,
                            style: .continuous
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private var formTitle: String {
        switch mode {
        case .login:
            session.showWelcomeBack ? session.t(.welcomeBack) : session.t(.signInHeadline)
        case .signUp: session.t(.createAccount)
        case .reset: session.t(.forgotPassword)
        }
    }

    private var formSubhead: String {
        switch mode {
        case .login:
            session.showWelcomeBack ? session.t(.signInToContinue) : session.t(.signInBodyOnboarding)
        case .signUp: session.t(.signInBubbleSignUp)
        case .reset: session.t(.signInBubbleReset)
        }
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

    private var orContinueDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(CheckMedTheme.locked)
                .frame(height: 1)
            Text(session.t(.orContinueWith))
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(CheckMedTheme.muted)
            Rectangle()
                .fill(CheckMedTheme.locked)
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var primaryTitle: String {
        switch mode {
        case .login: session.t(.signIn)
        case .signUp: session.t(.createAccount)
        case .reset: session.t(.sendResetLink)
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
            page = .form
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

    private func iconField<Trailing: View>(
        _ title: String,
        text: Binding<String>,
        systemImage: String,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        secure: Bool,
        identifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(CheckMedTheme.muted)
                .frame(width: 18)
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
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CheckMedTheme.locked, lineWidth: 1.5)
        )
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }

    private func iconField(
        _ title: String,
        text: Binding<String>,
        systemImage: String,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        secure: Bool,
        identifier: String
    ) -> some View {
        iconField(
            title,
            text: text,
            systemImage: systemImage,
            contentType: contentType,
            keyboard: keyboard,
            secure: secure,
            identifier: identifier,
            trailing: { EmptyView() }
        )
    }

    private enum ProviderKind {
        case apple, google
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
            .padding(.vertical, 15)
            .background(kind == .apple ? Color.black : Color.white, in: Capsule())
            .overlay(
                Capsule().stroke(
                    kind == .apple ? Color.clear : CheckMedTheme.ink.opacity(0.12),
                    lineWidth: 1.5
                )
            )
            .shadow(color: .black.opacity(kind == .apple ? 0 : 0.06), radius: 8, y: 3)
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
                .foregroundStyle(.white)
        case .google:
            Text("G")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(CheckMedTheme.google)
        }
    }
}
