import Foundation
import CoreGraphics

/// The arrangements the bubble stage can morph between.
enum OrbitScene: Hashable {
    /// Earth in the middle, five friends bud out of it.
    case world
    /// Maya moves to the middle and her friends bud out of her.
    case friendsOfFriends
    /// Everyone regroups into three crews of three.
    case crews
    /// The crews melt into a single drop, which bursts into a liquid ring around Earth.
    case orbit
    /// Everything melts back into Earth, which shrinks to nothing.
    case collapse
}

/// A layout and when to start moving toward it, counted from the moment the scene starts.
struct Keyframe {
    let after: Double
    let layout: BubbleLayout
}

/// Bubble positions for every `OrbitScene`, at the reference's scale: few, big bubbles,
/// happy to run off the edge of the screen.
///
/// Bubble 0 is Earth, 1...5 are your friends (1 is Maya), 6...9 are Maya's friends and 10 only
/// shows up in the ring. Coordinates are in the stage's 372 x 480 reference space, centered on
/// the middle of the stage.
enum OrbitChoreography {
    static let bubbleCount = 11
    static let earth = 0
    static let maya = 1

    static func keyframes(for scene: OrbitScene) -> [Keyframe] {
        switch scene {
        case .world: [Keyframe(after: 0, layout: world)]
        case .friendsOfFriends: [Keyframe(after: 0, layout: friendsOfFriends)]
        case .crews: [Keyframe(after: 0, layout: crews)]
        case .orbit: [Keyframe(after: 0, layout: drop), Keyframe(after: 1.05, layout: orbit)]
        case .collapse: [Keyframe(after: 0, layout: collapse)]
        }
    }

    // MARK: Scenes

    private static var world: BubbleLayout {
        let earthCenter = CGPoint(x: 0, y: -10)
        // (angle in degrees, 0 is right and clockwise; distance from Earth; radius) for friends 1...5.
        let friends: [(Double, CGFloat, CGFloat)] = [
            (-58, 176, 44),   // Maya
            (12, 170, 40),    // Kwame
            (82, 172, 44),    // Ines
            (152, 170, 40),   // Kai
            (-128, 174, 42),  // Amara
        ]
        // Bud order hops across the planet instead of ticking round it like a clock.
        let budOrder = [0, 3, 1, 2, 4]

        var targets = hiddenEverywhere()
        targets[earth] = BubbleTarget(center: earthCenter, radius: 92, appearDelay: 0.05)
        for (k, friend) in friends.enumerated() {
            let offset = polar(friend.1, friend.0)
            targets[1 + k] = BubbleTarget(
                center: CGPoint(x: earthCenter.x + offset.x, y: earthCenter.y + offset.y),
                radius: friend.2,
                appearDelay: 0.7 + 0.22 * Double(budOrder[k]),
                moveDelay: 0.04 * Double(k)
            )
        }
        return BubbleLayout(targets: targets)
    }

    private static var friendsOfFriends: BubbleLayout {
        let mayaCenter = CGPoint(x: 0, y: -40)
        // (angle around Maya, distance, radius) for Maya's friends 6...9.
        let around: [(Double, CGFloat, CGFloat)] = [(-150, 140, 40), (-90, 136, 40), (-30, 140, 40), (30, 140, 42)]

        var targets = hiddenEverywhere()
        targets[maya] = BubbleTarget(center: mayaCenter, radius: 54)
        // Earth and Kwame drift down and half off screen; everyone else steps out of frame.
        targets[earth] = BubbleTarget(center: CGPoint(x: -160, y: 120), radius: 92, appearDelay: 0.05)
        targets[2] = BubbleTarget(center: CGPoint(x: 170, y: 175), radius: 40, moveDelay: 0.05)
        targets[3] = BubbleTarget(center: CGPoint(x: 300, y: 60), radius: 44, moveDelay: 0.05)
        targets[4] = BubbleTarget(center: CGPoint(x: -320, y: -40), radius: 40, moveDelay: 0.05)
        targets[5] = BubbleTarget(center: CGPoint(x: -300, y: -200), radius: 42, moveDelay: 0.05)
        for (i, friend) in around.enumerated() {
            let offset = polar(friend.1, friend.0)
            targets[6 + i] = BubbleTarget(
                center: CGPoint(x: mayaCenter.x + offset.x, y: mayaCenter.y + offset.y),
                radius: friend.2,
                appearDelay: 0.75 + 0.2 * Double(i),
                moveDelay: 0.05 * Double(i)
            )
        }
        return BubbleLayout(
            targets: targets,
            labels: [StageLabel(title: "Maya", detail: "4 mutual friends", anchors: [maya])],
            labelDelay: 1.9
        )
    }

