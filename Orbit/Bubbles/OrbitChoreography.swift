import Foundation
import CoreGraphics

/// The story the bubbles tell, one scene per onboarding page.
///
/// v1 (the first story, lilac liquid): `you`, `bump`, `circle`, `world`, then `collapse`.
/// v2 (one screen, glass orbs that are the liquid themselves, no threads): `gate`, swipe up,
/// `reveal`, and after "Continue" back to `gate`, so a recording loops.
/// v3 (pull back from a city to a glowing globe, friends pinned on it lift off into orbit, joined
/// by liquid glass): `space` while the map zooms out, `pins`, `bloom`, and `space` again after
/// "Continue".
enum OrbitScene: Hashable {
    // MARK: v3

    /// Nothing on the stage: the map and the zoom have the screen, and everyone waits inside Earth.
    /// After "Continue" everyone melts back into Earth.
    case space
    /// Earth's glass seeps out from under the globe and friends pop up as pins on their cities.
    case pins
    /// The friends lift off into orbit round Earth, joined to it by necks of liquid glass.
    case bloom

    // MARK: v2

    /// The gate: Earth as a big glass dome rising from the bottom edge, everyone still inside it.
    /// Swiping up lifts it (see `EarthLift`); letting go far enough plays `reveal`.
    case gate
    /// Earth flies up and shrinks into a small glass orb, stretching like a drop of liquid glass as
    /// it goes, and your friends bubble out of its surface into a floating cluster above it.
    case reveal

    // MARK: v1

    /// One bubble, you, alive in the middle.
    case you
    /// A friend drifts in and collides with you; you fuse, then pull apart still joined by a thread.
    case bump
    /// Friends bud out of each of you, every one tethered by a thread of liquid.
    case circle
    /// Everything drains into one drop that swells into Earth, friends clinging to its rim.
    case world
    /// Everything melts back into Earth, which shrinks to nothing.
    case collapse
}

/// A layout and when to start moving toward it, counted from the moment the scene starts.
struct Keyframe {
    let after: Double
    let layout: BubbleLayout
}

/// Bubble positions for every `OrbitScene`.
///
/// Bubble 0 is Earth, 1 is you, 2 is the friend you bump, 3...5 are your friends, 6...8 are
/// theirs and 9 is one more for the ring. v2 also uses 10...15, small clear glass droplets with no
/// photo. v3 uses Earth and 1...4. Coordinates are in the stage's
/// 372 x 480 reference space, centered on the middle of the stage (v2's stage is the whole screen,
/// so its coordinates reach about 400 above and below the centre).
enum OrbitChoreography {
    static let bubbleCount = 16
    /// v2: photo-less glass droplets.
    static let droplets = 10...15

    static func hasPhoto(_ id: Int) -> Bool { id >= 0 && id <= 9 }
    static let earth = 0
    static let you = 1
    static let friend = 2

    static func keyframes(for scene: OrbitScene) -> [Keyframe] {
        switch scene {
        case .you: [Keyframe(after: 0, layout: alone)]
        case .bump: [Keyframe(after: 0, layout: collide), Keyframe(after: 1.5, layout: tethered)]
        case .circle: [Keyframe(after: 0, layout: circle)]
        case .world: [Keyframe(after: 0, layout: drop), Keyframe(after: 1.1, layout: world)]
        case .collapse: [Keyframe(after: 0, layout: collapse)]
        case .gate: [Keyframe(after: 0, layout: gate)]
        case .reveal: [Keyframe(after: 0, layout: reveal)]
        case .space: [Keyframe(after: 0, layout: space)]
        case .pins: [Keyframe(after: 0, layout: pins)]
        case .bloom: [Keyframe(after: 0, layout: bloom)]
        }
    }

    // MARK: v3 scenes

    /// Where Earth sits once the zoom has pulled back to it, and how big its glass is (the globe,
    /// `globeRadius`, sits inside, leaving a ring of glass round it).
    static let bloomEarth = (center: CGPoint(x: 0, y: -120), radius: CGFloat(91))
    static let globeRadius: CGFloat = 84
    /// The globe at rest: the point facing you, and how far away the camera is in Earth radii
    /// (far enough to be nearly flat-on, close enough for a touch of depth).
    static let globeView = (latitude: 25.0, longitude: 12.0, distance: 9.0)

