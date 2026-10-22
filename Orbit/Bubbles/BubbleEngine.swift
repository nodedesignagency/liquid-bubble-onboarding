import SwiftUI

// MARK: - Layout types

/// Colour of the liquid around a bubble, as it reads on the canvas. Kept as raw components so
/// it can be interpolated, and so crews with different tints blend where their liquid meets.
struct GooTint: Equatable {
    var red, green, blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Pale lilac, the default. Mirrors `Theme.liquid`.
    static let liquid = GooTint(hex: 0xEDDDFA)
    /// Mirrors `Theme.butter` and `Theme.sky`.
    static let butter = GooTint(hex: 0xF4E9CA)
    static let sky = GooTint(hex: 0xDCE6F3)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    static func mix(_ a: GooTint, _ b: GooTint, _ t: Double) -> GooTint {
        GooTint(red: a.red + (b.red - a.red) * t,
                green: a.green + (b.green - a.green) * t,
                blue: a.blue + (b.blue - a.blue) * t)
    }
}

/// Where a bubble should end up in a layout. Coordinates are in the stage's reference space
/// (see `StageMetrics`), with the origin in the middle of the stage.
struct BubbleTarget {
    var center: CGPoint = .zero
    /// Zero hides the bubble.
    var radius: CGFloat = 0
    var tint: GooTint = .liquid
    /// A hidden bubble sits inside this bubble, so it buds out of it and melts back into it.
    var anchor: Int?
    /// Wait before the bubble starts, when it is appearing.
    var appearDelay: Double = 0
    /// Wait before the bubble starts, when it is moving or disappearing.
    var moveDelay: Double = 0
    /// Arrive with a soft wobble, for bubbles that collide. On a bubble that is appearing, it buds
    /// out and swells with a bounce instead.
    var jelly = false
    /// Radians per second this bubble circles `orbitCenter` at, once it gets there (positive is
    /// clockwise on screen). Zero keeps it still.
    var orbitRate: Double = 0
    var orbitCenter: CGPoint = .zero
    /// Stretches the orbit vertically (1 is a circle), measured from `orbitCenter`. `center` is
    /// given on the unstretched circle.
    var orbitStretch: CGFloat = 1
    /// Bud out of the anchor's surface instead of its middle: from just inside its rim, facing
    /// the bubble's target, so it swells out of the surface and pinches off. Set on the appearing
    /// bubble's target.
    var budsFromSurface = false
}

/// A thin string of liquid joining two bubbles. Time it to form just as a budding bubble would
/// snap free of its parent, and the neck stretches into the thread instead of breaking.
struct LiquidThread {
    let a: Int
    let b: Int
    var delay: Double = 0

    fileprivate var key: Int { min(a, b) * 1000 + max(a, b) }
}

/// A small caption under a group of bubbles, like "New York trip / Sep 3-5" in the reference.
struct StageLabel: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let detail: String
    /// The bubbles it sits under, centered on the group.
    let anchors: [Int]
}

struct BubbleLayout {
    /// One target per bubble, indexed by bubble id.
    var targets: [BubbleTarget]
    /// Radians per second the whole layout slowly rotates at.
    var spin: Double = 0
    var labels: [StageLabel] = []
    /// Labels wait for the bubbles to settle before fading in.
    var labelDelay: Double = 1.0
    var threads: [LiquidThread] = []
}

struct RenderedBubble: Identifiable {
    let id: Int
    var center: CGPoint
    var radius: CGFloat
    var tint: GooTint
    /// Stacking order: the size the bubble is animating, without the idle breathing, with the id
    /// breaking ties. Bigger is on top; equal bubbles keep a fixed order instead of swapping.
    var depth: Double
    /// Melting back into its anchor, so it should slip underneath whoever swallows it.
    var isLeaving = false
}

struct RenderedThread {
    let a: Int
    let b: Int
    /// 0 is gone, 1 is fully formed.
    var strength: CGFloat
}

struct RenderedLabel: Identifiable {
    let label: StageLabel
    var opacity: Double
    var id: String { label.id }
}

// MARK: - Engine

/// Drives every bubble, thread and label as a function of time.
///
/// Each call to `transition(to:at:)` starts a spring from wherever things are right now
/// toward their new target, so taps that interrupt a running animation never jump.
/// Hidden bubbles follow their anchor bubble every frame, which is what makes new
/// bubbles bud out of a moving parent instead of out of empty space.
final class BubbleEngine {
    private struct Pose {
        var center: CGPoint
        var radius: CGFloat
        var tint: GooTint
    }

    private struct Track {
        var from: Pose
        var to: Pose
        var fromAnchor: Int?
        var toAnchor: Int?
        var moveStart: Double
        var growStart: Double
        var move: SpringCurve
        var grow: SpringCurve
        var orbitRate: Double = 0
        var orbitCenter: CGPoint = .zero
        var orbitStretch: CGFloat = 1
        /// Starting from the anchor's surface (see `BubbleTarget.budsFromSurface`).
        var fromSurface = false
    }

