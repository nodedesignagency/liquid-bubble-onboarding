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
    /// How holographic the continents are (0 pearl, 1 full sheen), how strong the aura is, and
    /// the whole thing's opacity.
    var holo: Double = 1
    var glow: Double = 1
    var opacity: Double = 1
}

/// v3's globe: the `holoGlobe` shader over the whole stage, so its aura can spread past it. Sharp
/// at any size, because it is drawn per pixel rather than scaled.
struct HoloGlobeView: View {
    var state: GlobeState
    /// Seconds, for the sheen's slow drift.
    var time: Double

    private static let land = Image("land-sdf")

    var body: some View {
        Rectangle()
            .fill(.white)
            .colorEffect(ShaderLibrary.holoGlobe(
                .image(Self.land),
                .float4(Float(state.center.x), Float(state.center.y), Float(state.radius), Float(state.distance)),
                .float4(Float(state.latitude * .pi / 180), Float(state.longitude * .pi / 180),
                        Float(state.roll * .pi / 180), 0),
                .float4(Float(state.holo), Float(state.glow), Float(state.opacity), Float(time.truncatingRemainder(dividingBy: 1000)))
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