    /// v3's friends: a photo inside a ring of glass. A pin on the globe is small, with a white edge;
    /// in orbit it is full size. The radius here is the glass; the photo is `photoFraction` of it.
    static let friendRadius: CGFloat = 33
    static let pinRadius: CGFloat = 14
    static let photoFraction: CGFloat = 28.0 / 33.0
    static let orbitDistance: CGFloat = 150

    /// Four friends, each pinned where they live, then in orbit at a corner around Earth, on the
    /// side their city is on (angle in degrees, 0 to the right, clockwise).
    static let friendHomes: [(id: Int, latitude: Double, longitude: Double, slot: Double)] = [
        (1, 51.51, -0.13, -135),   // London
        (2, 25.20, 55.27, -45),    // Dubai
        (3, -1.29, 36.82, 45),     // Nairobi
        (4, 6.52, 3.38, 135),      // Lagos
    ]

    /// Where a friend's pin sits on the globe at rest, in reference points.
    static func pinCenter(latitude: Double, longitude: Double) -> CGPoint {
        let face = GlobeMath.project(latitude: latitude, longitude: longitude, facing: globeView.latitude,
                                     globeView.longitude, distance: globeView.distance)
        return CGPoint(x: bloomEarth.center.x + face.x * globeRadius, y: bloomEarth.center.y + face.y * globeRadius)
    }

    /// Nothing on the stage while the map and the zoom have the screen; everyone waits inside
    /// Earth, Earth hidden at its own place. After "Continue" everyone melts back into it, then its
    /// glass drains under the globe.
    private static var space: BubbleLayout {
        var targets = (0..<bubbleCount).map { _ in BubbleTarget(anchor: earth) }
        targets[earth] = BubbleTarget(center: bloomEarth.center, moveDelay: 0.55)
        return BubbleLayout(targets: targets)
    }

    /// Earth's glass seeps out from under the globe, and each friend pops up as a pin on their city.
    private static var pins: BubbleLayout {
        var targets = space.targets
        targets[earth] = BubbleTarget(center: bloomEarth.center, radius: bloomEarth.radius)
        for (order, home) in friendHomes.enumerated() {
            targets[home.id] = BubbleTarget(
                center: pinCenter(latitude: home.latitude, longitude: home.longitude),
                radius: pinRadius,
                appearDelay: 0.15 + 0.14 * Double(order),
                jelly: true,
                popsInPlace: true
            )
        }
        return BubbleLayout(targets: targets)
    }

    /// The friends lift off their cities into orbit round Earth, a neck of liquid glass stretching
    /// from Earth to each, and keep bobbing gently so the necks breathe.
    private static var bloom: BubbleLayout {
        var targets = pins.targets
        for (order, home) in friendHomes.enumerated() {
            let radians = home.slot * .pi / 180
            let spot = CGPoint(x: bloomEarth.center.x + orbitDistance * CGFloat(cos(radians)),
                               y: bloomEarth.center.y + orbitDistance * CGFloat(sin(radians)))
            let phase = Double(order) * 1.9
            let bob: CGFloat = 4
            targets[home.id] = BubbleTarget(
                center: CGPoint(x: spot.x + bob * CGFloat(cos(phase)), y: spot.y + bob * CGFloat(sin(phase))),
                radius: friendRadius,
                moveDelay: 0.1 * Double(order),
                jelly: true,
                orbitRate: order.isMultiple(of: 2) ? 0.5 : -0.43,
                orbitCenter: spot
            )
        }
        return BubbleLayout(targets: targets)
    }

    // MARK: v2 scenes

    /// Where Earth sits as the gate's dome: mostly below the bottom edge, its top at about 70% of
    /// the screen's height.
    private static let dome = (center: CGPoint(x: 0, y: 425), radius: CGFloat(222))
    /// Earth after the reveal: a small orb above the title.
    private static let orb = (center: CGPoint(x: 0, y: -44), radius: CGFloat(30))

    /// Everyone tucked inside Earth, so they all bud out of it, and melt back into it.
    private static func insideEarth() -> [BubbleTarget] {
        (0..<bubbleCount).map { id in id == earth ? BubbleTarget() : BubbleTarget(anchor: earth) }
    }

    private static var gate: BubbleLayout {
        var targets = insideEarth()
        targets[earth] = BubbleTarget(center: dome.center, radius: dome.radius, appearDelay: 0.1, jelly: true)
        return BubbleLayout(targets: targets)
    }

