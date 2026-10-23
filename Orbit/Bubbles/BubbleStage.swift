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

/// How the stage draws its bubbles.
enum StageLook {
    /// Photos on a pale lilac liquid (the `liquid` shader).
    case v1
    /// No background liquid: the glass orbs are the liquid themselves (`GlassLiquidLayer`).
    case v2
    /// Earth and friends in rings of glass joined by necks of liquid glass (`WorldGlass`), the
    /// globe (`centerpiece`, from the screen) over the glass, and the friends' photos on top.
    case v3
}

/// The liquid bubble animation. Change `scene` and the bubbles flow into the new arrangement.
///
/// Give it `slot` (in global coordinates) to lay the bubbles out in one part of the screen
/// while still drawing over all of it, so bubbles pushed aside slide off the real screen edge
/// instead of being cut off by a box.
struct BubbleStage: View {
    var scene: OrbitScene
    var slot: CGRect? = nil
    var look: StageLook = .v1
    /// v2: the finger lifting Earth, added to its position every frame.
    var lift: EarthLift? = nil
    /// v2: drawn into the glass layer over the photos, so glass passing over it bends it.
    var backdrop: AnyView? = nil
    /// v3: the finger spinning everyone around Earth.
    var spin: SpinDial? = nil
    /// v3: drawn between the glass and the photos (the globe), given Earth's bubble as it is this
    /// frame (turned by the spin), so pins sit on the globe, the glass rings it, and it follows Earth
    /// when a friend takes the middle.
    var centerpiece: ((RenderedBubble?) -> AnyView)? = nil
    /// Starts on `scene` already settled instead of animating into it: v2's dome is simply there
    /// at launch (it used to swell out of the middle of the screen and bounce down), and v3's
    /// Earth waits at its own place, so its pool swells out from under the globe.
    var startsSettled = false

