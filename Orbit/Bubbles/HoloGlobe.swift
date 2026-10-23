import SwiftUI

/// Everything that places and styles v3's globe on screen. See `GlobeMath` for the geometry.
struct GlobeState: Equatable {
    /// The globe's centre and the radius of its edge, in screen points.
    var center: CGPoint
    var radius: CGFloat
    /// The camera's distance from Earth's centre, in Earth radii: close is a wide, curved view of
    /// a region, far is the whole globe nearly flat-on.
    var distance: Double
    /// The point facing you, in degrees.
    var latitude: Double
    var longitude: Double
    /// Turned on screen, clockwise, in degrees (matching a map whose heading isn't north).
    var roll: Double = 0
    /// How strong the continents' sheen is (0 plain, 1 full), how strong the aura is, and the whole
    /// thing's opacity.
    var holo: Double = 1
    var glow: Double = 1
    var opacity: Double = 1
    /// The globe shows only inside this circle (screen points), with a glowing ring at its edge:
    /// it sweeps out over the satellite imagery from the city. Nil shows all of it.
    var reveal: (center: CGPoint, radius: CGFloat)? = nil

    static func == (a: GlobeState, b: GlobeState) -> Bool {
        a.center == b.center && a.radius == b.radius && a.distance == b.distance && a.latitude == b.latitude
            && a.longitude == b.longitude && a.roll == b.roll && a.holo == b.holo && a.glow == b.glow
            && a.opacity == b.opacity && a.reveal?.center == b.reveal?.center && a.reveal?.radius == b.reveal?.radius
    }
}

/// The globe's colours, four versions in the hues of the FlightElite onboarding the user liked
/// (its sunset gradient runs royal blue #222EB4, violet #8759F6, orchid #DD92E2, blush #EFB0C3,
/// peach #E7C69D down to plum #571768), compared side by side in a mock (`tools/preview/globe.py`).
/// A long press on the globe (debug builds) cycles them, and the choice is remembered.
struct GlobePalette: Equatable {
    let name: String
    let seaTop: UInt32, seaBottom: UInt32, rim: UInt32, land: UInt32
    let sheenA: UInt32, sheenB: UInt32, sheenC: UInt32, aura: UInt32, backlight: UInt32
    let sheenAmount: Float, backlightStrength: Float

    /// Royal blue into violet sea, blush-lavender land, a magenta glow from below: the closest to
    /// the reference's globe.
    static let dusk = GlobePalette(name: "Dusk", seaTop: 0x222EB4, seaBottom: 0x5C49F5, rim: 0xA88BFF, land: 0xEAE4FF,
                                   sheenA: 0xBB73F7, sheenB: 0xEFB0C3, sheenC: 0x8CADEF, aura: 0x7B4DF5, backlight: 0xDD92E2,
                                   sheenAmount: 0.55, backlightStrength: 1.1)
    /// Warmer: peach and blush land, like the gradient's warm band.
    static let afterglow = GlobePalette(name: "Afterglow", seaTop: 0x3A44E3, seaBottom: 0x8759F6, rim: 0xDD92E2, land: 0xFFE9E4,
                                        sheenA: 0xEFB0C3, sheenB: 0xE7C69D, sheenC: 0xDD92E2, aura: 0xBB73F7, backlight: 0xE7C69D,
                                        sheenAmount: 0.8, backlightStrength: 1.2)
    /// Deeper: a royal-to-plum sea, lilac land, a magenta rim.
    static let midnight = GlobePalette(name: "Midnight bloom", seaTop: 0x1A1F7A, seaBottom: 0x571768, rim: 0xBB73F7, land: 0xCDBDFF,
                                       sheenA: 0xDD92E2, sheenB: 0x8759F6, sheenC: 0x8CADEF, aura: 0x9B3DF0, backlight: 0xC843DB,
                                       sheenAmount: 0.6, backlightStrength: 1.25)
    /// Lighter: a bright violet sea, white-pink land.
    static let lavender = GlobePalette(name: "Lavender sky", seaTop: 0x5C49F5, seaBottom: 0xBB73F7, rim: 0xEFB0C3, land: 0xFFF4FA,
                                       sheenA: 0xEFB0C3, sheenB: 0xFFFFFF, sheenC: 0xDD92E2, aura: 0x8759F6, backlight: 0xEFB0C3,
                                       sheenAmount: 0.5, backlightStrength: 0.9)

    static let all: [GlobePalette] = [.dusk, .afterglow, .midnight, .lavender]
    static let storageKey = "globePalette"

    static func named(_ name: String) -> GlobePalette {
        all.first { $0.name == name } ?? .dusk
    }

    /// The next one, for the long press.
    var next: GlobePalette {
        let index = Self.all.firstIndex(of: self) ?? 0
        return Self.all[(index + 1) % Self.all.count]
    }

    /// The 29 floats `holoGlobe` reads.
    var floats: [Float] {
        func rgb(_ hex: UInt32) -> [Float] {
            [Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255]
        }
        return [seaTop, seaBottom, rim, land, sheenA, sheenB, sheenC, aura, backlight].flatMap(rgb)
            + [sheenAmount, backlightStrength]
    }
}

/// v3's globe: the `holoGlobe` shader over the whole stage, so its aura can spread past it. Sharp
/// at any size, because it is drawn per pixel rather than scaled.
struct HoloGlobeView: View {
    var state: GlobeState
    var palette: GlobePalette
    /// Seconds, for the sheen's slow drift.
    var time: Double

    private static let land = Image("land-sdf")

    var body: some View {
        let reveal = state.reveal
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.holoGlobe(
                .image(Self.land),
                .float4(Float(state.center.x), Float(state.center.y), Float(state.radius), Float(state.distance)),
                .float4(Float(state.latitude * .pi / 180), Float(state.longitude * .pi / 180),
                        Float(state.roll * .pi / 180), 0),
                .float4(Float(state.holo), Float(state.glow), Float(state.opacity), Float(time.truncatingRemainder(dividingBy: 1000))),
                .float4(Float(reveal?.center.x ?? 0), Float(reveal?.center.y ?? 0), Float(reveal?.radius ?? 1_000_000),
                        Float(max(28, (reveal?.radius ?? 0) * 0.12))),
                .floatArray(palette.floats)
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