    /// Earth flies up into a small orb with a bounce, stretching like a drop as it goes (the glass
    /// stretches along its motion, see `GlassLiquidLayer`), then friends and droplets bubble out
    /// of its top one after another and float into a
    /// cluster above, each bobbing gently on a small circle of its own, so neighbours keep melting
    /// into each other and letting go.
    private static var reveal: BubbleLayout {
        var targets = insideEarth()
        targets[earth] = BubbleTarget(center: orb.center, radius: orb.radius, jelly: true)

        // (x, y, radius), drawn into a cluster around its middle; order is the order they bud in.
        let middle = CGPoint(x: 0, y: -205)
        let spots: [(Int, CGFloat, CGFloat, CGFloat)] = [
            (1, 0, -150, 44), (3, 80, -212, 36), (2, -78, -205, 34), (5, 108, -132, 30),
            (4, -112, -128, 28), (6, -20, -262, 26), (7, 46, -280, 22), (9, 150, -250, 22),
            (8, -150, -230, 20),
            (10, -62, -104, 9), (11, 66, -98, 7), (12, -128, -300, 10), (13, 126, -318, 8),
            (14, 2, -334, 12), (15, 32, -112, 5),
        ]
        for (order, spot) in spots.enumerated() {
            let (id, x, y, r) = spot
            // Pulled in toward the middle, so close neighbours just touch.
            let home = CGPoint(x: middle.x + (x - middle.x) * 0.85, y: middle.y + (y - middle.y) * 0.85)
            let phase = Double(order) * 2.4
            let bob: CGFloat = r < 15 ? 7 : 5
            targets[id] = BubbleTarget(
                center: CGPoint(x: home.x + bob * CGFloat(cos(phase)), y: home.y + bob * CGFloat(sin(phase))),
                radius: r,
                appearDelay: 0.75 + 0.11 * Double(order),
                jelly: true,
                orbitRate: order.isMultiple(of: 2) ? 0.5 : -0.42,
                orbitCenter: home,
                budsFromSurface: true
            )
        }
        return BubbleLayout(targets: targets)
    }

    // MARK: v1 scenes

    // MARK: Scenes

    private static var alone: BubbleLayout {
        var targets = tucked()
        targets[you] = BubbleTarget(center: CGPoint(x: 0, y: 10), radius: 88, appearDelay: 0.1)
        // Waiting just off the right edge for the next page.
        targets[friend] = BubbleTarget(center: CGPoint(x: 340, y: 20), radius: 62)
        return BubbleLayout(targets: targets)
    }

    /// The friend glides in and squashes into you.
    private static var collide: BubbleLayout {
        var targets = tucked()
        targets[you] = BubbleTarget(center: CGPoint(x: -60, y: 10), radius: 74, jelly: true)
        targets[friend] = BubbleTarget(center: CGPoint(x: 64, y: 10), radius: 60, jelly: true)
        return BubbleLayout(targets: targets)
    }

    /// You drift apart, and the liquid between you stretches into a thread instead of breaking.
    private static var tethered: BubbleLayout {
        var targets = tucked()
        targets[you] = BubbleTarget(center: CGPoint(x: -84, y: -30), radius: 66)
        targets[friend] = BubbleTarget(center: CGPoint(x: 88, y: 56), radius: 54)
        return BubbleLayout(targets: targets, threads: [LiquidThread(a: you, b: friend)])
    }

    private static var circle: BubbleLayout {
        let youCenter = CGPoint(x: -34, y: -66)
        let friendCenter = CGPoint(x: 62, y: 72)
        // (parent, angle around the parent in degrees with 0 right and clockwise, distance, radius, bud delay)
        // Packed like the reference: each bud sits close enough that its liquid merges with its parent's.
        let buds: [(Int, Double, CGFloat, CGFloat, Double)] = [
            (you, -112, 104, 42, 0.5),
            (you, -168, 102, 40, 0.7),
            (you, -42, 106, 40, 0.9),
            (friend, 24, 94, 38, 0.6),
            (friend, 78, 96, 40, 0.8),
            (friend, 138, 94, 38, 1.0),
        ]

        var targets = tucked()
        targets[you] = BubbleTarget(center: youCenter, radius: 58)
        targets[friend] = BubbleTarget(center: friendCenter, radius: 50)
        var threads = [LiquidThread(a: you, b: friend)]
        for (i, bud) in buds.enumerated() {
            let parentCenter = bud.0 == you ? youCenter : friendCenter
            let offset = polar(bud.2, bud.1)
            targets[3 + i] = BubbleTarget(
                center: CGPoint(x: parentCenter.x + offset.x, y: parentCenter.y + offset.y),
                radius: bud.3,
                appearDelay: bud.4
            )
            // Forms as the bud would snap free, so its neck stretches into the thread.
            threads.append(LiquidThread(a: bud.0, b: 3 + i, delay: bud.4 + 0.25))
        }
        return BubbleLayout(targets: targets, threads: threads)
    }

