import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TodayPathStore.self) private var path
    @State private var showSignIn = false
    @State private var showScan = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.isGuest {
                        GuestBanner { showSignIn = true }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hey \(session.displayName)")
                                .font(.system(.title2, design: .rounded).weight(.heavy))
                            Text("Today’s path with \(session.companionName)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(CheckMedTheme.muted)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("🔥")
                            Text("\(TodayPathStore.streakDays)")
                                .font(.system(.title3, design: .rounded).weight(.black))
                                .foregroundStyle(CheckMedTheme.streak)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(CheckMedTheme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0xF3D7A0), lineWidth: 2))
                        .accessibilityLabel("\(TodayPathStore.streakDays) day streak")
                    }

                    HStack(alignment: .center, spacing: 12) {
                        PhilView(size: 96, mood: path.displayMood)
                        SpeechBubbleView(text: path.bubble)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(CheckMedTheme.locked)
                                Capsule()
                                    .fill(CheckMedTheme.primary)
                                    .frame(width: geo.size.width * CGFloat(path.completed) / CGFloat(max(path.total, 1)))
                            }
                        }
                        .frame(height: 12)
                        Text(path.pathComplete ? "Path complete" : "\(path.completed) of \(path.total) today")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(CheckMedTheme.muted)
                    }

                    ForEach(Array(path.nodes.enumerated()), id: \.element.id) { index, node in
                        PathNodeView(
                            node: node,
                            offset: TodayPathStore.offsets.indices.contains(index) ? TodayPathStore.offsets[index] : 0,
                            showConnector: index < path.nodes.count - 1,
                            onTake: { path.takeCurrent() },
                            onSkip: { path.skipCurrent() }
                        )
                    }

                    Button {
                        showScan = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(CheckMedTheme.primary, in: Circle())
                                .shadow(color: CheckMedTheme.primaryShadow, radius: 0, y: 4)
                            Text("SCAN")
                                .font(.system(.body, design: .rounded).weight(.heavy))
                                .foregroundStyle(CheckMedTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Scan a prescription")

                    SafetyCaption()
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(CheckMedTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSignIn) {
                NavigationStack { SignInView() }
            }
            .sheet(isPresented: $showScan) {
                ScanView()
            }
        }
    }
}
