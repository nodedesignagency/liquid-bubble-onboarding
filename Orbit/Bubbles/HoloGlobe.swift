import SwiftUI
import UIKit

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
    /// How much of the real Earth shows (satellite snapshots on the sphere, see `GlobeImagery`)
    /// instead of the hologram: 1 while the zoom pulls back from the city, dissolving to 0.
    var satellite: Double = 0
    /// The opacity of each of `GlobeImagery.layers` (finest first) at this scale.
    var layerOpacity: [Double] = []
}

/// The globe's colours. Aurora (the default) is the one the user picked from a sheet of six: a dark
/// teal sea, land glowing from aqua to lime, a mint rim and a green aura. The other four are in the
/// hues of the FlightElite onboarding the user liked (its sunset gradient runs royal blue #222EB4,
/// violet #8759F6, orchid #DD92E2, blush #EFB0C3, peach #E7C69D down to plum #571768). Compared in
/// a mock first (`tools/preview/globe.py`). A long press (debug builds, once everyone is in orbit)
/// cycles them, and the choice is remembered.
struct GlobePalette: Equatable {
    let name: String
    let seaTop: UInt32, seaBottom: UInt32, rim: UInt32, land: UInt32
    let sheenA: UInt32, sheenB: UInt32, sheenC: UInt32, aura: UInt32, backlight: UInt32
    let sheenAmount: Float, backlightStrength: Float

    /// A dark teal sea, land glowing from aqua (lower left) to lime (upper right), a mint rim and
    /// glow from below, a green aura. Matched to the user's "aurora" sheet in the mock.
    static let aurora = GlobePalette(name: "Aurora", seaTop: 0x07343B, seaBottom: 0x042127, rim: 0x2FD3A0, land: 0x84EAD6,
                                     sheenA: 0xC8F48A, sheenB: 0x6CDCD8, sheenC: 0x8EEFC0, aura: 0x17B07E, backlight: 0x4BD4A5,
                                     sheenAmount: 0.7, backlightStrength: 1.0)
    /// Royal blue into violet sea, blush-lavender land, a magenta glow from below.
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

    static let all: [GlobePalette] = [.aurora, .dusk, .afterglow, .midnight, .lavender]
    /// Renamed when the default changed to Aurora, so a colourway picked before doesn't stick.
    static let storageKey = "globePalette.2"

    static func named(_ name: String) -> GlobePalette {
        all.first { $0.name == name } ?? .aurora
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
/// at any size, because it is drawn per pixel rather than scaled. While `state.satellite` is above
/// zero it draws `imagery` (the real Earth) on the sphere too.
struct HoloGlobeView: View {
    var state: GlobeState
    var palette: GlobePalette
    /// Seconds, for the sheen's slow drift.
    var time: Double
    var imagery: GlobeImagery? = nil

    private static let land = Image("land-sdf")
    /// Stands in for any snapshot the shader doesn't need this frame.
    private static let blank = Image(uiImage: UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    })

    var body: some View {
        // The snapshots go to the shader only while they show, so the globe at rest stays light.
        let real = state.satellite > 0.001 ? imagery : nil
        let layers = real?.layers ?? []
        let map = real?.worldMap ?? GlobeImagery.Map(u0: 0, uPerRadian: 0, v0: 0, vPerMercator: 0)
        let city = real?.cityRadians ?? CGPoint.zero
        let hasWorld: Float = real?.world == nil ? 0 : 1
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.holoGlobe(
                .image(Self.land),
                .image(real?.world ?? Self.blank),
                .image(Self.image(0, of: layers)),
                .image(Self.image(1, of: layers)),
                .image(Self.image(2, of: layers)),
                .float4(Float(state.center.x), Float(state.center.y), Float(state.radius), Float(state.distance)),
                .float4(Float(state.latitude * .pi / 180), Float(state.longitude * .pi / 180),
                        Float(state.roll * .pi / 180), 0),
                .float4(Float(state.holo), Float(state.glow), Float(state.opacity), Float(time.truncatingRemainder(dividingBy: 1000))),
                .float4(Float(state.satellite), hasWorld, 0, 0),
                .float4(Float(map.u0), Float(map.uPerRadian), Float(map.v0), Float(map.vPerMercator)),
                .float4(Float(city.x), Float(city.y), 0, 0),
                level(0, of: layers),
                level(1, of: layers),
                level(2, of: layers),
                .floatArray(palette.floats)
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static func image(_ index: Int, of layers: [GlobeImagery.Layer]) -> Image {
        index < layers.count ? layers[index].image : blank
    }

    /// A snapshot's place in the shader's `level` arguments: the city's uv, uv per radian, opacity.
    private func level(_ index: Int, of layers: [GlobeImagery.Layer]) -> Shader.Argument {
        guard index < layers.count, index < state.layerOpacity.count else { return .float4(0, 0, 0, 0) }
        let layer = layers[index]
        return .float4(Float(layer.cityUV.x), Float(layer.cityUV.y), Float(layer.uvPerRadian), Float(state.layerOpacity[index]))
    }
}
