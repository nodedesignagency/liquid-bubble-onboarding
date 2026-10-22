import SwiftUI
import UIKit

/// Maps the choreography's fixed reference space onto whatever size the stage gets.
struct StageMetrics {
    static let referenceSize = CGSize(width: 372, height: 400)
    /// Above this, avatars would be drawn larger than the size they were rendered at and start to blur.
    static let maxScale: CGFloat = 1.3

    let size: CGSize

    var scale: CGFloat {
        let fit = min(size.width / Self.referenceSize.width, size.height / Self.referenceSize.height)
        return min(max(fit, 0.1), Self.maxScale)
    }

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + p.x * scale, y: size.height / 2 + p.y * scale)
    }
}

/// The liquid bubble animation. Change `scene` and the bubbles flow into the new arrangement.
struct BubbleStage: View {
    var scene: OrbitScene

    @State private var engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
    @State private var popHaptics: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let people = Person.samples

    var body: some View {
        GeometryReader { proxy in
            let metrics = StageMetrics(size: proxy.size)
            ZStack {
                TimelineView(.animation) { timeline in
                    let bubbles = engine.snapshot(at: timeline.date.timeIntervalSinceReferenceDate)
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
                    }
                }

                ForEach(OrbitChoreography.layout(for: scene).labels) { label in
                    CrewLabel(label: label)
                        .position(metrics.point(label.position))
                        .transition(AnyTransition.asymmetric(
                            insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.85))
                                .animation(.smooth(duration: 0.4).delay(0.75)),
                            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.15))
                        ))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { play(scene) }
        .onChange(of: scene) { _, newScene in play(newScene) }
        .onDisappear { popHaptics?.cancel() }
    }

    private func play(_ scene: OrbitScene) {
        engine.reduceMotion = reduceMotion
        let pops = engine.transition(
            to: OrbitChoreography.layout(for: scene),
            at: Date.timeIntervalSinceReferenceDate
        )

        // A soft tap for every bubble that pops free, like popping bubble wrap.
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
                generator.impactOccurred(intensity: 0.6)
            }
        }
    }

    /// Faces are rendered once at their largest on-screen size and only ever scaled down, so they stay sharp.
    private func faceSize(for id: Int) -> CGFloat {
        id == OrbitChoreography.earth ? 210 : 88
    }

    @ViewBuilder
    private func face(for id: Int, diameter: CGFloat) -> some View {
        if id == OrbitChoreography.earth {
            EarthFace(diameter: diameter)
        } else {
            AvatarFace(person: people[(id - 1) % people.count], diameter: diameter)
        }
    }
}

/// The liquid behind the photos. Blur the circles together, then cut the blur back with an alpha
/// threshold: wherever two blurs overlap they fuse into one blob, which is the goo. The blob is filled
/// with a soft pastel gradient and feathered at the edge, like the reference.
private struct GooLayer: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics

    var body: some View {
        Canvas { context, size in
            let scale = metrics.scale
            context.drawLayer { tinted in
                tinted.drawLayer { goo in
                    goo.addFilter(.alphaThreshold(min: 0.5, color: .white))
                    goo.addFilter(.blur(radius: 8 * scale))
                    goo.drawLayer { shapes in
                        for bubble in bubbles where bubble.radius > 0.5 {
                            shapes.fill(Path(ellipseIn: haloRect(for: bubble, scale: scale)), with: .color(.white))
                        }
                    }
                }

                // Fill the blob with the stage-wide gradient...
                tinted.blendMode = .sourceIn
                tinted.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: Theme.liquidGradient),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                tinted.blendMode = .sourceAtop
                for bubble in bubbles where bubble.radius > 0.5 {
                    let halo = haloRect(for: bubble, scale: scale)
                    let center = CGPoint(x: halo.midX, y: halo.midY)
                    let edge = halo.width / 2
                    // ...let crews glow in their own tint, blending where neighbours meet...
                    if bubble.tint != .liquid {
                        let reach = edge * 1.7
                        tinted.fill(
                            Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                            with: .radialGradient(
                                Gradient(colors: [bubble.tint.color, bubble.tint.color.opacity(0)]),
                                center: center,
                                startRadius: edge * 0.6,
                                endRadius: reach
                            )
                        )
                    }
                    // ...and lighten it right around each photo, so the color deepens toward the rim.
                    tinted.fill(
                        Path(ellipseIn: halo),
                        with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                            center: center,
                            startRadius: bubble.radius * scale * 0.9,
                            endRadius: edge
                        )
                    )
                }
            }
        }
        // Feathered edge: the reference's liquid has no hard outline.
        .blur(radius: 4 * metrics.scale)
    }

    private func haloRect(for bubble: RenderedBubble, scale: CGFloat) -> CGRect {
        // A rim of liquid around every photo: about a quarter of its radius, capped so Earth's isn't
        // chunky, and tapering to nothing for tiny bubbles so they grow out smoothly.
        let padding = min(bubble.radius, min(12, max(6, bubble.radius * 0.24)))
        let r = (bubble.radius + padding) * scale
        let c = metrics.point(bubble.center)
        return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
}

private struct CrewLabel: View {
    let label: StageLabel

    var body: some View {
        VStack(spacing: 2) {
            Text(label.title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label.detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkTertiary)
        }
        .fixedSize()
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
