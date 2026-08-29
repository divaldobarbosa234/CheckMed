import SwiftUI

enum CheckMedTheme {
    static let background = Color(hex: 0xFFF8EE)
    static let surface = Color.white
    static let primary = Color(hex: 0x58CC02)
    static let primaryShadow = Color(hex: 0x46A302)
    static let ink = Color(hex: 0x3C3C3C)
    static let muted = Color(hex: 0x777777)
    static let locked = Color(hex: 0xE5E5E5)
    static let current = Color(hex: 0x1CB0F6)
    static let streak = Color(hex: 0xFF9600)
    static let skip = Color(hex: 0xFFC800)
    static let danger = Color(hex: 0xFF4B4B)
    static let guestBg = Color(hex: 0xFFF4CC)
    static let guestBorder = Color(hex: 0xFFC800)
    static let safety = Color(hex: 0x8A5A00)
    static let belly = Color(hex: 0xE8FFD4)
    static let cheek = Color(hex: 0xFF8FAB)
    static let beak = Color(hex: 0xFF9600)
    static let facebook = Color(hex: 0x1877F2)
    static let superAccent = Color(hex: 0xCE82FF)
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
