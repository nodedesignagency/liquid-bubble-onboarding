import SwiftUI
import UIKit

/// v3's liquid, after the AiOS concept the user shared, made of glass instead of flat colour:
/// everyone sits in a ring of glass, and a neck of glass runs from the one in the middle (Earth, or
/// a friend you tapped) to each of the others, wide where it leaves the middle, thin halfway,
/// flaring into the other's ring. The rings and necks are joined into one outline (the necks meet
/// the rings along their tangents, so it is smooth) and drawn as one shape of Liquid Glass on
/// iOS 26, over the whole screen. Before iOS 26 it is a dark glass outline.
///
/// One shape, not one per ring and neck: separate glass shapes in a container blended together,
/// but each was drawn in a view the size of its own shape, and the blend between them was cut off
/// at those views' edges, as straight lines across the necks (the user saw "sharp cuts").
///
/// Under the glass the page is filled plain: Liquid Glass shows what is behind it, and the dot grid
/// showing through the rings and necks read as dots on top of the photos.
struct WorldGlass: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics
    var size: CGSize

    var body: some View {
        let outline = GlassPart.union(GlassPart.parts(for: bubbles, metrics: metrics))
        ZStack {
            PathShape(path: outline)
                .fill(Theme.worldCanvas)
                .overlay(PathShape(path: outline).stroke(Theme.worldCanvas, lineWidth: 6))
            glass(outline)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glass(_ outline: Path) -> some View {
        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: size.width, height: size.height)
                .glassEffect(.regular, in: PathShape(path: outline))
        } else {
            ZStack {
                PathShape(path: outline).fill(Theme.worldGlass)
                PathShape(path: outline).stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// One piece of the glass: a ring (Earth's, a friend's or a moment's) or a neck from the middle.
struct GlassPart: Identifiable {
    let id: String
    /// Its outline on screen.
    let absolute: Path

    /// A ring for everyone visible (Earth, people and moments), and a neck from the biggest of them
    /// (the one in the middle; while two swap, whoever is bigger at that moment) to each other one
    /// close enough to reach. The bubbles' radii are their glass.
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

/// v3's photos: people 1...9 and the friends' moments (16...39). Earth (0) is the globe.
enum WorldPhoto {
    static func hasPhoto(_ id: Int) -> Bool {
        (1...9).contains(id) || OrbitChoreography.momentIDs.contains(id)
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
        if let moment = OrbitChoreography.moment(id) {
            return moments[(moment.friend - 1) * 4 + moment.index - 1]
        }
        if (1...6).contains(id), let portrait = people[id - 1] { return portrait }
        return Person.samples[(id - 1) % Person.samples.count].photo
    }

    /// v3's own portraits of your six friends, `person-<id>` (v1 and v2 keep `friend-<id>`).
    private static let people: [UIImage?] = (1...6).map { UIImage(named: "person-\($0)") }

    /// Two colours for the glow round someone in the middle, from their photo's background: the
    /// outer band of the circle the photo is cropped to, where the background shows (its top for
    /// the inner colour, its sides for the outer), with a little more colour and light so it glows.
    static func glowColors(for id: Int) -> (inner: Color, outer: Color) {
        if let known = glowCache[id] { return known }
        let colors = measureGlow(image(for: id))
        glowCache[id] = colors
        return colors
    }

    private static var glowCache: [Int: (inner: Color, outer: Color)] = [:]

    private static func measureGlow(_ image: UIImage?) -> (inner: Color, outer: Color) {
        let fallback = (inner: Color(red: 0.6, green: 0.85, blue: 0.8), outer: Color(red: 0.4, green: 0.7, blue: 0.75))
        guard let cgImage = image?.cgImage else { return fallback }
        let n = 24
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return fallback }
        var top = [0.0, 0.0, 0.0], sides = [0.0, 0.0, 0.0]
        var topCount = 0.0, sideCount = 0.0
        for y in 0..<n {
            for x in 0..<n {
                // Row 0 is the image's top.
                let dx = (Double(x) + 0.5) / Double(n) - 0.5, dy = (Double(y) + 0.5) / Double(n) - 0.5
                let r = (dx * dx + dy * dy).squareRoot()
                guard r > 0.36, r < 0.5, dy < 0.15 else { continue }
                let i = (y * n + x) * 4
                let rgb = [Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])].map { $0 / 255 }
                if dy < -0.15 {
                    for c in 0..<3 { top[c] += rgb[c] }
                    topCount += 1
                } else {
                    for c in 0..<3 { sides[c] += rgb[c] }
                    sideCount += 1
                }
            }
        }
        guard topCount > 0, sideCount > 0 else { return fallback }
        return (glowing(top.map { $0 / topCount }), glowing(sides.map { $0 / sideCount }))
    }

    /// A background colour made to glow on the dark page: more saturated, and bright.
    private static func glowing(_ rgb: [Double]) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: Double(min(saturation * 1.4 + 0.08, 1)), brightness: Double(max(brightness, 0.82)))
    }

    /// `moment-<friend>-<n>`: four from each of your six friends' weeks (places, coffee, food).
    private static let moments: [UIImage?] = OrbitChoreography.momentIDs.map { id in
        OrbitChoreography.moment(id).flatMap { UIImage(named: "moment-\($0.friend)-\($0.index)") }
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

    /// The white edge a pin has on the globe, fading as the friend grows into orbit. Popping up or
    /// melting away, it goes by the size the bubble is heading for (or leaving), so a friend budding
    /// out of someone, or shrinking back into Earth, never flashes a pin's edge on the way.
    static func pinEdge(for bubble: RenderedBubble) -> Double {
        let size = bubble.isAppearing || bubble.isVanishing ? bubble.fullRadius : bubble.radius
        return Double(min(max((24 - size) / 8, 0), 1))
    }
}

