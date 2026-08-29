import SwiftUI
import UIKit

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var mode: Mode = .login
    @State private var showAppleComingSoon = false

    private enum Mode {
        case login, signUp, reset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    PhilView(size: 88)
                    SpeechBubbleView(text: bubbleText)
                }
                Text("Sign in to CheckMed")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                Text("Real session. Guest can still tap Home. An account is required before a prescription photo or PDF syncs to the cloud.")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(CheckMedTheme.muted)

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(CheckMedTheme.danger)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                }
                if let note = session.lastAuthNote, note != "sign-in" {
                    Text(note)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.safety)
                }
                if !session.supabaseConfigured {
                    Text("Supabase keys are not in this iOS target yet. Copy SupabaseConfig.example to Secrets.xcconfig. Guest still works.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.safety)
                }
                if session.supabaseConfigured && !session.googleConfigured {
                    Text("Google needs the iOS Client ID from Google Cloud Console → APIs & Services → Credentials → iOS OAuth 2.0 Client ID → Client ID, pasted into GOOGLE_IOS_CLIENT_ID.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.safety)
                }

                provider("Continue with Apple", color: .black) {
                    session.requestProvider(.apple)
                    showAppleComingSoon = true
                }
                provider("Continue with Google", color: Color(hex: 0x4285F4)) {
                    session.requestProvider(.google)
                }
                provider("Continue with Facebook", color: CheckMedTheme.facebook) {
                    session.requestProvider(.facebook)
                }

                field("Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress, secure: false)

                if mode != .reset {
                    field("Password", text: $password, contentType: mode == .signUp ? .newPassword : .password, keyboard: .default, secure: true)
                }
                if mode == .signUp {
                    field("Confirm password", text: $confirmPassword, contentType: .newPassword, keyboard: .default, secure: true)
                }

                CheckMedButton(title: primaryTitle, action: submit)
                    .disabled(session.isLoading)

                HStack {
                    Button(secondaryTitle) { toggleMode() }
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                    Spacer()
                    if mode != .reset {
                        Button("Forgot password?") { mode = .reset }
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                    }
                }
                .foregroundStyle(CheckMedTheme.ink)

                if session.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                CheckMedButton(title: "Continue as guest", style: .ghost) {
                    session.continueAsGuest()
                    dismiss()
                }
                SafetyCaption()
            }
            .padding(20)
        }
        .background(CheckMedTheme.background)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(session.isLoading)
        .alert("Sign in with Apple", isPresented: $showAppleComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We'll have this section before launch")
        }
        .onChange(of: session.kind) { _, kind in
            if kind == .authenticated { dismiss() }
        }
    }

    private var bubbleText: String {
        switch mode {
        case .login: "Save your streak. Google, email, or guest — I follow the account, not this phone."
        case .signUp: "Create an account and I’ll keep your path with you."
        case .reset: "I’ll send a reset link if that email is on file."
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .login: "Log in"
        case .signUp: "Create account"
        case .reset: "Send reset link"
        }
    }

    private var secondaryTitle: String {
        switch mode {
        case .login: "Need an account? Sign up"
        case .signUp, .reset: "Already have an account? Log in"
        }
    }

    private func toggleMode() {
        session.auth.clearMessages()
        mode = mode == .login ? .signUp : .login
        confirmPassword = ""
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            session.auth.presentError("Phil needs a real email.")
            return
        }
        switch mode {
        case .login:
            guard !password.isEmpty else {
                session.auth.presentError("Enter your password.")
                return
            }
            Task { await session.signIn(email: trimmedEmail, password: password) }
        case .signUp:
            guard password.count >= 6 else {
                session.auth.presentError("Password needs at least 6 characters.")
                return
            }
            guard password == confirmPassword else {
                session.auth.presentError("Passwords need to match.")
                return
            }
            Task { await session.signUp(email: trimmedEmail, password: password) }
        case .reset:
            Task { await session.resetPassword(email: trimmedEmail) }
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        secure: Bool
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
        .padding(14)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckMedTheme.locked, lineWidth: 2))
    }

    private func provider(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
