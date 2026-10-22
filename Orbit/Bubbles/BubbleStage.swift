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
                    GooLayer(bubbles: bubbles, threads: engine.threads(at: time), metrics: metrics)
                    ForEach(bubbles) { bubble in
                        let base = faceSize(for: bubble.id)
                        face(for: bubble.id, diameter: base)
                            .frame(width: base, height: base)
                            .scaleEffect(max(bubble.radius * 2 * metrics.scale / base, 0.001))
                            .position(metrics.point(bubble.center))
                            .opacity(bubble.radius < 0.5 ? 0 : 1)
                            // Bigger on top: a new bubble stays hidden behind its parent's photo
                            // until it buds out, and an absorbed one slips behind whoever swallows it.
                            // Earth sits just above the liquid and under everyone, so friends cling to its rim.
                            .zIndex(bubble.id == OrbitChoreography.earth ? 0.5 : Double(bubble.radius))
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

/// The liquid behind the photos: a pale wash around each one, bridging to its neighbours where
/// they come close, like the reference. Drawn by the `liquid` Metal shader (see `Liquid.metal`)
/// over the whole stage: a blur cut by a soft threshold, computed per pixel, so there is no blur
/// pass, the edge is as soft as it is at any size, and the colour inside is flat.
private struct GooLayer: View {
    var bubbles: [RenderedBubble]
    var threads: [RenderedThread]
    var metrics: StageMetrics

    /// The blur's shoulder, in reference points, and the half-width of the threshold ramp in field
    /// units. The shoulder (with `haloWidth`) is fitted to the reference video's outline at every
    /// angle, so the outline and the scallops between photos match it. The ramp sets how soft the
    /// edge looks: the reference's edge fades over about 7pt once the video's own blur is taken
    /// out, and 0.2 gives 6.8pt. The earlier 0.312 faded over 9.5pt and read as blurrier.
    static let softness: CGFloat = 10.55
    static let edge: Float = 0.2

    var body: some View {
        let shapes = shapes
        if shapes.isEmpty {
            Color.clear
        } else {
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.liquid(
                    .float(Float(Self.softness * metrics.scale)),
                    .float(Self.edge),
                    .floatArray(shapes)
                ))
        }
    }

    /// Nine floats per shape, as `Liquid.metal` reads them: kind, x1, y1, x2, y2, radius, r, g, b.
    private var shapes: [Float] {
        var out: [Float] = []
        out.reserveCapacity((bubbles.count + threads.count) * 9)
        for bubble in bubbles where bubble.radius > 0.5 {
            let c = metrics.point(bubble.center)
            let radius = (bubble.radius + OrbitChoreography.haloWidth(bubble.radius)) * metrics.scale
            out += [0, Float(c.x), Float(c.y), 0, 0, Float(radius),
                    Float(bubble.tint.red), Float(bubble.tint.green), Float(bubble.tint.blue)]
        }
        for thread in threads {
            guard bubbles.indices.contains(thread.a), bubbles.indices.contains(thread.b) else { continue }
            let a = bubbles[thread.a], b = bubbles[thread.b]
            guard a.radius > 1, b.radius > 1 else { continue }
            let pa = metrics.point(a.center), pb = metrics.point(b.center)
            let tint = GooTint.mix(a.tint, b.tint, 0.5)
            out += [1, Float(pa.x), Float(pa.y), Float(pb.x), Float(pb.y), Float(8 * thread.strength * metrics.scale),
                    Float(tint.red), Float(tint.green), Float(tint.blue)]
        }
        return out
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
