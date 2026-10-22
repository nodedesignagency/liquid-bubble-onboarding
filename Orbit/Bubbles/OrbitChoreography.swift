import Foundation
import CoreGraphics

/// The arrangements the bubble stage can morph between.
enum OrbitScene: Hashable {
    /// Earth in the middle, six friends pop out of it.
    case world
    /// Each friend pops out two friends of their own.
    case friendsOfFriends
    /// Everyone regroups into three tinted crews.
    case crews
    /// A gooey ring of friends slowly orbiting Earth.
    case orbit
    /// Everything melts back into Earth, which shrinks to nothing.
    case collapse
}

/// Bubble positions for every `OrbitScene`.
///
/// Bubble 0 is Earth, 1...6 are the inner friends, 7...18 are friends of friends
/// (two per inner friend). All coordinates are in the stage's 372 x 400 reference space,
/// centered on the middle of the stage. Sizes and angles are deliberately uneven so the
/// layouts feel hand-placed rather than drawn with a compass.
enum OrbitChoreography {
    static let bubbleCount = 19
    static let earth = 0
    static let innerFriends = 1...6

    static func layout(for scene: OrbitScene) -> BubbleLayout {
        switch scene {
        case .world: world
        case .friendsOfFriends: friendsOfFriends
        case .crews: crews
        case .orbit: orbit
        case .collapse: collapse
        }
    }

    // MARK: Scenes

    /// Where each inner friend sits around Earth, in degrees (0 is right, clockwise).
    private static let friendAngles: [Double] = [-96, -38, 22, 84, 146, 204]

    private static var world: BubbleLayout {
        let distances: [CGFloat] = [150, 156, 144, 152, 150, 146]
        let radii: [CGFloat] = [33, 27, 31, 26, 32, 28]
        // Pop order hops across the planet instead of ticking round it like a clock.
        let popOrder = [0, 3, 1, 4, 2, 5]

        var targets = tuckedIn()
        targets[earth] = BubbleTarget(radius: 80, appearDelay: 0.05)
        for k in 0..<6 {
            targets[1 + k] = BubbleTarget(
                center: polar(distances[k], friendAngles[k]),
                radius: radii[k],
                appearDelay: 0.6 + 0.11 * Double(popOrder.firstIndex(of: k) ?? k),
                moveDelay: 0.03 * Double(k)
            )
        }
        return BubbleLayout(targets: targets)
    }

    private static var friendsOfFriends: BubbleLayout {
        let distances: [CGFloat] = [98, 102, 98, 96, 100, 98]
        let radii: [CGFloat] = [28, 25, 27, 24, 28, 26]
        // (angle offset from their friend, distance from Earth, radius) for each friend's two friends.
        let children: [[(Double, CGFloat, CGFloat)]] = [
            [(-17, 162, 20), (15, 158, 17)],
            [(-16, 160, 18), (17, 166, 21)],
            [(-17, 158, 19), (15, 162, 16)],
            [(-15, 164, 21), (17, 158, 18)],
            [(-17, 160, 17), (16, 164, 20)],
            [(-16, 158, 19), (17, 162, 17)],
        ]

        var targets = tuckedIn()
        targets[earth] = BubbleTarget(radius: 40, appearDelay: 0.05)
        for k in 0..<6 {
            targets[1 + k] = BubbleTarget(
                center: polar(distances[k], friendAngles[k]),
                radius: radii[k],
                appearDelay: 0.3 + 0.08 * Double(k),
                moveDelay: 0.02 * Double(k)
            )
            for (j, child) in children[k].enumerated() {
                targets[7 + 2 * k + j] = BubbleTarget(
                    center: polar(child.1, friendAngles[k] + child.0),
                    radius: child.2,
                    appearDelay: 0.3 + 0.11 * Double(k) + 0.05 * Double(j),
                    moveDelay: 0.02 * Double(k)
                )
            }
        }
        return BubbleLayout(targets: targets)
    }

