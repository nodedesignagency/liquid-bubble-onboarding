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
    /// A friend you tapped has the middle, globe-size, their own friends round them; Earth waits
    /// among them as a way home.
    case focus(Int)

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
/// photo. v3 uses Earth and 1...9, any of whom can have the middle. Coordinates are in the stage's
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
        case .bloom: [Keyframe(after: 0, layout: constellation(center: earth))]
        case .focus(let id): [Keyframe(after: 0, layout: constellation(center: id))]
        }
    }

    // MARK: v3 scenes

    /// The hub of the constellation: where Earth sits once the zoom has pulled back to it (and where
    /// a friend sits when you tap them), and the radius of the glass there. The globe, `globeRadius`,
    /// sits inside Earth's glass, leaving a ring of glass round it.
    static let bloomEarth = (center: CGPoint(x: 0, y: -120), radius: CGFloat(91))
    static let globeRadius: CGFloat = 84
    /// The globe at rest: the point facing you, and how far away the camera is in Earth radii
    /// (far enough to be nearly flat-on, close enough for a touch of depth).
    static let globeView = (latitude: 25.0, longitude: 12.0, distance: 9.0)
    /// A friend's pin on the globe, and Earth's glass when a friend has the middle.
    static let pinRadius: CGFloat = 14
    static let satelliteEarthRadius: CGFloat = 32

    /// The people (bubble ids 1...9, photos `friend-1`...`friend-9`) and where they live.
    static let people: [(id: Int, city: String, latitude: Double, longitude: Double)] = [
        (1, "London", 51.51, -0.13), (2, "Lagos", 6.52, 3.38), (3, "Johannesburg", -26.20, 28.05),
        (4, "Istanbul", 41.01, 28.98), (5, "Nairobi", -1.29, 36.82), (6, "Dubai", 25.20, 55.27),
        (7, "Berlin", 52.52, 13.40), (8, "Cairo", 30.04, 31.24), (9, "Lisbon", 38.72, -9.14),
    ]
    /// Your friends: pinned on the globe, then in orbit round Earth.
    static let homeCircle = [1, 2, 3, 4, 5, 6]

    /// Who knows whom: everyone has four or five friends, and friendship goes both ways, so the
    /// friend you came from is always in the orbit of the friend you tap next.
    static func friends(of id: Int) -> [Int] {
        guard (1...9).contains(id) else { return homeCircle }
        var out: [Int] = []
        for step in [1, -1, 2, -2] {
            out.append((id - 1 + step + 9) % 9 + 1)
        }
        // A few longer links, both ways: 1-5, 2-6, 3-7, 4-8.
        let extra: [Int: Int] = [1: 5, 5: 1, 2: 6, 6: 2, 3: 7, 7: 3, 4: 8, 8: 4]
        if let other = extra[id] { out.append(other) }
        return out
    }

    /// The six places round the hub, deliberately uneven (angle in degrees, 0 to the right and
    /// clockwise; distance from the hub; glass radius). Each is within reach of a glass neck from
    /// the hub (`GlassNeck`) and clear of the copy below.
    static let slots: [(angle: Double, distance: CGFloat, radius: CGFloat)] = [
        (-95, 150, 34), (-30, 146, 29), (22, 140, 32), (78, 132, 30), (142, 140, 27), (-160, 150, 31),
    ]
    /// Where each person goes round the hub when they can: your friends on the side their city is
    /// on, the others somewhere sensible. Taken places are skipped.
    static let homeSlot: [Int: Int] = [1: 5, 4: 0, 6: 1, 5: 2, 3: 3, 2: 4, 7: 1, 8: 2, 9: 5]

    static func city(of id: Int) -> String {
        people.first { $0.id == id }?.city ?? ""
    }

    /// Where a friend's pin sits on the globe at rest, in reference points.
    static func pinCenter(of id: Int) -> CGPoint {
        guard let person = people.first(where: { $0.id == id }) else { return bloomEarth.center }
        let face = GlobeMath.project(latitude: person.latitude, longitude: person.longitude, facing: globeView.latitude,
                                     globeView.longitude, distance: globeView.distance)
        return CGPoint(x: bloomEarth.center.x + face.x * globeRadius, y: bloomEarth.center.y + face.y * globeRadius)
    }

    /// Nothing on the stage while the city and the zoom have the screen; everyone waits inside
    /// Earth, Earth hidden at the hub. After "Continue" everyone melts back into it, then its
    /// glass drains under the globe.
    private static var space: BubbleLayout {
        var targets = (0..<bubbleCount).map { _ in BubbleTarget(anchor: earth) }
        targets[earth] = BubbleTarget(center: bloomEarth.center, moveDelay: 0.55)
        return BubbleLayout(targets: targets)
    }

    /// Earth's glass seeps out from under the globe, and your friends pop up as pins on their cities.
    private static var pins: BubbleLayout {
        var targets = space.targets
        targets[earth] = BubbleTarget(center: bloomEarth.center, radius: bloomEarth.radius)
        for (order, id) in homeCircle.enumerated() {
            targets[id] = BubbleTarget(center: pinCenter(of: id), radius: pinRadius,
                                       appearDelay: 0.15 + 0.11 * Double(order), jelly: true, popsInPlace: true)
        }
        return BubbleLayout(targets: targets)
    }

    /// `center` (Earth, or a friend you tapped) at the hub, its circle round it on necks of glass,
    /// each bobbing on a small circle so the necks breathe. With a friend in the middle, Earth takes
    /// the place that friend left, and stays as a way home. Anyone not in the circle melts into
    /// Earth; anyone new buds out of the one in the middle.
    static func constellation(center: Int) -> BubbleLayout {
        var targets = (0..<bubbleCount).map { _ in BubbleTarget(anchor: earth) }
        targets[center] = BubbleTarget(center: bloomEarth.center, radius: bloomEarth.radius, jelly: true)

        let circle = center == earth ? homeCircle : [earth] + friends(of: center)
        var place: [Int: Int] = [:]
        var taken = Set<Int>()
        if center != earth, let left = homeSlot[center] {
            place[earth] = left
            taken.insert(left)
        }
        for id in circle where place[id] == nil {
            if let wanted = homeSlot[id], !taken.contains(wanted) {
                place[id] = wanted
                taken.insert(wanted)
            }
        }
        for id in circle where place[id] == nil {
            // The free place nearest the one it wanted.
            let wanted = homeSlot[id] ?? 0
            let free = slots.indices.filter { !taken.contains($0) }
            if let best = free.min(by: { angleBetween(slots[$0].angle, slots[wanted].angle) < angleBetween(slots[$1].angle, slots[wanted].angle) }) {
                place[id] = best
                taken.insert(best)
            }
        }

        for (order, id) in circle.enumerated() {
            guard let index = place[id] else { continue }
            let slot = slots[index]
            let radians = slot.angle * .pi / 180
            let spot = CGPoint(x: bloomEarth.center.x + slot.distance * CGFloat(cos(radians)),
                               y: bloomEarth.center.y + slot.distance * CGFloat(sin(radians)))
            let phase = Double(id) * 1.9
            let bob: CGFloat = 4
            targets[id] = BubbleTarget(
                center: CGPoint(x: spot.x + bob * CGFloat(cos(phase)), y: spot.y + bob * CGFloat(sin(phase))),
                radius: id == earth ? satelliteEarthRadius : slot.radius,
                anchor: center,
                appearDelay: 0.2 + 0.09 * Double(order),
                moveDelay: 0.05 * Double(order),
                jelly: true,
                orbitRate: id.isMultiple(of: 2) ? 0.5 : -0.43,
                orbitCenter: spot,
                budsFromSurface: true
            )
        }
        return BubbleLayout(targets: targets)
    }

    private static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
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
