import SwiftUI

// MARK: - Layout types

/// Tint of the liquid around a bubble, kept as raw components so it can be interpolated.
/// `.liquid` means "no tint of its own": the stage-wide gradient shows through.
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

    static let liquid = GooTint(hex: 0xE2D5F2)
    /// Crew tints, as soft as the reference's: lavender, sky and lilac.
    static let lavender = GooTint(hex: 0xDCCDF3)
    static let sky = GooTint(hex: 0xD3E2F6)
    static let lilac = GooTint(hex: 0xF0D7EE)

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
}

struct RenderedBubble: Identifiable {
    let id: Int
    var center: CGPoint
    var radius: CGFloat
    var tint: GooTint
}

struct RenderedLabel: Identifiable {
    let label: StageLabel
    var opacity: Double
    var id: String { label.id }
}

// MARK: - Engine

/// Drives every bubble and label as a function of time.
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
                grow: .glide
            )

            if isHidden && willShow {
                let start = now + target.appearDelay * delayScale
                // Swell inside the parent first, then drift out, so the liquid stretches into a long neck before it lets go.
                track.growStart = start
                track.moveStart = start + 0.12
                track.move = .bud
                track.grow = .inflate
                pops.append(target.appearDelay * delayScale + 0.55)
            } else if !isHidden && !willShow {
                track.move = .absorb
                track.grow = .deflate
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

        for i in labelTracks.indices where labelTracks[i].hiddenAt == nil {
            labelTracks[i].hiddenAt = now
        }
        labelTracks.removeAll { ($0.hiddenAt ?? .infinity) < now - 1 }
        labelTracks += layout.labels.map { LabelTrack(label: $0, shownAt: now + layout.labelDelay * delayScale) }
        return pops
    }

    /// The frame to draw at `time`, plus a slow idle drift so the liquid feels alive.
    func snapshot(at time: Double) -> [RenderedBubble] {
        basePoses(at: time).enumerated().map { id, pose in
            var center = pose.center
            var radius = pose.radius
            if !reduceMotion {
                let phase = Double(id) * 1.7
                center.x += CGFloat(1.4 * sin(time * 0.55 + phase))
                center.y += CGFloat(1.4 * cos(time * 0.45 + phase * 1.3))
                radius *= CGFloat(1 + 0.01 * sin(time * 0.8 + phase))
            }
            return RenderedBubble(id: id, center: center, radius: radius, tint: pose.tint)
        }
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
                start = pose(anchor).center
            }
            var end = track.to.center.rotated(by: angle)
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