    private static var crews: BubbleLayout {
        struct Crew {
            let name: String
            let center: CGPoint
            /// Degrees. Around 0 the triangle points up, around 180 it points down.
            let rotation: Double
            let tint: GooTint
            /// Members in slot order: top, middle-left, middle-right, bottom-left, bottom-middle, bottom-right.
            /// Picked so nobody crosses the stage to get there.
            let members: [Int]
        }
        let crews = [
            Crew(name: "Roomies", center: CGPoint(x: -84, y: -106), rotation: -8, tint: .lilac, members: [7, 18, 8, 17, 6, 1]),
            Crew(name: "Run club", center: CGPoint(x: 84, y: 2), rotation: 188, tint: .periwinkle, members: [12, 11, 3, 10, 2, 9]),
            Crew(name: "Family", center: CGPoint(x: -80, y: 104), rotation: 10, tint: .blush, members: [5, 15, 4, 16, 14, 13]),
        ]

        // Six bubbles packed into a triangle (rows of 1, 2 and 3), centered on its centroid.
        // Slightly uneven sizes on an even grid: the goo still fuses them, but it looks less stamped out.
        let spacing: CGFloat = 45
        let h = spacing * 3.0.squareRoot() / 2
        let slots = [
            CGPoint(x: 0, y: -4 * h / 3),
            CGPoint(x: -spacing / 2, y: -h / 3), CGPoint(x: spacing / 2, y: -h / 3),
            CGPoint(x: -spacing, y: 2 * h / 3), CGPoint(x: 0, y: 2 * h / 3), CGPoint(x: spacing, y: 2 * h / 3),
        ]
        let radii: [CGFloat] = [22, 20, 23, 19, 22, 21]

        var targets = tuckedIn()
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.05)
        var labels: [StageLabel] = []
        for (c, crew) in crews.enumerated() {
            let angle = crew.rotation * .pi / 180
            var lowest = -CGFloat.infinity
            for (slot, id) in crew.members.enumerated() {
                let offset = slots[slot].rotated(by: angle)
                lowest = max(lowest, offset.y + radii[slot])
                targets[id] = BubbleTarget(
                    center: CGPoint(x: crew.center.x + offset.x, y: crew.center.y + offset.y),
                    radius: radii[slot],
                    tint: crew.tint,
                    appearDelay: 0.3 + 0.05 * Double(slot),
                    moveDelay: 0.08 * Double(c) + 0.04 * Double(slot)
                )
            }
            labels.append(StageLabel(
                title: crew.name,
                detail: "\(crew.members.count) friends",
                position: CGPoint(x: crew.center.x, y: crew.center.y + lowest + 19)
            ))
        }
        return BubbleLayout(targets: targets, labels: labels)
    }

    private static var orbit: BubbleLayout {
        // Ten friends close enough that their halos fuse into one liquid ring.
        let ring = [8, 9, 10, 11, 12, 13, 14, 16, 17, 7]
        // Everyone else melts into the ring friend nearest to where they were standing in `crews`.
        let absorbedInto = [1: 8, 18: 7, 6: 17, 2: 10, 3: 11, 4: 13, 5: 16, 15: 14]

        var targets = tuckedIn()
        targets[earth] = BubbleTarget(radius: 56, appearDelay: 0.35)
        for (slot, id) in ring.enumerated() {
            targets[id] = BubbleTarget(
                center: polar(122, -90 + 36 * Double(slot)),
                radius: 33,
                appearDelay: 0.45 + 0.06 * Double(slot),
                moveDelay: 0.03 * Double(slot)
            )
        }
        for (id, anchor) in absorbedInto {
            targets[id] = BubbleTarget(anchor: anchor, moveDelay: 0.02 * Double(id))
        }
        return BubbleLayout(targets: targets, spin: 0.12)
    }

    private static var collapse: BubbleLayout {
        var targets = (0..<bubbleCount).map { id in
            BubbleTarget(anchor: earth, moveDelay: 0.025 * Double(id))
        }
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.45)
        return BubbleLayout(targets: targets)
    }

    // MARK: Helpers

    /// Every bubble hidden inside the bubble it grows out of: friends inside Earth, friends of friends inside their friend.
    private static func tuckedIn() -> [BubbleTarget] {
        (0..<bubbleCount).map { id in
            BubbleTarget(anchor: id == earth ? nil : parent(of: id), moveDelay: 0.02 * Double(id % 6))
        }
    }

    private static func parent(of id: Int) -> Int {
        innerFriends.contains(id) ? earth : 1 + (id - 7) / 2
    }

    private static func polar(_ distance: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: distance * CGFloat(cos(radians)), y: distance * CGFloat(sin(radians)))
    }
}
