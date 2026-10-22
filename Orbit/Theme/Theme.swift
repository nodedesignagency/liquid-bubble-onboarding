import SwiftUI

/// A flat near-white canvas, quiet Apple-gray type, and bluish lavender liquid.
/// The bubbles are the only color on screen.
enum Theme {
    static let background = Color(hex: 0xFAFAFA)
    static let ink = Color(hex: 0x1D1D1F)
    static let inkSecondary = Color(hex: 0x86868B)
    static let hairline = Color(hex: 0x1D1D1F, opacity: 0.14)

    /// The liquid, lit from above: lighter at the top of the screen, deeper toward the bottom.
    static let liquidLight = Color(hex: 0xE8E2FB)
    static let liquid = Color(hex: 0xDCD3F7)
    static let liquidDeep = Color(hex: 0xD0C4F2)
    /// The shaded lower right of each blob.
    static let liquidShade = Color(hex: 0xB9A9EC)
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
