import SwiftUI
import UIKit

/// Presentation-only artwork and category mapping. Does not award grants.
enum AchievementArtwork {
    static let totalCount = RewardCatalog.Achievement.allCases.count

    static let journey: [RewardCatalog.Achievement] = [
        .firstDose, .firstDay, .firstRecovery, .firstTreatmentComplete
    ]

    static let consistency: [RewardCatalog.Achievement] = [
        .streak1, .streak3, .streak7, .streak14, .streak30, .streak90
    ]

    static func assetName(for achievement: RewardCatalog.Achievement) -> String {
        switch achievement {
        case .firstDose: "achievement_first_dose"
        case .firstDay: "achievement_first_day"
        case .firstRecovery: "achievement_first_recovery"
        case .firstTreatmentComplete: "achievement_first_treatment_complete"
        case .streak1: "achievement_streak_1"
        case .streak3: "achievement_streak_3"
        case .streak7: "achievement_streak_7"
        case .streak14: "achievement_streak_14"
        case .streak30: "achievement_streak_30"
        case .streak90: "achievement_streak_90"
        }
    }

    static func titleKey(for achievement: RewardCatalog.Achievement) -> L10n.Key {
        switch achievement {
        case .firstDose: .achievementTitleFirstDose
        case .firstDay: .achievementTitleFirstDay
        case .firstRecovery: .achievementTitleFirstRecovery
        case .firstTreatmentComplete: .achievementTitleFirstTreatment
        case .streak1: .achievementTitleStreak1
        case .streak3: .achievementTitleStreak3
        case .streak7: .achievementTitleStreak7
        case .streak14: .achievementTitleStreak14
        case .streak30: .achievementTitleStreak30
        case .streak90: .achievementTitleStreak90
        }
    }

    static func bodyKey(for achievement: RewardCatalog.Achievement) -> L10n.Key {
        switch achievement {
        case .firstDose: .achievementBodyFirstDose
        case .firstDay: .achievementBodyFirstDay
        case .firstRecovery: .achievementBodyFirstRecovery
        case .firstTreatmentComplete: .achievementBodyFirstTreatment
        case .streak1: .achievementBodyStreak1
        case .streak3: .achievementBodyStreak3
        case .streak7: .achievementBodyStreak7
        case .streak14: .achievementBodyStreak14
        case .streak30: .achievementBodyStreak30
        case .streak90: .achievementBodyStreak90
        }
    }

    static func howToUnlockKey(for achievement: RewardCatalog.Achievement) -> L10n.Key {
        switch achievement {
        case .firstDose: .achievementHowFirstDose
        case .firstDay: .achievementHowFirstDay
        case .firstRecovery: .achievementHowFirstRecovery
        case .firstTreatmentComplete: .achievementHowFirstTreatment
        case .streak1: .achievementHowStreak1
        case .streak3: .achievementHowStreak3
        case .streak7: .achievementHowStreak7
        case .streak14: .achievementHowStreak14
        case .streak30: .achievementHowStreak30
        case .streak90: .achievementHowStreak90
        }
    }

    static func taglineKey(for achievement: RewardCatalog.Achievement) -> L10n.Key {
        switch achievement {
        case .firstDose: .achievementTaglineFirstDose
        case .firstDay: .achievementTaglineFirstDay
        case .firstRecovery: .achievementTaglineFirstRecovery
        case .firstTreatmentComplete: .achievementTaglineFirstTreatment
        case .streak1: .achievementTaglineStreak1
        case .streak3: .achievementTaglineStreak3
        case .streak7: .achievementTaglineStreak7
        case .streak14: .achievementTaglineStreak14
        case .streak30: .achievementTaglineStreak30
        case .streak90: .achievementTaglineStreak90
        }
    }

    static func shareHookKey(for achievement: RewardCatalog.Achievement) -> L10n.Key {
        switch achievement {
        case .firstDose: .badgesShareHookFirstDose
        case .firstDay: .badgesShareHookFirstDay
        case .firstRecovery: .badgesShareHookFirstRecovery
        case .firstTreatmentComplete: .badgesShareHookFirstTreatment
        case .streak1: .badgesShareHookStreak1
        case .streak3: .badgesShareHookStreak3
        case .streak7: .badgesShareHookStreak7
        case .streak14: .badgesShareHookStreak14
        case .streak30: .badgesShareHookStreak30
        case .streak90: .badgesShareHookStreak90
        }
    }