    private struct ThreadTrack {
        let a: Int
        let b: Int
        var from: Double
        var to: Double
        var start: Double
        var curve: SpringCurve
    }

    private struct LabelTrack {
        let label: StageLabel
        let shownAt: Double
        var hiddenAt: Double?
    }

    var reduceMotion = false

    private var tracks: [Track]
    private var spinRate: Double = 0
    private var spinStart: Double = 0
    private var labelTracks: [LabelTrack] = []
    private var threadTracks: [Int: ThreadTrack] = [:]

    init(bubbleCount: Int) {
        let hidden = Pose(center: .zero, radius: 0, tint: .liquid)
        tracks = Array(
            repeating: Track(from: hidden, to: hidden, fromAnchor: nil, toAnchor: nil,
                             moveStart: 0, growStart: 0, move: .glide, grow: .glide),
            count: bubbleCount
        )
    }

    /// Starts animating toward `layout`. Returns, in seconds from `now`, roughly when each new
    /// bubble breaks free of its parent, so the caller can play a haptic for each pop.
    @discardableResult
    func transition(to layout: BubbleLayout, at now: Double) -> [Double] {
        let current = basePoses(at: now)
        let delayScale = reduceMotion ? 0.25 : 1
        var pops: [Double] = []

        for (id, target) in layout.targets.enumerated() where id < tracks.count {
            let previous = tracks[id]
            let isHidden = current[id].radius < 1
            let willShow = target.radius >= 1

            var track = Track(
                from: current[id],
                to: Pose(center: target.center, radius: target.radius, tint: target.tint),
                fromAnchor: isHidden ? (previous.toAnchor ?? previous.fromAnchor) : nil,
                toAnchor: willShow ? nil : target.anchor,
                moveStart: now + target.moveDelay * delayScale,
                growStart: now + target.moveDelay * delayScale,
                move: .glide,
                grow: .glide,
                orbitRate: reduceMotion ? 0 : target.orbitRate,
                orbitCenter: target.orbitCenter,
                orbitStretch: target.orbitStretch
            )

            if isHidden && willShow {
                let start = now + target.appearDelay * delayScale
                // Swell inside the parent first, then drift out, so the liquid stretches into a long neck before it lets go.
                track.growStart = start
                track.moveStart = start + 0.12
                track.move = target.jelly ? .budBouncy : .bud
                track.grow = target.jelly ? .inflateBouncy : .inflate
                track.fromSurface = target.budsFromSurface && track.fromAnchor != nil
                if track.fromSurface {
                    // Swell against the surface first, then pull away, so the neck has time to show.
                    track.moveStart = start + 0.3
                }
                pops.append(target.appearDelay * delayScale + 0.55)
            } else if !isHidden && !willShow {
                track.move = .absorb
                track.grow = .deflate
            } else if target.jelly {
                track.move = .jelly
                // Swell or shrink with the same bounce, unless it is only gliding.
                if abs(target.radius - current[id].radius) > 1 { track.grow = .inflateBouncy }
            }

            if reduceMotion {
                track.move = .calm
                track.grow = .calm
            }
            tracks[id] = track
        }

        // Spin is baked into the poses captured above, so restarting it here never jumps.
        spinRate = reduceMotion ? 0 : layout.spin
        spinStart = now

        // Threads that stay keep going from where they are; dropped ones thin out and vanish.
        let wanted = Dictionary(layout.threads.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, track) in threadTracks where wanted[key] == nil {
            threadTracks[key] = ThreadTrack(a: track.a, b: track.b, from: strength(of: track, at: now), to: 0,
                                            start: now, curve: reduceMotion ? .calm : .absorb)
        }
        for (key, thread) in wanted {
            let current = threadTracks[key].map { strength(of: $0, at: now) } ?? 0
            threadTracks[key] = ThreadTrack(a: thread.a, b: thread.b, from: current, to: 1,
                                            start: now + thread.delay * delayScale, curve: reduceMotion ? .calm : .glide)
        }

        for i in labelTracks.indices where labelTracks[i].hiddenAt == nil {
            labelTracks[i].hiddenAt = now
        }
        labelTracks.removeAll { ($0.hiddenAt ?? .infinity) < now - 1 }
        labelTracks += layout.labels.map { LabelTrack(label: $0, shownAt: now + layout.labelDelay * delayScale) }
        return pops
    }

    /// The frame to draw at `time`, plus a slow idle drift so the liquid feels alive.
    func snapshot(at time: Double) -> [RenderedBubble] {
        let poses = basePoses(at: time)
        return poses.enumerated().map { id, pose in
            var center = pose.center
            var radius = pose.radius
            if !reduceMotion {
                // Small enough that neighbours 2pt apart never touch.
                let phase = Double(id) * 1.7
                center.x += CGFloat(0.4 * sin(time * 0.55 + phase))
                center.y += CGFloat(0.4 * cos(time * 0.45 + phase * 1.3))
                radius *= CGFloat(1 + 0.005 * sin(time * 0.8 + phase))
            }
            return RenderedBubble(id: id, center: center, radius: radius, tint: pose.tint,
                                  depth: Double(pose.radius) + Double(id) * 0.001,
                                  isLeaving: tracks[id].to.radius < 1 && tracks[id].toAnchor != nil)
        }
    }

