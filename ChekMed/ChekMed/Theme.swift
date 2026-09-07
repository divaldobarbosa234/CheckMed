import SwiftUI
import UIKit

enum CheckMedTheme {
    /// Cream canvas matching Phil’s belly.
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.08, blue: 0.04, alpha: 1)
            : UIColor(red: 1, green: 0.957, blue: 0.839, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.13, blue: 0.07, alpha: 1)
            : UIColor(red: 1, green: 0.988, blue: 0.957, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.957, blue: 0.839, alpha: 1)
            : UIColor(red: 0.227, green: 0.145, blue: 0.055, alpha: 1)
    })
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.82, green: 0.70, blue: 0.52, alpha: 1)
            : UIColor(red: 0.545, green: 0.416, blue: 0.267, alpha: 1)
    })
    static let locked = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.32, green: 0.23, blue: 0.12, alpha: 1)
            : UIColor(red: 0.941, green: 0.875, blue: 0.737, alpha: 1)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.25, blue: 0.14, alpha: 1)
            : UIColor(red: 0.953, green: 0.886, blue: 0.757, alpha: 1)
    })
    /// Baby-blue canvas sampled from phil_onboarding_flow.mp4 edges.
    static let philFlowCanvasUIColor = UIColor(red: 193 / 255, green: 232 / 255, blue: 249 / 255, alpha: 1)
    static let philFlowCanvas = Color(uiColor: philFlowCanvasUIColor)
    /// Active How it Works page pill (blue, not gold).
    static let flowDot = Color(hex: 0x3B8FD4)
    /// Inactive How it Works dots (pale blue, not locked cream/orange).
    static let flowDotIdle = Color(hex: 0x8EC4E8)
    /// Canvas sampled from phil_sad.mp4 edges (off-white, not cream).
    static let philSadCanvasUIColor = UIColor(red: 252 / 255, green: 251 / 255, blue: 242 / 255, alpha: 1)
    static let philSadCanvas = Color(uiColor: philSadCanvasUIColor)
    /// Phil body / splash gold.
    static let primary = Color(hex: 0xFBD604)
    /// Beak / feet orange, button shadow.
    static let primaryShadow = Color(hex: 0xE07000)
    static let onPrimary = Color(hex: 0x3A250E)
    static let current = Color(hex: 0xF08A10)
    static let streak = Color(hex: 0xFF8A00)
    static let skip = Color(hex: 0xFFC800)
    static let danger = Color(hex: 0xFF4B4B)
    static let guestBg = Color(hex: 0xFFF4CC)
    static let guestBorder = Color(hex: 0xFFC800)
    static let safety = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.82, blue: 0.42, alpha: 1)
            : UIColor(red: 0.541, green: 0.353, blue: 0, alpha: 1)
    })
    static let belly = Color(hex: 0xFFF3C4)
    static let cheek = Color(hex: 0xFF8FAB)
    static let beak = Color(hex: 0xFF8A00)
    static let google = Color(hex: 0x4285F4)
    static let superAccent = Color(hex: 0xE86A1A)
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func title(_ session: SessionStore) -> String {
        switch self {
        case .system: session.t(.appearanceSystem)
        case .light: session.t(.appearanceLight)
        case .dark: session.t(.appearanceDark)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
