import SwiftUI

struct TreatmentsView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Treatments")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 72)
                        SpeechBubbleView(
                            text: "This is where we organize what you verified. One mock treatment lives here until scan and editor land."
                        )
                    }
                    Button {
                        path.append(ProductRoute.treatment)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(CheckMedTheme.primaryShadow)
                            Text("Morning + evening routine")
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                            Text("Vitamin D · Metformin · Atorvastatin. Remaining days and the original document arrive with import. Phil will keep the path in order.")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CheckMedTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open treatment editor placeholder")
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProductRoute.self) { route in
                ProductRouteView(route: route, path: $path)
            }
        }
    }
}

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("History")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 72)
                        SpeechBubbleView(
                            text: "Taken days count for the streak. Skip does not break it. Missed will — when real logs land."
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today · 08:00")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(CheckMedTheme.muted)
                        Text("Vitamin D 1000 IU")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text("Taken")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.primaryShadow)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
                    )
                    Text("Later doses appear here after you tap Taken or Skip on Home.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 72)
                        SpeechBubbleView(
                            text: session.isGuest
                                ? "Guest for now. Create an account and I follow you — not this phone. Super never blocks Taken."
                                : "You're in, \(session.displayName). I follow this account — Super never blocks Taken."
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(CheckMedTheme.muted)
                        Text(session.isGuest ? "Guest" : (session.email ?? session.displayName))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text(
                            session.isGuest
                                ? "Cloud scan stays behind an account. Google, email, or guest until Apple ships."
                                : "Session is real. Sign out anytime. Cloud treatments sync in Phase 3."
                        )
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                        if session.isGuest {
                            CheckMedButton(title: "Create account") { showSignIn = true }
                        } else {
                            CheckMedButton(title: "Sign out", style: .secondary) {
                                session.signOut()
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CheckMedTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
                    )

                    profileRow(label: "Companion", value: session.companionName)
                    Button {
                        path.append(ProductRoute.family)
                    } label: {
                        profileRow(label: "Family profiles", value: "1 of 1")
                    }
                    .buttonStyle(.plain)
                    Button {
                        path.append(ProductRoute.paywall)
                    } label: {
                        profileRow(label: "Super CheckMed", value: "Free")
                    }
                    .buttonStyle(.plain)
                    profileRow(label: "Notifications", value: "On (preview)")
                    profileRow(label: "Voice & language", value: "English")

                    if !session.isGuest {
                        Button("Delete account & data") { confirmDelete = true }
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProductRoute.self) { route in
                ProductRouteView(route: route, path: $path)
            }
            .sheet(isPresented: $showSignIn) {
                NavigationStack { SignInView() }
            }
            .alert("Delete account & data", isPresented: $confirmDelete) {
                Button("Sign out here", role: .destructive) { session.deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This signs you out now. Wiping the cloud account is Phase 6. You can also delete the user in the Supabase dashboard.")
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded).weight(.bold))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
        }
        .padding(16)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xEFEFEF), lineWidth: 2)
        )
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") { HomeView() }
            Tab("Treatments", systemImage: "pills.fill") { TreatmentsView() }
            Tab("History", systemImage: "clock.fill") { HistoryView() }
            Tab("Profile", systemImage: "person.fill") { ProfileView() }
        }
        .tint(CheckMedTheme.primaryShadow)
    }
}
