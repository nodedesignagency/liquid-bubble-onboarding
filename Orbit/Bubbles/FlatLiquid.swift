import SwiftUI
import UIKit

/// v3's look: one crisp body of flat, pale liquid, with each photo a sharp disc sitting in it,
/// like the pentagon in the Yandex Music concept the user circled. No blur and no glass on the
/// liquid itself: Earth, in the middle, is the one glass thing on screen.
///
/// The liquid is drawn by the `flatLiquid` shader (`Liquid.metal`): every bubble is a circle a
/// little larger than its photo, joined to its neighbours with a smooth minimum, so a bubble
/// budding out of another swells out of its edge with a wide neck that thins and pinches off.
struct FlatLiquidLayer: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics

    /// How wide the fillets between neighbours are, in reference points: two shapes join when the
    /// gap between their edges is under about half of this.
    static let blend: CGFloat = 38
    /// How much the liquid darkens just inside its edge (0 is perfectly flat).
    static let rim: Float = 1

    /// A bubble's liquid: past the photo by `OrbitChoreography.photoMargin`. Earth's radius already
    /// is its pool (the globe sits inside it), and drops are only liquid.
    static func liquidRadius(_ bubble: RenderedBubble) -> CGFloat {
        WorldPhoto.hasPhoto(bubble.id) ? bubble.radius * (1 + OrbitChoreography.photoMargin) : bubble.radius
    }

    var body: some View {
        let circles = circles
        if circles.isEmpty {
            Color.clear
        } else {
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.flatLiquid(
                    .float(Float(Self.blend * metrics.scale)),
                    .float(Self.rim),
                    .float3(Theme.worldLiquidRGB.r, Theme.worldLiquidRGB.g, Theme.worldLiquidRGB.b),
                    .floatArray(circles)
                ))
        }
    }

    /// Three floats per bubble, as `flatLiquid` reads them: x, y, radius, in screen points.
    private var circles: [Float] {
        var out: [Float] = []
        out.reserveCapacity(bubbles.count * 3)
        for bubble in bubbles where bubble.radius > 0.5 {
            let c = metrics.point(bubble.center)
            out += [Float(c.x), Float(c.y), Float(Self.liquidRadius(bubble) * metrics.scale)]
        }
        return out
    }
}

/// v3's photos: friends (1...9) and places (16...20). Earth (0) is the live map, drops have none.
enum WorldPhoto {
    static func hasPhoto(_ id: Int) -> Bool {
        (1...9).contains(id) || OrbitChoreography.places.contains(id)
    }

    static func image(for id: Int) -> UIImage? {
        if OrbitChoreography.places.contains(id) {
            return places[id - OrbitChoreography.places.lowerBound]
        }
        return Person.samples[(id - 1) % Person.samples.count].photo
    }

    private static let places: [UIImage?] = (1...5).map { UIImage(named: "place-\($0)") }

    /// How big the photo is drawn for a bubble of this size: it waits until its liquid has
    /// swollen to 30% of the bubble's full size, then pops in, overshooting with the bubble's own
    /// bounce (capped at 12%). Melting away, it is gone before the liquid is.
    static func radius(for bubble: RenderedBubble) -> CGFloat {
        guard bubble.fullRadius > 0.5 else { return 0 }
        let grown = bubble.radius / bubble.fullRadius
        return bubble.fullRadius * min(max((grown - 0.3) / 0.7, 0), 1.12)
    }
}

/// v3: the finger spinning the bloom around Earth, like the reference's "spin phone". Dragging
/// turns everything with the finger (the angle it sweeps around Earth); letting go, it coasts to a
/// stop. The stage turns every bubble around Earth by this angle, and the map turns the globe.
final class SpinDial {
    /// How long the coast takes to fade, in seconds (it is 95% done after three times this).
    static let coast = 0.55

    private var dragging = false
    private var grabbedAngle: Double = 0
    private var sweep: Double = 0
    private var lastFinger: Double = 0
    private var restedAngle: Double = 0
    private var releasedAt: Double?
    private var velocity: Double = 0

    /// Radians, positive is clockwise on screen.
    func angle(at time: Double) -> Double {
        if dragging { return grabbedAngle + sweep }
        guard let start = releasedAt else { return restedAngle }
        let elapsed = max(0, time - start)
        return restedAngle + velocity * Self.coast * (1 - exp(-elapsed / Self.coast))
    }

    /// Where it comes to rest after the last release.
    var finalAngle: Double { restedAngle + velocity * Self.coast }

    /// `finger` is the finger's angle around Earth (radians, clockwise on screen).
    func drag(finger: Double, at time: Double) {
        if !dragging {
            grabbedAngle = angle(at: time)
            sweep = 0
            lastFinger = finger
            dragging = true
        }
        // Unwrapped, so circling past the left side doesn't jump a whole turn.
        var delta = finger - lastFinger
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        sweep += delta
        lastFinger = finger
    }

    /// `velocity` is the finger's angular speed around Earth when it let go, radians per second.
    func release(velocity: Double, at time: Double) {
        restedAngle = grabbedAngle + sweep
        self.velocity = min(max(velocity, -7), 7)
        releasedAt = time
        dragging = false
    }
}
