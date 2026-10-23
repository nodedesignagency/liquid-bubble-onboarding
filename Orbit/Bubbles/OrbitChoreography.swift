import Foundation
import CoreGraphics

/// The story the bubbles tell, one scene per onboarding page.
///
/// v1 (the first story, lilac liquid): `you`, `bump`, `circle`, `world`, then `collapse`.
/// v2 (one screen, glass orbs that are the liquid themselves, no threads): `gate`, swipe up,
/// `reveal`, and after "Continue" back to `gate`, so a recording loops.
/// v3 (pull back from a city to the whole Earth, then friends pop out of it in flat liquid):
/// `space` while the map zooms out, `bloom`, and `space` again after "Continue".
enum OrbitScene: Hashable {
    // MARK: v3

    /// Nothing on the stage: the map has the screen (zooming out from a city to the whole Earth),
    /// and everyone waits inside Earth for `bloom`. After "Continue" everyone melts back into Earth.
    case space
    /// Earth sits in a pool of liquid; five friends pop out of it, then more pop out of them.
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
/// photo; v3 uses them as small drops of liquid, and 16...20 as places. Coordinates are in the stage's
/// 372 x 480 reference space, centered on the middle of the stage (v2's stage is the whole screen,
/// so its coordinates reach about 400 above and below the centre).
enum OrbitChoreography {
    static let bubbleCount = 21
    /// v2: photo-less glass droplets. v3: small drops of liquid.
    static let droplets = 10...15
    /// v3: places your friends have been (`place-1` to `place-5`).
    static let places = 16...20

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
        case .bloom: [Keyframe(after: 0, layout: bloom)]
        }
    }

    // MARK: v3 scenes

    /// Where Earth sits once the map has shrunk into it: the middle of its pool of liquid. `radius`
    /// is the pool's edge; the globe itself (`globeRadius`) sits inside it, leaving a rim of liquid.
    static let bloomEarth = (center: CGPoint(x: 0, y: -125), radius: CGFloat(55))
    static let globeRadius: CGFloat = 46
    /// v3: how far each photo's liquid reaches past the photo, as a fraction of its radius.
    static let photoMargin: CGFloat = 0.26

    /// One bubble of v3's bloom: where it lives around Earth (angle in degrees, 0 to the right and
    /// clockwise; distance from Earth's centre), its size, who it pops out of, and when.
    private struct Petal {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let radius: CGFloat
        let parent: Int
        let delay: Double
        /// How far it bobs around its home, so its neck keeps breathing.
        let bob: CGFloat
    }

    /// The bloom, in the order it pops out: five friends around Earth (a pentagon, like the
    /// reference the user circled), then a ring in the valleys between them and a few further out
    /// along their axes, each out of the friend next to it, then small drops at the tips.
    private static let petals: [Petal] = {
        var petals: [Petal] = []
        let ring1 = [1, 2, 3, 4, 5]
        for (k, id) in ring1.enumerated() {
            petals.append(Petal(id: id, angle: -90 + 72 * Double(k), distance: 94, radius: 34,
                                parent: earth, delay: 0.25 + 0.1 * Double(k), bob: 3))
        }
        // In the valleys, each out of the friend just before it (clockwise).
        let ring2 = [16, 6, 17, 7, 18]
        for (k, id) in ring2.enumerated() {
            petals.append(Petal(id: id, angle: -54 + 72 * Double(k), distance: 140, radius: 22,
                                parent: ring1[k], delay: 0.95 + 0.09 * Double(k), bob: 4))
        }
        // Further out along four of the five friends' axes. The empty one, bottom right, keeps the
        // bloom from reading as a wheel.
        let ring3: [(Int, Int)] = [(0, 19), (1, 8), (3, 20), (4, 9)]
        for (n, (k, id)) in ring3.enumerated() {
            petals.append(Petal(id: id, angle: -90 + 72 * Double(k), distance: 170, radius: 18,
                                parent: ring1[k], delay: 1.3 + 0.09 * Double(n), bob: 4))
        }
        // Drops of liquid with no photo at the tips: (id, angle, distance, radius, parent). A few
        // degrees off their parent's axis, about as far out as a neck can reach, so they hang on,
        // pinch off and melt back as everyone bobs.
        let drops: [(Int, Double, CGFloat, CGFloat, Int)] = [
            (10, -62, 188, 6, 16), (11, 26, 188, 5, 6), (12, 170, 188, 7, 7),
            (13, 226, 188, 5, 18), (14, -82, 210, 6, 19), (15, 134, 210, 5, 20),
        ]
        for (n, drop) in drops.enumerated() {
            petals.append(Petal(id: drop.0, angle: drop.1, distance: drop.2, radius: drop.3,
                                parent: drop.4, delay: 1.75 + 0.1 * Double(n), bob: 7))
        }
        return petals
    }()

    /// Everyone tucked inside the bubble they pop out of; Earth hidden at its own place, so its
    /// pool swells out from under the globe instead of sliding in. Melting back after "Continue",
    /// the outer ones go first, then the friends, then Earth's pool drains under the globe.
    private static var space: BubbleLayout {
        var targets = (0..<bubbleCount).map { _ in BubbleTarget(anchor: earth) }
        targets[earth] = BubbleTarget(center: bloomEarth.center, moveDelay: 0.75)
        for petal in petals {
            targets[petal.id] = BubbleTarget(anchor: petal.parent, moveDelay: petal.parent == earth ? 0.3 : 0)
        }
        return BubbleLayout(targets: targets)
    }

    private static var bloom: BubbleLayout {
        var targets = space.targets
        targets[earth] = BubbleTarget(center: bloomEarth.center, radius: bloomEarth.radius)
        for (order, petal) in petals.enumerated() {
            let radians = petal.angle * .pi / 180
            let home = CGPoint(x: bloomEarth.center.x + petal.distance * CGFloat(cos(radians)),
                               y: bloomEarth.center.y + petal.distance * CGFloat(sin(radians)))
            let phase = Double(order) * 2.1
            targets[petal.id] = BubbleTarget(
                center: CGPoint(x: home.x + petal.bob * CGFloat(cos(phase)), y: home.y + petal.bob * CGFloat(sin(phase))),
                radius: petal.radius,
                anchor: petal.parent,
                appearDelay: petal.delay,
                jelly: true,
                orbitRate: order.isMultiple(of: 2) ? 0.55 : -0.47,
                orbitCenter: home,
                budsFromSurface: true
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