    /// Every bubble drains into the middle and melts into one small drop.
    private static var drop: BubbleLayout {
        var targets = (0..<bubbleCount).map { id in
            BubbleTarget(anchor: earth, moveDelay: 0.04 * Double(id % 4))
        }
        targets[earth] = BubbleTarget(radius: 12, appearDelay: 0.3)
        return BubbleLayout(targets: targets)
    }

    /// The drop blooms into the ring: nine glass orbs, evenly spaced with a 2pt gap between
    /// neighbours (like the reference's photos), one liquid around them and nothing in the middle.
    /// Ring radius and orb size keep the reference's outer edge and band thickness.
    private static var world: BubbleLayout {
        let orbRadius: CGFloat = 40.7      // 44pt on screen
        let ringRadius: CGFloat = 121.8    // neighbours 2pt apart on screen
        var targets = tucked()
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.2)
        for i in 0..<9 {
            targets[1 + i] = BubbleTarget(
                center: polar(ringRadius, -90 + 40 * Double(i)),
                radius: orbRadius,
                appearDelay: 0.25 + 0.06 * Double(i)
            )
        }
        return BubbleLayout(targets: targets, spin: 0.04)
    }

    private static var collapse: BubbleLayout {
        var targets = (0..<bubbleCount).map { id in
            BubbleTarget(anchor: earth, moveDelay: 0.03 * Double(id))
        }
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.5)
        return BubbleLayout(targets: targets)
    }

    // MARK: Helpers

    /// The liquid's reach beyond a photo's edge, in reference points, to the middle of its soft
    /// edge: 9.7 on a big photo, so the band around the ring is as thick as the reference's, tapering
    /// away for tiny ones so they grow out of their parent smoothly.
    static func haloWidth(_ radius: CGFloat) -> CGFloat {
        min(9.7, 2 + radius * 0.19)
    }

    /// Each bubble tucked inside the one it grows out of: your friends inside you, your friend's inside them.
    private static func tucked() -> [BubbleTarget] {
        (0..<bubbleCount).map { id in
            switch id {
            case earth: BubbleTarget()
            case 3...5: BubbleTarget(anchor: you)
            case 6...8: BubbleTarget(anchor: friend)
            default: BubbleTarget(anchor: earth)
            }
        }
    }

    private static func polar(_ distance: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: distance * CGFloat(cos(radians)), y: distance * CGFloat(sin(radians)))
    }
}

/// The globe's geometry, shared by the `holoGlobe` shader (`Liquid.metal`), `HoloGlobeView` and the
/// pins: a unit sphere seen by a pinhole camera `distance` Earth radii from its centre, turned so
/// the point at (`latitude`, `longitude`) faces the camera, north up. Screen y points down.
enum GlobeMath {
    /// Where a point on Earth lands on screen, relative to the globe's centre, in units of the
    /// globe's on-screen radius; `visible` is false on the far side.
    static func project(latitude: Double, longitude: Double, facing latitude0: Double, _ longitude0: Double,
                        distance: Double) -> (x: CGFloat, y: CGFloat, visible: Bool) {
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        // Earth frame: x east at longitude 0, y north, z out of the globe at (0, 0).
        let e = (x: cos(lat) * sin(lon), y: sin(lat), z: cos(lat) * cos(lon))
        // Into the camera's frame: undo the turn to longitude0, then the tilt to latitude0.
        let b = -longitude0 * .pi / 180
        let x1 = e.x * cos(b) + e.z * sin(b), z1 = -e.x * sin(b) + e.z * cos(b), y1 = e.y
        let a = latitude0 * .pi / 180
        let y2 = y1 * cos(a) - z1 * sin(a), z2 = y1 * sin(a) + z1 * cos(a)
        let d = max(distance, 1.0001)
        // The limb is where the screen radius is 1: focal length F = sqrt(d^2 - 1) in those units.
        let focal = (d * d - 1).squareRoot()
        let depth = d - z2
        return (CGFloat(focal * x1 / depth), CGFloat(-focal * y2 / depth), d * z2 > 1)
    }
}