/// v3: the finger spinning everyone round the middle. Dragging turns everything with the finger
/// (the angle it sweeps round the hub); letting go, it coasts to a stop. The stage turns everyone
/// round the hub by this angle (all but Earth, which is either on the hub or parked in its
/// corner), and the globe turns on its axis with them (`globeAngle`). Tapping someone unwinds it
/// (`settle`), so the friends melting into Earth on its way to the corner meet it where it is.
final class SpinDial {
    /// How long the coast takes to fade, in seconds (it is 95% done after three times this).
    static let coast = 0.55
    /// How long unwinding takes.
    static let settleTime = 0.7

    private var dragging = false
    private var grabbedAngle: Double = 0
    private var sweep: Double = 0
    private var lastFinger: Double = 0
    private var restedAngle: Double = 0
    private var releasedAt: Double?
    private var velocity: Double = 0
    private var settleFrom: Double = 0
    private var settledAt: Double?
    /// Whole turns taken off by `settle`, kept for the globe so it doesn't spin back with them.
    private var unwound: Double = 0

    /// Radians, positive is clockwise on screen.
    func angle(at time: Double) -> Double {
        if dragging { return grabbedAngle + sweep }
        if let settledAt, time - settledAt < Self.settleTime {
            let x = min(max((time - settledAt) / Self.settleTime, 0), 1)
            return settleFrom * (1 - x * x * (3 - 2 * x))
        }
        guard let start = releasedAt else { return restedAngle }
        let elapsed = max(0, time - start)
        return restedAngle + velocity * Self.coast * (1 - exp(-elapsed / Self.coast))
    }

    /// What the globe turns by: the same, without the whole turns `settle` took off.
    func globeAngle(at time: Double) -> Double {
        angle(at: time) + unwound
    }

    /// `finger` is the finger's angle around Earth (radians, clockwise on screen).
    func drag(finger: Double, at time: Double) {
        if !dragging {
            grabbedAngle = angle(at: time)
            settledAt = nil
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
        settledAt = nil
        dragging = false
    }

    /// Unwinds to no turn at all, the short way round.
    func settle(at time: Double) {
        let current = angle(at: time)
        let turns = (current / (2 * .pi)).rounded()
        unwound += turns * 2 * .pi
        settleFrom = current - turns * 2 * .pi
        settledAt = time
        restedAngle = 0
        releasedAt = nil
        velocity = 0
        dragging = false
    }
}
