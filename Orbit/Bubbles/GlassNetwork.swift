import SwiftUI
import UIKit

/// v3's liquid, after the AiOS concept the user shared, made of glass instead of flat colour:
/// everyone sits in a ring of glass, and a neck of glass runs from the one in the middle (Earth, or
/// a friend you tapped) to each of the others, wide where it leaves the middle, thin halfway,
/// flaring into the other's ring. On iOS 26 it is real Liquid Glass: every ring and neck is a glass
/// shape inside one `GlassEffectContainer`, so they render as one body. Before iOS 26 it is a dark
/// glass outline.
///
/// Under the glass the page is filled plain: Liquid Glass shows what is behind it, and the dot grid
/// showing through the rings and necks read as dots on top of the photos.
struct WorldGlass: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics
    var size: CGSize

    var body: some View {
        let parts = GlassPart.parts(for: bubbles, metrics: metrics)
        ZStack {
            ForEach(parts) { part in
                PathShape(path: part.absolute)
                    .fill(Theme.worldCanvas)
                    .overlay(PathShape(path: part.absolute).stroke(Theme.worldCanvas, lineWidth: 6))
            }
            glass(parts)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glass(_ parts: [GlassPart]) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    ZStack {
                        ForEach(parts) { part in
                            Rectangle()
                                .fill(Color.white.opacity(0.001))
                                .frame(width: part.bounds.width, height: part.bounds.height)
                                .glassEffect(.regular, in: PathShape(path: part.local))
                                .position(x: part.bounds.midX, y: part.bounds.midY)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
            } else {
                let outline = GlassPart.union(parts)
                ZStack {
                    outline.fill(Theme.worldGlass)
                    outline.stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }
}

/// One glass shape: a ring (Earth's or a friend's) or a neck between Earth and a friend.
struct GlassPart: Identifiable {
    let id: String
    /// Where it is on screen.
    let bounds: CGRect
    /// Its outline, relative to `bounds`.
    let local: Path
    /// Its outline on screen.
    let absolute: Path

    init(id: String, absolute: Path) {
        self.id = id
        self.absolute = absolute
        let box = absolute.boundingRect
        bounds = box
        local = absolute.offsetBy(dx: -box.minX, dy: -box.minY)
    }

    /// A ring for everyone visible (Earth and people), and a neck from the biggest of them (the one
    /// in the middle; while two swap, whoever is bigger at that moment) to each other one close
    /// enough to reach. The bubbles' radii are their glass.
    static func parts(for bubbles: [RenderedBubble], metrics: StageMetrics) -> [GlassPart] {
        let shown = bubbles.filter { $0.radius > 0.5 && ($0.id == OrbitChoreography.earth || WorldPhoto.hasPhoto($0.id)) }
        guard let hub = shown.max(by: { $0.radius < $1.radius }) else { return [] }
        let hubCenter = metrics.point(hub.center)
        let hubRadius = hub.radius * metrics.scale
        var parts: [GlassPart] = []
        for bubble in shown {
            let center = metrics.point(bubble.center)
            let radius = bubble.radius * metrics.scale
            parts.append(GlassPart(id: "ring-\(bubble.id)", absolute: circle(center, radius)))
            guard bubble.id != hub.id else { continue }
            if let neck = GlassNeck.path(from: hubCenter, hubRadius, to: center, radius) {
                parts.append(GlassPart(id: "neck-\(bubble.id)", absolute: neck))
            }
        }
        return parts
    }

    static func union(_ parts: [GlassPart]) -> Path {
        guard var outline = parts.first?.absolute else { return Path() }
        for part in parts.dropFirst() {
            outline = outline.union(part.absolute)
        }
        return outline
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// A shape that is just a fixed path.
struct PathShape: Shape {
    var path: Path

    func path(in rect: CGRect) -> Path { path }
}

/// The classic gooey connector between two circles (as in metaball drawings): two curves leaving
/// the first circle and landing on the second, thinning as the circles part and gone once they
/// are more than 2.5 of the second's radii apart. Union it with the two circles.
/// Mirrored in `tools/preview/render_v3.py` (`neck`).
enum GlassNeck {
    static func path(from c1: CGPoint, _ r1: CGFloat, to c2: CGPoint, _ r2: CGFloat,
                     spread v: CGFloat = 0.45, handle: CGFloat = 2.4) -> Path? {
        let d = hypot(c2.x - c1.x, c2.y - c1.y)
        guard r1 > 0.5, r2 > 0.5, d <= r1 + r2 * 2.5, d > abs(r1 - r2) else { return nil }
        func clamped(_ x: CGFloat) -> CGFloat { min(max(x, -1), 1) }
        var u1: CGFloat = 0, u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(clamped((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d)))
            u2 = acos(clamped((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d)))
        }
        let angle = atan2(c2.y - c1.y, c2.x - c1.x)
        let maxSpread = acos(clamped((r1 - r2) / d))
        let a1 = angle + u1 + (maxSpread - u1) * v
        let a2 = angle - u1 - (maxSpread - u1) * v
        let a3 = angle + .pi - u2 - (.pi - u2 - maxSpread) * v
        let a4 = angle - .pi + u2 + (.pi - u2 - maxSpread) * v
        func at(_ c: CGPoint, _ a: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        let p1 = at(c1, a1, r1), p2 = at(c1, a2, r1), p3 = at(c2, a3, r2), p4 = at(c2, a4, r2)
        let total = r1 + r2
        let d2 = min(v * handle, hypot(p3.x - p1.x, p3.y - p1.y) / total) * min(1, d * 2 / total)
        let h1 = at(p1, a1 - .pi / 2, r1 * d2), h2 = at(p2, a2 + .pi / 2, r1 * d2)
        let h3 = at(p3, a3 + .pi / 2, r2 * d2), h4 = at(p4, a4 - .pi / 2, r2 * d2)
        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: h1, control2: h3)
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: h4, control2: h2)
        // Back through the first circle's middle: inside the circle, so the union stays clean.
        path.addLine(to: c1)
        path.closeSubpath()
        return path
    }
}

/// v3's photos: people 1...9. Earth (0) is the globe.
enum WorldPhoto {
    static func hasPhoto(_ id: Int) -> Bool {
        (1...9).contains(id)
    }

    /// A photo inside a ring of glass of radius `glass`: 5 points of glass, less on a small pin.
    static func photoRadius(glass: CGFloat) -> CGFloat {
        glass - min(5, glass * 0.15)
    }

    /// The globe inside Earth's glass, in reference points: the same proportion as at rest
    /// (84 in 91). While Earth's glass seeps out or drains away, the globe keeps its full size.
    static func globeRadius(for earth: RenderedBubble) -> CGFloat {
        let glass = earth.isAppearing || earth.isVanishing ? earth.fullRadius : earth.radius
        return glass * OrbitChoreography.globeRadius / OrbitChoreography.bloomEarth.radius
    }

    static func image(for id: Int) -> UIImage? {
        Person.samples[(id - 1) % Person.samples.count].photo
    }

    /// How big the photo is drawn, in reference points: inside its ring of glass. Appearing, it pops
    /// in once the bubble has swollen to 30% of its full size, overshooting with its bounce (capped
    /// at 12%); melting away, it is gone before the glass is. Otherwise (a pin growing into orbit)
    /// it simply grows with its glass.
    static func radius(for bubble: RenderedBubble) -> CGFloat {
        guard bubble.isAppearing || bubble.isLeaving else {
            return photoRadius(glass: bubble.radius)
        }
        guard bubble.fullRadius > 0.5 else { return 0 }
        let grown = bubble.radius / bubble.fullRadius
        return photoRadius(glass: bubble.fullRadius) * min(max((grown - 0.3) / 0.7, 0), 1.12)
    }

    /// The white edge a pin has on the globe, fading as the friend grows into orbit.
    static func pinEdge(for bubble: RenderedBubble) -> Double {
        Double(min(max((24 - bubble.radius) / 8, 0), 1))
    }
}

/// v3: the finger spinning everyone round the middle. Dragging turns everything with the finger
/// (the angle it sweeps round the hub); letting go, it coasts to a stop. The stage turns everyone
/// round the hub by this angle, and the globe turns on its axis with them.
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
