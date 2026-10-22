import Foundation
import CoreGraphics

/// The story the bubbles tell, one scene per onboarding page.
///
/// v1 (the first story, lilac liquid): `you`, `bump`, `circle`, `world`, then `collapse`.
/// v2 (glass orbs that are the liquid themselves, no threads): `planet`, `rise`, `gather`,
/// `orbit`, then `planet` again, so a recording loops.
enum OrbitScene: Hashable {
    // MARK: v2

    /// Earth alone, big, in the middle. Everyone is still inside it.
    case planet
    /// Earth sinks to the bottom of the screen like a horizon, and you bud out of it and rise.
    case rise
    /// Your friends bud out of the horizon one by one, float up and fuse onto your bubble.
    case gather
    /// The cluster lets go: friends glide into orbits around you, the inner and outer rings going
    /// opposite ways so they melt into each other as they pass, and Earth, now small, orbits you too.
    case orbit

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
/// theirs and 9 is one more for the ring. Coordinates are in the stage's 372 x 480 reference
/// space, centered on the middle of the stage.
enum OrbitChoreography {
    static let bubbleCount = 10
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
        case .planet: [Keyframe(after: 0, layout: planet)]
        case .rise: [Keyframe(after: 0, layout: rise)]
        case .gather: [Keyframe(after: 0, layout: gather)]
        case .orbit: [Keyframe(after: 0, layout: orbit)]
        }
    }

    // MARK: v2 scenes

    /// Earth on pages 2 and 3: shrunk to a planet at the bottom of the stage, clear of the footer.
    private static let ground = (center: CGPoint(x: 0, y: 156), radius: CGFloat(80))
    /// Your bubble while friends gather onto it.
    private static let youRisen = (center: CGPoint(x: 0, y: -72), radius: CGFloat(62))

    /// Everyone tucked inside Earth, so they all bud out of it, and melt back into it.
    private static func insideEarth() -> [BubbleTarget] {
        (0..<bubbleCount).map { id in id == earth ? BubbleTarget() : BubbleTarget(anchor: earth) }
    }

    /// Earth alone, swelling in with a bounce.
    private static var planet: BubbleLayout {
        var targets = insideEarth()
        targets[earth] = BubbleTarget(center: CGPoint(x: 0, y: 0), radius: 150, appearDelay: 0.1, jelly: true)
        return BubbleLayout(targets: targets)
    }

    /// Earth shrinks down to the bottom of the stage and you bud out of its top, pulling a neck of
    /// glass that pinches off.
    private static var rise: BubbleLayout {
        var targets = insideEarth()
        targets[earth] = BubbleTarget(center: ground.center, radius: ground.radius)
        targets[you] = BubbleTarget(center: youRisen.center, radius: youRisen.radius, appearDelay: 0.45, jelly: true,
                                    budsFromSurface: true)
        return BubbleLayout(targets: targets)
    }

    /// Friends rise out of Earth one at a time and settle just off your edge, close enough that
    /// the glass melts into a neck between each of them and you.
    private static var gather: BubbleLayout {
        // (angle around you in degrees, 0 right and clockwise; radius)
        let spots: [(Double, CGFloat)] = [(160, 34), (20, 36), (215, 30), (325, 32), (255, 28), (290, 30)]
        var targets = insideEarth()
        targets[earth] = BubbleTarget(center: ground.center, radius: ground.radius)
        targets[you] = BubbleTarget(center: youRisen.center, radius: youRisen.radius)
        for (i, spot) in spots.enumerated() {
            let offset = polar(youRisen.radius + spot.1 + 3, spot.0)
            targets[2 + i] = BubbleTarget(
                center: CGPoint(x: youRisen.center.x + offset.x, y: youRisen.center.y + offset.y),
                radius: spot.1,
                appearDelay: 0.25 + 0.32 * Double(i),
                jelly: true,
                budsFromSurface: true
            )
        }
        return BubbleLayout(targets: targets)
    }

    /// You in the middle; three friends on an inner orbit going clockwise, three more and Earth on
    /// an outer orbit going the other way. Both orbits are tall ellipses that use the screen's
    /// height, and at the sides they overlap, so friends melt into each other as they pass.
    private static var orbit: BubbleLayout {
        let inner: CGFloat = 104, outer: CGFloat = 160, stretch: CGFloat = 1.22
        var targets = insideEarth()
        targets[you] = BubbleTarget(center: .zero, radius: 58)
        for (i, angle) in [210.0, 330, 90].enumerated() {
            targets[2 + i] = BubbleTarget(center: polar(inner, angle), radius: 34, orbitRate: 0.32, orbitStretch: stretch)
        }
        for (i, angle) in [0.0, 180, 270].enumerated() {
            targets[5 + i] = BubbleTarget(center: polar(outer, angle), radius: 27, orbitRate: -0.22, orbitStretch: stretch)
        }
        // Your world, now small enough to orbit you.
        targets[earth] = BubbleTarget(center: polar(outer, 90), radius: 28, orbitRate: -0.22, orbitStretch: stretch)
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