    static func isJourney(_ achievement: RewardCatalog.Achievement) -> Bool {
        journey.contains(achievement)
    }
}

/// Matches `FloatingPlusMenu`: tab bar 52 + gap 10 + plus 58 + content breathing room.
enum ProgressOverlayGeometry {
    static let bottomClearance: CGFloat = 52 + 10 + 58 + 16
}

/// Public marketing destination. Do not scatter this URL through presentation code.
enum CheckMedPublicWeb {
    static let siteURL = URL(string: "https://connycooper.com")!
    static var siteHost: String { siteURL.host ?? "connycooper.com" }
}

/// Presents `UIActivityViewController` on the topmost controller.
/// `ShareLink` cannot present a second sheet from Progress's existing `.sheet`.
private enum AchievementSharePresenter {
    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Share card: approved IMAGE B geometry on the supplied environment PNG.
private struct AchievementShareCard: View {
    let nameLine: String
    let hookLine: String
    let title: String
    let routinesLine: String
    let brandLine: String
    let discoverMore: String
    let siteHost: String
    let achievement: RewardCatalog.Achievement

    /// Asset-locked 1080×1350 template. Only foreground content is composed here.
    private enum Layout {
        static let canvas = CGSize(width: 1080, height: 1350)
        static let badge = CGRect(x: 245, y: 95, width: 590, height: 590)
        static let pill = CGRect(x: 270, y: 650, width: 540, height: 88)
        static let name = CGRect(x: 140, y: 748, width: 800, height: 82)
        static let hook = CGRect(x: 140, y: 820, width: 800, height: 118)
        static let brand = CGRect(x: 140, y: 960, width: 800, height: 120)
        static let cta = CGRect(x: 140, y: 1142, width: 800, height: 112)
        static let navy = Color(hex: 0x0B2E5B)
        static let primaryBlue = Color(hex: 0x1E90FF)
        static let gray = Color(hex: 0x6B7A90)
    }

    var body: some View {
        let asset = AchievementArtwork.assetName(for: achievement)
        ZStack(alignment: .topLeading) {
            Image("achievement_share_background")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: Layout.canvas.width, height: Layout.canvas.height)
                .clipped()

            Image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(AchievementBadgeFit.extraScale(assetName: asset))
                .frame(width: Layout.badge.width, height: Layout.badge.height)
                .offset(x: Layout.badge.minX, y: Layout.badge.minY)

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Layout.primaryBlue)
                Text(title)
                    .font(.system(size: 37, weight: .semibold, design: .rounded))
                    .foregroundStyle(Layout.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Layout.pill.width, height: Layout.pill.height)
            .background(Color.white.opacity(0.94), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.96), lineWidth: 2)
            )
            .shadow(color: Layout.navy.opacity(0.12), radius: 14, y: 5)
            .offset(x: Layout.pill.minX, y: Layout.pill.minY)

            Text(nameLine)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(Layout.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(width: Layout.name.width, height: Layout.name.height)
                .offset(x: Layout.name.minX, y: Layout.name.minY)

            Text(hookLine)
                .font(.system(size: 82, weight: .heavy, design: .rounded))
                .foregroundStyle(Layout.primaryBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
                .frame(width: Layout.hook.width, height: Layout.hook.height)
                .offset(x: Layout.hook.minX, y: Layout.hook.minY)

            VStack(spacing: 2) {
                Text(routinesLine)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Layout.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("\(brandLine) ♥")
                    .font(.system(size: 50, weight: .bold, design: .serif).italic())
                    .foregroundStyle(Layout.primaryBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .multilineTextAlignment(.center)
            .frame(width: Layout.brand.width, height: Layout.brand.height)
            .offset(x: Layout.brand.minX, y: Layout.brand.minY)

            HStack(spacing: 22) {
                Image(systemName: "globe")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(Layout.primaryBlue)
                    .frame(width: 72)

                Rectangle()
                    .fill(Layout.gray.opacity(0.35))
                    .frame(width: 2, height: 66)

                VStack(alignment: .leading, spacing: 2) {
                    Text(discoverMore)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Layout.gray)
                    Text(siteHost)
                        .font(.system(size: 39, weight: .bold, design: .rounded))
                        .foregroundStyle(Layout.primaryBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Layout.primaryBlue)
            }
            .padding(.horizontal, 34)
            .frame(width: Layout.cta.width, height: Layout.cta.height, alignment: .leading)
            .background(Color(hex: 0xF4FAFF).opacity(0.96), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.96), lineWidth: 2)
            )
            .shadow(color: Layout.navy.opacity(0.16), radius: 16, y: 6)
            .offset(x: Layout.cta.minX, y: Layout.cta.minY)
        }
        .frame(width: Layout.canvas.width, height: Layout.canvas.height, alignment: .topLeading)
        .clipped()
    }
}

