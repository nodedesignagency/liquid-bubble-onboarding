import SwiftUI

/// Light and airy, like the reference: near-white canvas, pastel liquid, ink type, one violet accent.
enum Theme {
    static let background = Color(hex: 0xF8F7FB)
    static let ink = Color(hex: 0x15132B)
    static let inkSecondary = Color(hex: 0x6F6C84)
    static let inkTertiary = Color(hex: 0xA3A0B5)
    /// Accent phrase in each headline.
    static let accent = Color(hex: 0x6B5BFF)
    static let track = Color(hex: 0x15132B, opacity: 0.1)

    /// The liquid shifts from periwinkle through lavender to a pink lilac across the stage.
    static let liquidGradient = [Color(hex: 0xC2CEFF), Color(hex: 0xD5C4FF), Color(hex: 0xEEC9EF)]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
