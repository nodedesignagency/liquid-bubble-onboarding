import SwiftUI
import UIKit

/// Maps the choreography's fixed reference space onto the stage's slot.
struct StageMetrics {
    static let referenceSize = CGSize(width: 372, height: 480)
    /// Above this, photos would be drawn larger than the size they were rendered at and start to blur.
    static let maxScale: CGFloat = 1.3

    /// Where the reference space sits, in the stage view's own coordinates.
    let slot: CGRect

    var scale: CGFloat {
        let fit = min(slot.width / Self.referenceSize.width, slot.height / Self.referenceSize.height)
        return min(max(fit, 0.1), Self.maxScale)
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: slot.midX + p.x * scale, y: slot.midY + p.y * scale)
    }
}

/// The liquid bubble animation. Change `scene` and the bubbles flow into the new arrangement.
///
/// Give it `slot` (in global coordinates) to lay the bubbles out in one part of the screen
/// while still drawing over all of it, so bubbles pushed aside slide off the real screen edge
/// instead of being cut off by a box.
struct BubbleStage: View {
    var scene: OrbitScene
    var slot: CGRect? = nil

    @State private var engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
    @State private var sequence: Task<Void, Never>? = nil
    @State private var popHaptics: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let people = Person.samples

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let metrics = StageMetrics(
                slot: slot?.offsetBy(dx: -origin.x, dy: -origin.y) ?? CGRect(origin: .zero, size: proxy.size)
            )
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bubbles = engine.snapshot(at: time)
                ZStack {
                    GooLayer(
                        bubbles: bubbles,
                        threads: engine.threads(at: time),
                        time: time,
                        metrics: metrics,
                        alive: !reduceMotion
                    )
                    ForEach(bubbles) { bubble in
                        let base = faceSize(for: bubble.id)
                        face(for: bubble.id, diameter: base)
                            .frame(width: base, height: base)
                            .scaleEffect(max(bubble.radius * 2 * metrics.scale / base, 0.001))
                            .position(metrics.point(bubble.center))
                            .opacity(bubble.radius < 0.5 ? 0 : 1)
                            // Bigger on top: a new bubble stays hidden behind its parent's photo
                            // until it buds out, and an absorbed one slips behind whoever swallows it.
                            // Earth always sits underneath, so friends cling to its rim on top of it.
                            .zIndex(bubble.id == OrbitChoreography.earth ? -1 : Double(bubble.radius))
                    }
                    ForEach(engine.labels(at: time)) { rendered in
                        if let point = labelPoint(for: rendered.label, bubbles: bubbles, metrics: metrics) {
                            // Hangs down from `point`, centered under the group.
                            Color.clear
                                .frame(width: 0, height: 0)
                                .overlay(alignment: .top) {
                                    StageCaption(label: rendered.label)
                                        .fixedSize()
                                        .opacity(rendered.opacity)
                                }
                                .position(point)
                                .zIndex(1000)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { play(scene) }
        .onChange(of: scene) { _, newScene in play(newScene) }
        .onDisappear {
            sequence?.cancel()
            popHaptics?.cancel()
        }
    }

    /// Runs the scene's keyframes one after another.
    private func play(_ scene: OrbitScene) {
        sequence?.cancel()
        let keyframes = OrbitChoreography.keyframes(for: scene)
        guard let first = keyframes.first else { return }
        start(first.layout)

        let rest = keyframes.dropFirst()
        guard !rest.isEmpty else { return }
        sequence = Task { @MainActor in
            var elapsed = 0.0
            for keyframe in rest {
                try? await Task.sleep(for: .seconds(max(0, keyframe.after - elapsed)))
                guard !Task.isCancelled else { return }
                elapsed = keyframe.after
                start(keyframe.layout)
            }
        }
    }

    private func start(_ layout: BubbleLayout) {
        engine.reduceMotion = reduceMotion
        let pops = engine.transition(to: layout, at: Date.timeIntervalSinceReferenceDate)

        // A soft tap as each bubble lets go of its parent.
        popHaptics?.cancel()
        guard !pops.isEmpty else { return }
        popHaptics = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            var elapsed = 0.0
            for time in pops.sorted() {
                try? await Task.sleep(for: .seconds(max(0, time - elapsed)))
                guard !Task.isCancelled else { return }
                elapsed = time
                generator.impactOccurred(intensity: 0.5)
            }
        }
    }

    /// Faces are rendered once at their largest on-screen size and only ever scaled down, so they stay sharp.
    private func faceSize(for id: Int) -> CGFloat {
        id == OrbitChoreography.earth ? 260 : 240
    }

    @ViewBuilder
    private func face(for id: Int, diameter: CGFloat) -> some View {
        if id == OrbitChoreography.earth {
            EarthFace(diameter: diameter)
        } else {
            AvatarFace(person: people[(id - 1) % people.count], diameter: diameter)
        }
    }

    /// Just below the lowest of the label's bubbles, centered under them.
    private func labelPoint(for label: StageLabel, bubbles: [RenderedBubble], metrics: StageMetrics) -> CGPoint? {
        let group = label.anchors.compactMap { bubbles.indices.contains($0) ? bubbles[$0] : nil }.filter { $0.radius > 0.5 }
        guard let lowest = group.map({ $0.center.y + $0.radius }).max() else { return nil }
        let midX = group.map(\.center.x).reduce(0, +) / CGFloat(group.count)
        let p = metrics.point(CGPoint(x: midX, y: lowest))
        return CGPoint(x: p.x, y: p.y + 14)
    }
}

/// The liquid behind the photos. Blur the circles together, then cut the blur back with an alpha
/// threshold: wherever two blurs overlap they fuse into one blob, and a bubble leaving its parent
/// pulls a neck of liquid with it. Then it's lit like a gel: lighter top left, deeper bottom right.
private struct GooLayer: View {
    var bubbles: [RenderedBubble]
    var threads: [RenderedThread]
    var time: Double
    var metrics: StageMetrics
    /// Slowly undulating outlines. Off for Reduce Motion.
    var alive: Bool

