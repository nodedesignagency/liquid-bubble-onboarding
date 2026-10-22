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
                    GooLayer(bubbles: bubbles, metrics: metrics)
                    ForEach(bubbles) { bubble in
                        let base = faceSize(for: bubble.id)
                        face(for: bubble.id, diameter: base)
                            .frame(width: base, height: base)
                            .scaleEffect(max(bubble.radius * 2 * metrics.scale / base, 0.001))
                            .position(metrics.point(bubble.center))
                            .opacity(bubble.radius < 0.5 ? 0 : 1)
                            // Bigger on top: a new bubble stays hidden behind its parent's photo
                            // until it buds out, and an absorbed one slips behind whoever swallows it.
                            .zIndex(Double(bubble.radius))
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
        id == OrbitChoreography.earth ? 260 : 150
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
/// pulls a neck of liquid with it. The blob is filled with soft lavender and feathered.
private struct GooLayer: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics

    var body: some View {
        Canvas { context, size in
            let scale = metrics.scale
            context.drawLayer { tinted in
                // One filter per layer, so the blur is guaranteed to happen before the threshold.
                // (With both filters on one context the order isn't what you'd expect, and the
                // circles just glow instead of fusing.)
                tinted.drawLayer { cut in
                    cut.addFilter(.alphaThreshold(min: 0.5, color: .white))
                    cut.drawLayer { soft in
                        soft.addFilter(.blur(radius: 10 * scale))
                        soft.drawLayer { shapes in
                            for bubble in bubbles where bubble.radius > 0.5 {
                                shapes.fill(Path(ellipseIn: haloRect(for: bubble, scale: scale)), with: .color(.white))
                            }
                        }
                    }
                }

                // Fill the blob with the liquid color...
                tinted.blendMode = .sourceIn
                tinted.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: Theme.liquidGradient),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                // ...and let each crew's tint glow through around its bubbles, blending where crews meet.
                tinted.blendMode = .sourceAtop
                for bubble in bubbles where bubble.radius > 0.5 && bubble.tint != .liquid {
                    let halo = haloRect(for: bubble, scale: scale)
                    let center = CGPoint(x: halo.midX, y: halo.midY)
                    let reach = halo.width * 0.85
                    tinted.fill(
                        Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                        with: .radialGradient(
                            Gradient(colors: [bubble.tint.color, bubble.tint.color.opacity(0)]),
                            center: center,
                            startRadius: halo.width * 0.3,
                            endRadius: reach
                        )
                    )
                }
            }
        }
        // Feathered edge: the reference's liquid has no hard outline.
        .blur(radius: 3 * metrics.scale)
    }

    private func haloRect(for bubble: RenderedBubble, scale: CGFloat) -> CGRect {
        // A thick rim of liquid around every photo, like the reference, tapering to nothing for
        // tiny bubbles so they grow out smoothly.
        let padding = min(bubble.radius, min(14, max(6, bubble.radius * 0.24)))
        let r = (bubble.radius + padding) * scale
        let c = metrics.point(bubble.center)
        return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
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
        private let scenes: [OrbitScene] = [.world, .friendsOfFriends, .crews, .orbit]
        @State private var index = 0

        var body: some View {
            BubbleStage(scene: scenes[index])
                .background(Theme.background)
                .onTapGesture { index = (index + 1) % scenes.count }
        }
    }
    return Demo()
}