    private static var crews: BubbleLayout {
        // Three friends per crew, packed in a triangle, staggered down the screen like the reference.
        let crews: [(name: String, center: CGPoint, pointsDown: Bool, tint: GooTint, members: [Int])] = [
            ("Roomies", CGPoint(x: -84, y: -135), false, .lavender, [1, 6, 7]),
            ("Run club", CGPoint(x: 96, y: 8), true, .sky, [2, 8, 9]),
            ("Family", CGPoint(x: -70, y: 128), false, .lilac, [3, 4, 5]),
        ]
        let radius: CGFloat = 44
        let spacing = 2 * radius + 2
        let slots = [
            CGPoint(x: 0, y: -spacing / 3.0.squareRoot()),
            CGPoint(x: -spacing / 2, y: spacing / (2 * 3.0.squareRoot())),
            CGPoint(x: spacing / 2, y: spacing / (2 * 3.0.squareRoot())),
        ]

        var targets = hiddenEverywhere()
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.1)
        var labels: [StageLabel] = []
        for (c, crew) in crews.enumerated() {
            let flip: CGFloat = crew.pointsDown ? -1 : 1
            for (slot, id) in crew.members.enumerated() {
                targets[id] = BubbleTarget(
                    center: CGPoint(x: crew.center.x + slots[slot].x * flip, y: crew.center.y + slots[slot].y * flip),
                    radius: radius,
                    tint: crew.tint,
                    appearDelay: 0.3 + 0.08 * Double(slot),
                    moveDelay: 0.1 * Double(c) + 0.05 * Double(slot)
                )
            }
            labels.append(StageLabel(title: crew.name, detail: "\(crew.members.count) friends", anchors: crew.members))
        }
        return BubbleLayout(targets: targets, labels: labels)
    }

    /// Every crew slides into the middle and melts into one small drop.
    private static var drop: BubbleLayout {
        var targets = (0..<bubbleCount).map { id in
            BubbleTarget(anchor: earth, moveDelay: 0.04 * Double(id % 4))
        }
        targets[earth] = BubbleTarget(radius: 8, appearDelay: 0.35)
        return BubbleLayout(targets: targets)
    }

    /// The drop bursts into a ring that fuses into one liquid donut, and Earth swells back in the middle.
    private static var orbit: BubbleLayout {
        var targets = hiddenEverywhere()
        targets[earth] = BubbleTarget(radius: 56, appearDelay: 0.35, moveDelay: 0.35)
        for slot in 0..<10 {
            targets[1 + slot] = BubbleTarget(
                center: polar(134, -90 + 36 * Double(slot)),
                radius: 42,
                appearDelay: 0.02 * Double(slot),
                moveDelay: 0.02 * Double(slot)
            )
        }
        return BubbleLayout(targets: targets, spin: 0.08)
    }

    private static var collapse: BubbleLayout {
        var targets = (0..<bubbleCount).map { id in
            BubbleTarget(anchor: earth, moveDelay: 0.03 * Double(id))
        }
        targets[earth] = BubbleTarget(radius: 0, moveDelay: 0.5)
        return BubbleLayout(targets: targets)
    }

    // MARK: Helpers

    /// Each bubble tucked inside the one it grows out of: Maya's friends inside Maya, everyone else inside Earth.
    private static func hiddenEverywhere() -> [BubbleTarget] {
        (0..<bubbleCount).map { id in
            switch id {
            case earth: BubbleTarget()
            case 6...9: BubbleTarget(anchor: maya)
            default: BubbleTarget(anchor: earth)
            }
        }
    }

    private static func polar(_ distance: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: distance * CGFloat(cos(radians)), y: distance * CGFloat(sin(radians)))
    }
}