@MainActor
private enum AchievementShareCardRenderer {
    static func render(_ card: AchievementShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        return renderer.uiImage
    }

    #if DEBUG
    static func debugWrite(_ card: AchievementShareCard, named: String) {
        guard let image = render(card), let data = image.pngData() else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("share_cards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(named).png")
        try? data.write(to: url)
        print("[SHARE-CARD] \(named) \(image.size.width)×\(image.size.height) → \(url.path)")
    }
    #endif
}

/// Scales artwork so the opaque hex occupies a consistent fraction of a square slot.
private enum AchievementBadgeFit {
    private static var cache: [String: CGFloat] = [:]
    private static let targetFill: CGFloat = 0.92

    static func extraScale(assetName: String) -> CGFloat {
        if let cached = cache[assetName] { return cached }
        let value = compute(assetName)
        cache[assetName] = value
        return value
    }

    private static func compute(_ name: String) -> CGFloat {
        guard let image = UIImage(named: name), let cgImage = image.cgImage else { return 1 }
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { return 1 }
        let maxDim = 96
        let down = min(CGFloat(maxDim) / CGFloat(srcW), CGFloat(maxDim) / CGFloat(srcH))
        let width = max(1, Int(CGFloat(srcW) * down))
        let height = max(1, Int(CGFloat(srcH) * down))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1 }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                let alpha = data[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > 12 {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX > minX, maxY > minY else { return 1 }
        let occupied = max(
            CGFloat(maxX - minX + 1) / CGFloat(width),
            CGFloat(maxY - minY + 1) / CGFloat(height)
        )
        guard occupied > 0.08 else { return 1 }
        return min(1.45, max(1, targetFill / occupied))
    }
}

struct AchievementBadgeArt: View {
    enum LockStyle {
        case compact
        case hero
    }

    let achievement: RewardCatalog.Achievement
    var unlocked: Bool
    var size: CGFloat
    var showsLock: Bool = true
    var lockStyle: LockStyle = .compact