    /// Threads that are visible at `time`.
    func threads(at time: Double) -> [RenderedThread] {
        threadTracks.values.compactMap { track in
            let s = strength(of: track, at: time)
            return s > 0.02 ? RenderedThread(a: track.a, b: track.b, strength: CGFloat(min(s, 1.2))) : nil
        }
    }

    private func strength(of track: ThreadTrack, at time: Double) -> Double {
        track.from + (track.to - track.from) * track.curve.progress(at: time - track.start)
    }

    /// Labels that are visible at `time`, fading in after their layout settles and out when it changes.
    func labels(at time: Double) -> [RenderedLabel] {
        labelTracks.compactMap { track in
            let fadeIn = smoothstep((time - track.shownAt) / 0.4)
            let fadeOut = track.hiddenAt.map { 1 - smoothstep((time - $0) / 0.2) } ?? 1
            let opacity = fadeIn * fadeOut
            return opacity > 0.001 ? RenderedLabel(label: track.label, opacity: opacity) : nil
        }
    }

    private func basePoses(at time: Double) -> [Pose] {
        let angle = spinAngle(at: time)
        var resolved = [Pose?](repeating: nil, count: tracks.count)
        var visiting = Set<Int>()

        // Anchored bubbles need their anchor's position first. `visiting` breaks the rare
        // cycle where two bubbles swap roles (A was hidden in B, now B hides in A).
        func pose(_ id: Int) -> Pose {
            if let known = resolved[id] { return known }
            visiting.insert(id)
            let track = tracks[id]

            var start = track.from.center
            if let anchor = track.fromAnchor, tracks.indices.contains(anchor), !visiting.contains(anchor) {
                let parent = pose(anchor)
                start = parent.center
                if track.fromSurface {
                    // Just inside the parent's rim, on the side facing where this bubble is going,
                    // pulled in by its own size so it starts as a bulge, not a bubble sitting outside.
                    let goal = track.to.center.rotated(by: angle)
                    let dx = goal.x - parent.center.x, dy = goal.y - parent.center.y
                    let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
                    let q = CGFloat(track.grow.progress(at: time - track.growStart))
                    let depth = parent.radius - track.to.radius * min(max(q, 0), 1) * 0.9
                    start = CGPoint(x: parent.center.x + dx / length * max(depth, 0),
                                    y: parent.center.y + dy / length * max(depth, 0))
                }
            }
            var end = track.to.center.rotated(by: angle)
            if track.orbitRate != 0 || track.orbitStretch != 1 {
                // Circling its own centre: the target moves, and the spring chases it, so the
                // bubble glides into its orbit and stays on it.
                let around = track.orbitCenter.rotated(by: angle)
                let a = orbitAngle(rate: track.orbitRate, since: track.moveStart, at: time)
                end = CGPoint(x: end.x - around.x, y: end.y - around.y).rotated(by: a)
                end = CGPoint(x: end.x + around.x, y: end.y * track.orbitStretch + around.y)
            }
            if let anchor = track.toAnchor, tracks.indices.contains(anchor), !visiting.contains(anchor) {
                end = pose(anchor).center
            }

            let p = track.move.progress(at: time - track.moveStart)
            let q = track.grow.progress(at: time - track.growStart)
            let cp = CGFloat(p), cq = CGFloat(q)
            let result = Pose(
                center: CGPoint(x: start.x + (end.x - start.x) * cp, y: start.y + (end.y - start.y) * cp),
                radius: max(0, track.from.radius + (track.to.radius - track.from.radius) * cq),
                tint: .mix(track.from.tint, track.to.tint, min(max(p, 0), 1))
            )
            visiting.remove(id)
            resolved[id] = result
            return result
        }

        return tracks.indices.map { pose($0) }
    }

    /// How far a bubble has gone round its orbit, easing in from standing still.
    private func orbitAngle(rate: Double, since start: Double, at time: Double) -> Double {
        let elapsed = max(0, time - start)
        let ramp = 1.2
        return rate * (elapsed - ramp * (1 - exp(-elapsed / ramp)))
    }

    /// Eases into rotation instead of starting at full speed.
    private func spinAngle(at time: Double) -> Double {
        guard spinRate != 0 else { return 0 }
        let elapsed = max(0, time - spinStart)
        let ramp = 1.5
        return spinRate * (elapsed - ramp * (1 - exp(-elapsed / ramp)))
    }
}

private func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

extension CGPoint {
    func rotated(by radians: Double) -> CGPoint {
        guard radians != 0 else { return self }
        let c = CGFloat(cos(radians)), s = CGFloat(sin(radians))
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }
}
