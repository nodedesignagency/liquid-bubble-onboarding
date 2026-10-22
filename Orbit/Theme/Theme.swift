import SwiftUI

/// A flat near-white canvas, quiet Apple-gray type, and pale pastel liquid.
/// The bubbles are the only color on screen.
enum Theme {
    static let background = Color(hex: 0xFAFAFA)
    static let ink = Color(hex: 0x1D1D1F)
    static let inkSecondary = Color(hex: 0x86868B)
    static let hairline = Color(hex: 0x1D1D1F, opacity: 0.14)

    /// The liquid, as it reads on the canvas: a pale lilac wash. Flat, no lighting.
    static let liquid = Color(hex: 0xECDDF7)
    /// Other crews get their own wash.
    static let butter = Color(hex: 0xF4E9CA)
    static let sky = Color(hex: 0xDCE6F3)
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