    var body: some View {
        let asset = AchievementArtwork.assetName(for: achievement)
        ZStack(alignment: .bottom) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .scaleEffect(AchievementBadgeFit.extraScale(assetName: asset))
                .saturation(unlocked ? 1 : 0.0)
                .opacity(unlocked ? 1 : 0.88)
                .brightness(unlocked ? 0 : -0.02)
                .frame(width: size, height: size)
                .clipped()
                .accessibilityHidden(true)
            if !unlocked, showsLock {
                lockBadge
                    .offset(y: lockStyle == .hero ? size * 0.02 : -size * 0.02)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var lockBadge: some View {
        let iconSize = lockStyle == .hero ? max(16, size * 0.08) : max(9, size * 0.12)
        Image(systemName: "lock.fill")
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(Color(hex: 0x6B7C8D))
            .padding(lockStyle == .hero ? max(10, size * 0.045) : max(5, size * 0.055))
            .background(Color.white.opacity(0.96), in: Circle())
            .overlay(Circle().stroke(Color(hex: 0xC5D0DA), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
    }
}

/// Compact Your Progress card. Reads gallery items; does not write grants.
struct BadgesPreviewCard: View {
    @Environment(SessionStore.self) private var session
    let items: [RewardCatalog.AchievementGalleryItem]
    var onOpen: () -> Void

    private var unlockedCount: Int { items.filter(\.isUnlocked).count }
    private var preview: [RewardCatalog.AchievementGalleryItem] { Array(items.prefix(8)) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.t(.badgesTitle))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckMedTheme.ink)
                Spacer()
                Button(action: onOpen) {
                    Text(session.t(.badgesSeeAll))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.flowDot)
                }
                .buttonStyle(.plain)
                .accessibilityHint(session.t(.badgesOpenHint))
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(preview) { item in
                    Button(action: onOpen) {
                        VStack(spacing: 6) {
                            AchievementBadgeArt(
                                achievement: item.achievement,
                                unlocked: item.isUnlocked,
                                size: 64
                            )
                            Text(session.t(AchievementArtwork.titleKey(for: item.achievement)))
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(item.isUnlocked ? CheckMedTheme.ink : CheckMedTheme.muted)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.t(AchievementArtwork.titleKey(for: item.achievement)))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckMedTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CheckMedTheme.navy.opacity(0.06), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(session.t(.badgesTitle)). \(session.t(.badgesCollected, unlockedCount, AchievementArtwork.totalCount))"
        )
    }
}

struct BadgesScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(CheckMedStore.self) private var treatments
    @State private var category: BadgeCategory = .all

    private var items: [RewardCatalog.AchievementGalleryItem] { treatments.achievementGallery() }
    private var unlockedCount: Int { items.filter(\.isUnlocked).count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                hero
                collectionStatus
                categoryPills
                if category != .consistency {
                    section(
                        title: session.t(.badgesCategoryJourney),
                        count: AchievementArtwork.journey.count,
                        items: items(in: AchievementArtwork.journey)
                    )
                }
                if category != .journey {
                    section(
                        title: session.t(.badgesCategoryConsistency),
                        count: AchievementArtwork.consistency.count,
                        items: items(in: AchievementArtwork.consistency)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(CheckMedTheme.background)
        .navigationTitle(session.t(.badgesTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CheckMedTheme.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: ProgressOverlayGeometry.bottomClearance)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(hex: 0x3AA4F0),
                    Color(hex: 0x6CC4F8),
                    Color(hex: 0xBFE9FF),
                    Color(hex: 0xF4D4F2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            heroCloud(width: 160, height: 46, x: -70, y: -18, opacity: 0.55)
            heroCloud(width: 120, height: 36, x: 40, y: -36, opacity: 0.42)
            heroCloud(width: 90, height: 28, x: -20, y: 28, opacity: 0.32)
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 70, height: 70)
                .blur(radius: 8)
                .offset(x: 22, y: -40)
                .allowsHitTesting(false)
            badgesHeroConfetti
            HStack(alignment: .bottom, spacing: 0) {
                Text(session.t(.badgesHeroLine))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color(hex: 0x1A5F9A).opacity(0.28), radius: 4, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 18)
                PhilDoctor2DImage(size: 118)
                    .padding(.trailing, 6)
                    .padding(.bottom, 2)
            }
            .padding(.leading, 16)
            .padding(.top, 10)
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.t(.badgesHeroLine))
    }

    private func heroCloud(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
            .blur(radius: 4)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    private var badgesHeroConfetti: some View {
        ZStack {
            Capsule().fill(Color(hex: 0xFF8A4A)).frame(width: 6, height: 12).rotationEffect(.degrees(-28)).offset(x: -100, y: -22)
            Capsule().fill(Color(hex: 0xFFF176)).frame(width: 5, height: 11).rotationEffect(.degrees(18)).offset(x: -48, y: -40)
            Capsule().fill(Color.white.opacity(0.9)).frame(width: 5, height: 10).rotationEffect(.degrees(40)).offset(x: 8, y: -36)
            Capsule().fill(Color(hex: 0xFF8FAB)).frame(width: 6, height: 11).rotationEffect(.degrees(-16)).offset(x: 58, y: -28)
            Capsule().fill(Color(hex: 0x7B61FF)).frame(width: 5, height: 9).rotationEffect(.degrees(30)).offset(x: -72, y: 8)
        }
        .allowsHitTesting(false)
    }

    private var collectionStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.t(.badgesCollected, unlockedCount, AchievementArtwork.totalCount))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(CheckMedTheme.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CheckMedTheme.hairline)
                    Capsule()
                        .fill(CheckMedTheme.flowDot)
                        .frame(
                            width: max(
                                8,
                                geo.size.width * CGFloat(unlockedCount) / CGFloat(max(1, AchievementArtwork.totalCount))
                            )
                        )
                }
            }
            .frame(height: 7)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.t(.badgesCollected, unlockedCount, AchievementArtwork.totalCount))
    }

    private var categoryPills: some View {
        HStack(spacing: 6) {
            ForEach(BadgeCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    Text(item.title(session))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(category == item ? Color.white : CheckMedTheme.flowDot)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            category == item ? CheckMedTheme.flowDot : Color(hex: 0xEAF5FC),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == item ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.t(.badgesCategoryAll))
    }

    private func section(
        title: String,
        count: Int,
        items: [RewardCatalog.AchievementGalleryItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                Text(session.t(.badgesSectionCount, count))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(CheckMedTheme.muted)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ],
                spacing: 8
            ) {
                ForEach(items) { item in
                    NavigationLink {
                        BadgeDetailScreen(item: item)
                    } label: {
                        BadgeGridCell(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func items(in ids: [RewardCatalog.Achievement]) -> [RewardCatalog.AchievementGalleryItem] {
        let wanted = Set(ids)
        return items.filter { wanted.contains($0.achievement) }
            .sorted { lhs, rhs in
                (ids.firstIndex(of: lhs.achievement) ?? 0) < (ids.firstIndex(of: rhs.achievement) ?? 0)
            }
    }
}

private enum BadgeCategory: String, CaseIterable, Identifiable {
    case all, journey, consistency
    var id: String { rawValue }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .all: session.t(.badgesCategoryAll)
        case .journey: session.t(.badgesCategoryJourney)
        case .consistency: session.t(.badgesCategoryConsistency)
        }
    }
}

private struct BadgeGridCell: View {
    @Environment(SessionStore.self) private var session
    let item: RewardCatalog.AchievementGalleryItem

    var body: some View {
        VStack(spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        AchievementBadgeArt(
                            achievement: item.achievement,
                            unlocked: item.isUnlocked,
                            size: geo.size.width
                        )
                    }
                }
            Text(session.t(AchievementArtwork.titleKey(for: item.achievement)))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(CheckMedTheme.ink.opacity(item.isUnlocked ? 1 : 0.72))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilitySummary: String {
        let name = session.t(AchievementArtwork.titleKey(for: item.achievement))
        let state = session.t(item.isUnlocked ? .achievementUnlocked : .achievementLocked)
        return "\(name). \(state)"
    }
}

struct BadgeDetailScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: RewardCatalog.AchievementGalleryItem
    @State private var isPresentingShare = false

    private var titleText: String { session.t(AchievementArtwork.titleKey(for: item.achievement)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            detailEnvironment
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                detailBackBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: item.isUnlocked ? 16 : 18) {
                        hero
                        VStack(spacing: item.isUnlocked ? 8 : 10) {
                            Text(titleText)
                                .font(.system(.title, design: .rounded).weight(.black))
                                .foregroundStyle(item.isUnlocked ? CheckMedTheme.navy : Color(hex: 0x3A4C5C))
                                .multilineTextAlignment(.center)
                            Text(session.t(AchievementArtwork.taglineKey(for: item.achievement)))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(item.isUnlocked ? Color(hex: 0x3B8FD4) : Color(hex: 0x7B8C9C))
                                .multilineTextAlignment(.center)
                            Text(session.t(AchievementArtwork.bodyKey(for: item.achievement)))
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(item.isUnlocked ? CheckMedTheme.ink.opacity(0.78) : Color(hex: 0x5C6D7C))
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                                .padding(.horizontal, item.isUnlocked ? 4 : 8)
                        }
                        .padding(.horizontal, 12)

                        if item.isUnlocked {
                            unlockedDateCard
                            shareButton
                        } else {
                            howToUnlockCard
                            keepGoingCard
                        }
                    }
                    .padding(.horizontal, item.isUnlocked ? 22 : 26)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: ProgressOverlayGeometry.bottomClearance)
        }
        .accessibilityElement(children: .contain)
    }

    private var detailBackBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckMedTheme.navy)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.92), in: Circle())
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.t(.back))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: item.isUnlocked
                            ? [Color(hex: 0xFFE08A).opacity(0.55), Color(hex: 0x7EC8F8).opacity(0.18), Color.clear]
                            : [Color.white.opacity(0.7), Color(hex: 0xB7C9D8).opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 6)
                .allowsHitTesting(false)
            if item.isUnlocked {
                confettiLayer
            }
            AchievementBadgeArt(
                achievement: item.achievement,
                unlocked: item.isUnlocked,
                size: 236,
                showsLock: !item.isUnlocked,
                lockStyle: .hero
            )
            .shadow(
                color: item.isUnlocked ? Color(hex: 0xE8B84A).opacity(0.28) : Color.black.opacity(0.08),
                radius: 18,
                y: 8
            )
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var confettiLayer: some View {
        ZStack {
            ForEach(Array(Self.confetti.enumerated()), id: \.offset) { _, piece in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(piece.color)
                    .frame(width: piece.width, height: piece.height)
                    .rotationEffect(.degrees(piece.rotation))
                    .offset(x: piece.x, y: piece.y)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var unlockedDateCard: some View {
        if let unlockedAt = item.unlockedAt {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE08A4A))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xFDE7D6), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.t(.badgesUnlockedOnLabel))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckMedTheme.muted)
                    Text(unlockedDateText(unlockedAt))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(CheckMedTheme.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .accessibilityLabel(session.t(.achievementUnlockedOn, unlockedDateText(unlockedAt)))
        }
    }

    private var shareButton: some View {
        Button {
            presentAchievementShare()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                Text(session.t(.badgesShareAchievement))
                    .font(.system(.body, design: .rounded).weight(.heavy))
            }
            .foregroundStyle(Color(hex: 0x3B8FD4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(hex: 0xE7F3FC), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPresentingShare)
        .accessibilityLabel(session.t(.badgesShareAchievement))
    }

    /// Present from the topmost UIKit controller so Share is not nested inside the Progress `.sheet`.
    private func presentAchievementShare() {
        guard item.isUnlocked, !isPresentingShare else { return }
        var items: [Any] = []
        let card = AchievementShareCard(
            nameLine: shareNameLine,
            hookLine: session.t(AchievementArtwork.shareHookKey(for: item.achievement)),
            title: titleText,
            routinesLine: session.t(.badgesShareRoutinesLine),
            brandLine: session.t(.badgesShareWithBrand),
            discoverMore: session.t(.badgesShareDiscoverMore),
            siteHost: CheckMedPublicWeb.siteHost,
            achievement: item.achievement
        )
        if let image = AchievementShareCardRenderer.render(card) {
            items.append(image)
            #if DEBUG
            AchievementShareCardRenderer.debugWrite(
                card,
                named: item.achievement.rawValue
            )
            #endif
        }
        items.append(shareCaption)
        items.append(CheckMedPublicWeb.siteURL)
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.excludedActivityTypes = [.assignToContact, .addToReadingList]
        guard let presenter = AchievementSharePresenter.topViewController() else { return }
        if presenter is UIActivityViewController { return }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY - 24,
                width: 8,
                height: 8
            )
            pop.permittedArrowDirections = []
        }
        isPresentingShare = true
        activity.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                isPresentingShare = false
            }
        }
        presenter.present(activity, animated: true)
    }

    private var shareNameLine: String {
        if let first = session.shareCardFirstName {
            return session.t(.badgesShareCompletedNamed, first)
        }
        return session.t(.badgesShareCompletedAnonymous)
    }

    /// Achievement identity only — never medicine, dose, or health data.
    private var shareCaption: String {
        session.t(.badgesShareMessage, titleText)
    }

    private var howToUnlockCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x6B7C8D))
                .frame(width: 32, height: 32)
                .background(Color(hex: 0xE6EEF4), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.t(.badgesHowToUnlock))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color(hex: 0x4A5B6C))
                Text(session.t(AchievementArtwork.howToUnlockKey(for: item.achievement)))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(hex: 0x5C6D7C))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var keepGoingCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: 0xF0B429))
            Text(session.t(.badgesKeepGoingHeadline))
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Color(hex: 0x4A5B6C))
            Text(session.t(.badgesKeepGoingBody))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(hex: 0x7B8C9C))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var detailEnvironment: some View {
        ZStack {
            if item.isUnlocked {
                LinearGradient(
                    colors: [
                        Color(hex: 0x4EB6F2),
                        Color(hex: 0xA8DFFC),
                        Color(hex: 0xFFF4D6),
                        Color(hex: 0xFFD27A)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Color(hex: 0x5BB7F0).opacity(0.55))
                    .frame(width: 340, height: 340)
                    .blur(radius: 42)
                    .offset(x: 70, y: -280)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color(hex: 0xFFE08A).opacity(0.7))
                    .frame(width: 300, height: 300)
                    .blur(radius: 36)
                    .offset(y: 20)
                    .allowsHitTesting(false)
                unlockedSkyClouds
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: 0x8EADC4),
                        Color(hex: 0xC5D8E8),
                        Color(hex: 0xDCE7EF),
                        Color(hex: 0x9BB0C2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                lockedCloudField
            }
        }
    }

    private var unlockedSkyClouds: some View {
        ZStack {
            cloud(width: 260, height: 76, x: -120, y: -340, opacity: 0.42)
            cloud(width: 200, height: 60, x: 110, y: -300, opacity: 0.34)
            cloud(width: 140, height: 42, x: -20, y: -200, opacity: 0.22)
        }
        .allowsHitTesting(false)
    }

    private var lockedCloudField: some View {
        ZStack {
            cloud(width: 320, height: 110, x: -90, y: -340, opacity: 0.82)
            cloud(width: 260, height: 88, x: 130, y: -300, opacity: 0.7)
            cloud(width: 300, height: 100, x: -20, y: -210, opacity: 0.62)
            cloud(width: 220, height: 74, x: 110, y: -120, opacity: 0.52)
            cloud(width: 250, height: 80, x: -130, y: -40, opacity: 0.44)
            cloud(width: 210, height: 70, x: 90, y: 50, opacity: 0.4)
            cloud(width: 300, height: 100, x: -70, y: 150, opacity: 0.46)
            cloud(width: 260, height: 86, x: 110, y: 250, opacity: 0.4)
            cloud(width: 340, height: 120, x: -90, y: 360, opacity: 0.34)
            Ellipse()
                .fill(Color(hex: 0x6E879B).opacity(0.28))
                .frame(width: 480, height: 180)
                .offset(y: 390)
                .blur(radius: 20)
        }
        .allowsHitTesting(false)
    }

    private func cloud(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        HStack(spacing: -width * 0.18) {
            Capsule().fill(Color.white.opacity(opacity))
                .frame(width: width * 0.55, height: height * 0.72)
                .offset(y: height * 0.08)
            Ellipse().fill(Color.white.opacity(opacity + 0.08))
                .frame(width: width * 0.5, height: height)
            Capsule().fill(Color.white.opacity(opacity))
                .frame(width: width * 0.62, height: height * 0.78)
                .offset(y: height * 0.06)
        }
        .blur(radius: 8)
        .offset(x: x, y: y)
    }

    private func unlockedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = session.locale.foundationLocale
        formatter.calendar = session.foundationCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private struct ConfettiPiece {
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var width: CGFloat
        var height: CGFloat
        var color: Color
    }

    private static let confetti: [ConfettiPiece] = [
        .init(x: -118, y: -88, rotation: -28, width: 8, height: 18, color: Color(hex: 0x4CAF50)),
        .init(x: -78, y: -128, rotation: 18, width: 7, height: 16, color: Color(hex: 0xF4C430)),
        .init(x: -28, y: -142, rotation: -12, width: 6, height: 14, color: Color(hex: 0x7B61FF)),
        .init(x: 36, y: -138, rotation: 22, width: 8, height: 17, color: Color(hex: 0xFF8A4A)),
        .init(x: 92, y: -118, rotation: -35, width: 7, height: 16, color: Color(hex: 0x3B8FD4)),
        .init(x: 124, y: -64, rotation: 40, width: 6, height: 14, color: Color(hex: 0xFF5A8A)),
        .init(x: 118, y: 8, rotation: -18, width: 8, height: 16, color: Color(hex: 0x45B94F)),
        .init(x: 96, y: 78, rotation: 28, width: 7, height: 15, color: Color(hex: 0xFBD604)),
        .init(x: -102, y: 72, rotation: -42, width: 7, height: 16, color: Color(hex: 0x8E58D6)),
        .init(x: -128, y: 10, rotation: 15, width: 6, height: 14, color: Color(hex: 0x3B8FD4)),
        .init(x: 12, y: -108, rotation: 8, width: 5, height: 12, color: Color(hex: 0xFF8FAB)),
        .init(x: -48, y: 108, rotation: 32, width: 6, height: 13, color: Color(hex: 0x4CAF50)),
        .init(x: 58, y: 112, rotation: -24, width: 5, height: 12, color: Color(hex: 0xFF8A4A)),
        .init(x: -86, y: -48, rotation: 50, width: 5, height: 11, color: Color(hex: 0x7EC8F8))
    ]
}
