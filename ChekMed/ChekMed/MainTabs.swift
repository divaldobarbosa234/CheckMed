import SwiftUI

struct TreatmentsView: View {
    var body: some View {
        placeholder(title: "Treatments", body: "Phil will host each paper here after you verify OCR. Schedule and remaining days land with the editor.")
    }
}

struct HistoryView: View {
    var body: some View {
        placeholder(title: "History", body: "Taken and skipped logs stay on today’s path first. Longer filters are Super.")
    }
}

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        PhilView(size: 56)
                        VStack(alignment: .leading) {
                            Text(session.isGuest ? "Guest" : session.displayName)
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                            Text(session.isGuest ? "Account required to sync" : "Signed in")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                    }
                    .listRowBackground(CheckMedTheme.background)
                }
                Section("Account") {
                    if session.isGuest {
                        Button("Create an account") { showSignIn = true }
                    } else {
                        Button("Sign out", role: .destructive) {
                            session.signOut()
                        }
                        .disabled(session.isLoading)
                    }
                }
                Section("CheckMed") {
                    Text("Super CheckMed, family switcher, and delete-account cloud wipe stay in later phases. Sign out is in scope.")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(CheckMedTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CheckMedTheme.background)
            .navigationTitle("Profile")
            .sheet(isPresented: $showSignIn) {
                NavigationStack { SignInView() }
            }
        }
    }
}

private func placeholder(title: String, body: String) -> some View {
    NavigationStack {
        VStack(spacing: 16) {
            PhilView(size: 96)
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
            Text(body)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(CheckMedTheme.muted)
                .multilineTextAlignment(.center)
            SafetyCaption()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CheckMedTheme.background)
        .navigationTitle(title)
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