    @State private var engine: BubbleEngine
    @State private var sequence: Task<Void, Never>? = nil
    @State private var popHaptics: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PhotoStyle.storageKey) private var photoStyle = PhotoStyle.glass.rawValue

    private let people = Person.samples

    /// `engine`: pass one to share it with the screen (v3 hit-tests taps on it); by default the
    /// stage makes its own.
    init(scene: OrbitScene, slot: CGRect? = nil, look: StageLook = .v1, lift: EarthLift? = nil,
         backdrop: AnyView? = nil, spin: SpinDial? = nil, centerpiece: ((RenderedBubble?) -> AnyView)? = nil,
         startsSettled: Bool = false, engine: BubbleEngine? = nil) {
        self.scene = scene
        self.slot = slot
        self.look = look
        self.lift = lift
        self.backdrop = backdrop
        self.spin = spin
        self.centerpiece = centerpiece
        self.startsSettled = startsSettled
        let engine = engine ?? BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
        if startsSettled, let first = OrbitChoreography.keyframes(for: scene).first {
            // Started long ago, so every spring has come to rest.
            engine.transition(to: first.layout, at: Date.timeIntervalSinceReferenceDate - 60)
        }
        _engine = State(initialValue: engine)
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let metrics = StageMetrics(
                slot: slot?.offsetBy(dx: -origin.x, dy: -origin.y) ?? CGRect(origin: .zero, size: proxy.size)
            )
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bubbles = lifted(engine.snapshot(at: time), at: time, scale: metrics.scale)
                // v2 stretches each orb along its motion, so it needs where everyone was a moment ago.
                let earlier = look == .v2 ? lifted(engine.snapshot(at: time - Self.velocityStep), at: time - Self.velocityStep,
                                                   scale: metrics.scale) : []
                ZStack {
                    switch look {
                    case .v1:
                        GooLayer(bubbles: bubbles, threads: engine.threads(at: time), metrics: metrics)
                    case .v2:
                        GlassLiquidLayer(bubbles: bubbles, velocities: velocities(bubbles, earlier, scale: metrics.scale),
                                         metrics: metrics, size: proxy.size, backdrop: backdrop)
                    case .v3:
                        let turned = turnedBySpin(bubbles, at: time)
                        WorldGlass(bubbles: turned, metrics: metrics, size: proxy.size)
                        if let hub = Self.photoHub(turned) {
                            HubGlow(colors: WorldPhoto.glowColors(for: hub.id), radius: WorldPhoto.photoRadius(glass: hub.radius) * metrics.scale,
                                    strength: Self.hubGlowStrength(hub))
                                .position(metrics.point(hub.center))
                                .zIndex(0.3)
                        }
                        if let centerpiece {
                            centerpiece(turned.indices.contains(OrbitChoreography.earth) ? turned[OrbitChoreography.earth] : nil)
                                .zIndex(1)
                        }
                        ForEach(turned.filter { WorldPhoto.hasPhoto($0.id) && WorldPhoto.radius(for: $0) > 0.25 }) { bubble in
                            let diameter = WorldPhoto.radius(for: bubble) * 2 * metrics.scale
                            WorldDisc(image: WorldPhoto.image(for: bubble.id), diameter: diameter,
                                      edge: WorldPhoto.pinEdge(for: bubble))
                                .position(metrics.point(bubble.center))
                                .zIndex(Self.worldLayer(of: bubble))
                        }
                    }
                    ForEach(look == .v1 ? bubbles : []) { bubble in
                        // Drawn at its real size (not scaled), so the photo is resampled once and the
                        // glass shader works in screen points.
                        let diameter = max(bubble.radius * 2 * metrics.scale, 1)
                        face(for: bubble.id, diameter: diameter)
                            .frame(width: diameter, height: diameter)
                            .position(metrics.point(bubble.center))
                            .opacity(bubble.radius < 0.5 ? 0 : 1)
                            // Bigger on top: a new bubble stays hidden behind its parent's photo
                            // until it buds out, and an absorbed one slips behind whoever swallows it.
                            // Ordered by the size each bubble is heading for, not its breathing size,
                            // so two photos of the same size never swap places. Earth sits just above
                            // the liquid and under everyone, so friends cling to its rim.
                            .zIndex(bubble.id == OrbitChoreography.earth ? 0.5 : bubble.depth)
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
        .onAppear {
            // A settled start already has its first layout (see `init`).
            if !startsSettled { play(scene) }
        }
        .onChange(of: scene) { _, newScene in play(newScene) }
        .onDisappear {
            sequence?.cancel()
            popHaptics?.cancel()
        }
    }

    static let velocityStep = 1.0 / 120

    /// Each bubble's velocity in screen points per second, by id.
    private func velocities(_ now: [RenderedBubble], _ before: [RenderedBubble], scale: CGFloat) -> [CGVector] {
        now.indices.map { i in
            guard before.indices.contains(i) else { return .zero }
            return CGVector(dx: (now[i].center.x - before[i].center.x) * scale / Self.velocityStep,
                            dy: (now[i].center.y - before[i].center.y) * scale / Self.velocityStep)
        }
    }

    /// v3: everyone turned round the hub by the spin (the one in the middle sits on the pivot, so
    /// it doesn't move, and someone crossing to the middle never jumps). Photos stay upright: only
    /// their places turn. Earth never turns: it is on the pivot, or parked in its corner.
    static func turned(_ bubbles: [RenderedBubble], by angle: Double) -> [RenderedBubble] {
        guard angle != 0 else { return bubbles }
        let pivot = OrbitChoreography.bloomEarth.center
        return bubbles.map { bubble in
            guard bubble.id != OrbitChoreography.earth else { return bubble }
            var out = bubble
            let around = CGPoint(x: bubble.center.x - pivot.x, y: bubble.center.y - pivot.y).rotated(by: angle)
            out.center = CGPoint(x: around.x + pivot.x, y: around.y + pivot.y)
            return out
        }
    }

    /// v3: who is drawn over whom. The one in the middle, or heading there, is on top, so the
    /// others bud out from behind it and melt back in behind it, and the globe (zIndex 1) is over
    /// anyone budding out of Earth, melting into it, or leaving the middle as Earth comes back.
    /// Pins, and friends lifting off from them, stay on the globe's face. The glass is 0 and the
    /// glow in the middle 0.3.
    static func worldLayer(of bubble: RenderedBubble) -> Double {
        let middle = OrbitChoreography.bloomEarth.radius - 1
        if WorldPhoto.pinEdge(for: bubble) > 0.01 || abs(bubble.startRadius - OrbitChoreography.pinRadius) < 0.5 {
            return 1000 + bubble.depth
        }
        if bubble.targetRadius >= middle { return 500 + bubble.depth }
        if bubble.startRadius >= middle { return 0.6 + bubble.depth / 1000 }
        if bubble.isAppearing || bubble.isLeaving { return 0.5 + bubble.depth / 1000 }
        return 2 + bubble.depth
    }

    /// v3: the friend in the middle (the biggest photo, once it is bigger than anyone round it).
    static func photoHub(_ bubbles: [RenderedBubble]) -> RenderedBubble? {
        let hub = bubbles.filter { WorldPhoto.hasPhoto($0.id) }.max { $0.radius < $1.radius }
        guard let hub, hub.radius > 45 else { return nil }
        return hub
    }

    /// The middle's glow comes up as the friend grows into the middle (and goes as they leave).
    static func hubGlowStrength(_ hub: RenderedBubble) -> Double {
        Double(min(max((hub.radius - 45) / 40, 0), 1))
    }

    private func turnedBySpin(_ bubbles: [RenderedBubble], at time: Double) -> [RenderedBubble] {
        guard let spin else { return bubbles }
        return Self.turned(bubbles, by: spin.angle(at: time))
    }

    /// Earth moved by the finger, if there is one.
    private func lifted(_ bubbles: [RenderedBubble], at time: Double, scale: CGFloat) -> [RenderedBubble] {
        guard let lift, bubbles.indices.contains(OrbitChoreography.earth) else { return bubbles }
        let offset = lift.offset(at: time)
        guard offset != 0 else { return bubbles }
        var out = bubbles
        out[OrbitChoreography.earth].center.y += offset / scale
        return out
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

    @ViewBuilder
    private func face(for id: Int, diameter: CGFloat) -> some View {
        let style = PhotoStyle(rawValue: photoStyle) ?? .glass
        if id == OrbitChoreography.earth {
            EarthFace(diameter: diameter, style: style)
        } else {
            AvatarFace(person: people[(id - 1) % people.count], diameter: diameter, style: style)
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
    /// edge looks. In the reference video everything is equally soft, so its edges read as clean
    /// shapes; on a sharp screen a 7pt fade next to sharp photos read as haze. 0.06 fades over about
    /// 2pt: crisp, with no stair steps (variant C, picked by the user to try).
    static let softness: CGFloat = 10.55
    static let edge: Float = 0.06

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

/// v3: a photo as a sharp disc, with a pin's white edge while it sits on the globe. Drawn at its
/// real size each frame, so it stays crisp as it pops and grows.
private struct WorldDisc: View {
    let image: UIImage?
    let diameter: CGFloat
    /// The pin's white edge, 0 to 1.
    var edge: Double = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.worldGlass
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            if edge > 0.01 {
                Circle()
                    .strokeBorder(Color.white, lineWidth: max(1.5, diameter * 0.09))
                    .opacity(edge)
            }
        }
    }
}

/// v3: the glow round whoever is in the middle, like the globe's aura (a tight bright rim and a
/// wide soft spill, the same falloff as `holoGlobe`'s), in colours from the photo's own background
/// (`WorldPhoto.glowColors`), so it changes with the person. `radius` is the photo's edge.
private struct HubGlow: View {
    let colors: (inner: Color, outer: Color)
    let radius: CGFloat
    let strength: Double

    var body: some View {
        let reach = max(radius * 2.2, 1)
        // The aura's falloff past the edge, as fractions of the radius: 0.42 e^(-b/0.3) + 0.35 e^(-b/0.06).
        let beyond: [CGFloat] = [0, 0.06, 0.15, 0.3, 0.6, 1.2]
        let glow: [Double] = [0.77, 0.47, 0.28, 0.16, 0.06, 0]
        var stops: [Gradient.Stop] = [Gradient.Stop(color: colors.inner.opacity(0.77 * strength * 0.8), location: 0)]
        for i in beyond.indices {
            let tint = beyond[i] < 0.2 ? colors.inner : colors.outer
            stops.append(Gradient.Stop(color: tint.opacity(glow[i] * strength * 0.8), location: (1 + beyond[i]) * radius / reach))
        }
        return Circle()
            .fill(RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: reach))
            .frame(width: reach * 2, height: reach * 2)
            .allowsHitTesting(false)
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
        private let scenes: [OrbitScene] = [.gate, .reveal]
        @State private var index = 0

        var body: some View {
            BubbleStage(scene: scenes[index], look: .v2)
                .background(Theme.background)
                .onTapGesture { index = (index + 1) % scenes.count }
        }
    }
    return Demo()
}