    var body: some View {
        Canvas { context, size in
            let scale = metrics.scale
            context.drawLayer { tinted in
                // One filter per layer, so the blur is guaranteed to happen before the threshold.
                // (With both filters on one context the circles just glow instead of fusing.)
                tinted.drawLayer { cut in
                    cut.addFilter(.alphaThreshold(min: 0.5, color: .white))
                    cut.drawLayer { soft in
                        soft.addFilter(.blur(radius: 8 * scale))
                        soft.drawLayer { shapes in
                            for bubble in bubbles where bubble.radius > 0.5 {
                                drawBlob(for: bubble, into: &shapes, scale: scale)
                            }
                            for thread in threads {
                                drawThread(thread, into: &shapes, scale: scale)
                            }
                        }
                    }
                }

                // Fill the liquid, lit from the top...
                tinted.blendMode = .sourceIn
                tinted.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [Theme.liquidLight, Theme.liquid, Theme.liquidDeep]),
                        startPoint: CGPoint(x: size.width * 0.3, y: 0),
                        endPoint: CGPoint(x: size.width * 0.7, y: size.height)
                    )
                )
                tinted.blendMode = .sourceAtop
                for bubble in bubbles where bubble.radius > 4 {
                    let center = metrics.point(bubble.center)
                    let reach = haloRadius(bubble.radius) * scale
                    // ...each crew glowing in its own tint...
                    if bubble.tint != .liquid {
                        glow(&tinted, at: center, radius: reach * 1.7, color: bubble.tint.color, from: 0.35)
                    }
                    // ...with a soft highlight on the upper left of each blob and depth on the lower right.
                    glow(&tinted, at: CGPoint(x: center.x - reach * 0.35, y: center.y - reach * 0.42),
                         radius: reach, color: .white.opacity(0.6))
                    glow(&tinted, at: CGPoint(x: center.x + reach * 0.38, y: center.y + reach * 0.45),
                         radius: reach, color: Theme.liquidShade.opacity(0.55))
                }
            }
        }
        // Just enough to soften the threshold's stair-stepped edge. Any more and the rim fades
        // out like a drop shadow instead of reading as solid liquid.
        .blur(radius: 1.2)
    }

    /// The bubble's rim of liquid, plus three small satellites circling just inside it so the
    /// outline slowly undulates like a lava lamp instead of sitting there as a perfect circle.
    private func drawBlob(for bubble: RenderedBubble, into shapes: inout GraphicsContext, scale: CGFloat) {
        let center = metrics.point(bubble.center)
        let halo = haloRadius(bubble.radius)
        fillCircle(&shapes, center: center, radius: halo * scale)
        guard alive, bubble.radius > 12 else { return }
        let satellite = bubble.radius * 0.32
        let orbit = halo + bubble.radius * 0.045 - satellite
        for k in 0..<3 {
            let direction: Double = k.isMultiple(of: 2) ? 1 : -1
            let angle = time * (0.35 + 0.12 * Double(k)) * direction + Double(bubble.id) * 1.9 + Double(k) * 2.1
            let p = CGPoint(x: bubble.center.x + orbit * CGFloat(cos(angle)), y: bubble.center.y + orbit * CGFloat(sin(angle)))
            fillCircle(&shapes, center: metrics.point(p), radius: satellite * scale)
        }
    }

    /// A string of liquid between two bubbles: a chain of overlapping dots that the blur fuses
    /// into one strand, thinnest in the middle so it snaps there first as it lets go.
    private func drawThread(_ thread: RenderedThread, into shapes: inout GraphicsContext, scale: CGFloat) {
        guard bubbles.indices.contains(thread.a), bubbles.indices.contains(thread.b) else { return }
        let a = bubbles[thread.a], b = bubbles[thread.b]
        guard a.radius > 1, b.radius > 1 else { return }
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return }
        // Start and end a little inside each bubble so the strand fuses into both.
        let start = a.radius * 0.7 / length, end = 1 - b.radius * 0.7 / length
        guard end > start else { return }
        let steps = max(2, Int((end - start) * length / 4))
        for i in 0...steps {
            let u = start + (end - start) * CGFloat(i) / CGFloat(steps)
            let middle = abs(2 * (CGFloat(i) / CGFloat(steps)) - 1)
            let radius = 7.5 * thread.strength * (0.75 + 0.25 * middle * middle)
            let p = CGPoint(x: a.center.x + dx * u, y: a.center.y + dy * u)
            fillCircle(&shapes, center: metrics.point(p), radius: radius * scale)
        }
    }

    private func fillCircle(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.white)
        )
    }

    private func glow(_ context: inout GraphicsContext, at center: CGPoint, radius: CGFloat, color: Color, from: CGFloat = 0) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: center,
                startRadius: radius * from,
                endRadius: radius
            )
        )
    }

    /// The rim of liquid around a photo: about a quarter of its radius, capped so big bubbles
    /// aren't chunky, and tapering to nothing for tiny bubbles so they grow out smoothly.
    private func haloRadius(_ radius: CGFloat) -> CGFloat {
        radius + min(radius, min(14, max(6, radius * 0.24)))
    }
}

/// "New York trip / Sep 3-5" style caption from the reference.
private struct StageCaption: View {
    let label: StageLabel

    var body: some View {
        VStack(spacing: 1) {
            Text(label.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

#Preview {
    struct Demo: View {
        private let scenes: [OrbitScene] = [.you, .bump, .circle, .world]
        @State private var index = 0

        var body: some View {
            BubbleStage(scene: scenes[index])
                .background(Theme.background)
                .onTapGesture { index = (index + 1) % scenes.count }
        }
    }
    return Demo()
}
