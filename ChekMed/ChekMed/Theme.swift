import SwiftUI
import UIKit

enum CheckMedTheme {
    /// Warm off-white canvas used throughout the redesigned app.
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.09, blue: 0.14, alpha: 1)
            : UIColor(red: 0.985, green: 0.98, blue: 0.95, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.125, blue: 0.19, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 0.995, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.98, blue: 1, alpha: 1)
            : UIColor(red: 0.035, green: 0.14, blue: 0.27, alpha: 1)
    })
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.72, blue: 0.80, alpha: 1)
            : UIColor(red: 0.39, green: 0.47, blue: 0.57, alpha: 1)
    })
    static let locked = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.20, blue: 0.27, alpha: 1)
            : UIColor(red: 0.90, green: 0.92, blue: 0.94, alpha: 1)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.23, blue: 0.29, alpha: 1)
            : UIColor(red: 0.91, green: 0.93, blue: 0.91, alpha: 1)
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
    /// CheckMed green used for primary actions and positive health states.
    static let primary = Color(hex: 0x45B94F)
    static let primaryShadow = Color(hex: 0x178E48)
    static let onPrimary = Color.white
    static let philYellow = Color(hex: 0xFBD604)
    static let current = Color(hex: 0xFFAA32)
    static let streak = Color(hex: 0xFF8A00)
    static let skip = Color(hex: 0xFFC800)
    static let danger = Color(hex: 0xFF4B4B)
    static let guestBg = Color(hex: 0xEEF8EC)
    static let guestBorder = Color(hex: 0xA7DFA9)
    static let safety = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.80, blue: 0.42, alpha: 1)
            : UIColor(red: 0.50, green: 0.34, blue: 0.06, alpha: 1)
    })
    static let belly = Color(hex: 0xFFF4BE)
    static let cheek = Color(hex: 0xFF8FAB)
    static let beak = Color(hex: 0xFF8A00)
    static let google = Color(hex: 0x4285F4)
    static let superAccent = Color(hex: 0x8E58D6)
    static let mintWash = Color(hex: 0xEAF7E8)
    static let blueWash = Color(hex: 0xEAF5FC)
    static let lavenderWash = Color(hex: 0xF1EAFF)
    static let sunshineWash = Color(hex: 0xFFF4B8)
    static let navy = Color(hex: 0x092B50)
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
