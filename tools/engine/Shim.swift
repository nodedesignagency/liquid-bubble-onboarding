import Foundation
// Minimal stand-ins for the SwiftUI types the engine touches.
enum ColorScheme { case light, dark }
struct Color {
    enum RGBColorSpace { case sRGB }
    init(_ space: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double) {}
}
