import SwiftUI

/// Taken straight from the reference: a flat near-white canvas, quiet Apple-gray type,
/// and soft lavender liquid. The bubbles are the only color on screen.
enum Theme {
    static let background = Color(hex: 0xFAFAFA)
    static let ink = Color(hex: 0x1D1D1F)
    static let inkSecondary = Color(hex: 0x86868B)
    static let hairline = Color(hex: 0x1D1D1F, opacity: 0.1)

    /// The liquid drifts from a bluish lavender to a pinkish one across the stage. Barely: it should read as one color.
    static let liquidGradient = [Color(hex: 0xDCD6F5), Color(hex: 0xE2D5F2), Color(hex: 0xEAD6F0)]
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
