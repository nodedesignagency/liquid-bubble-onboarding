import SwiftUI
import MapKit

/// v3: one screen. It opens on a real city in 3D satellite view (Apple's map), pulls back through
/// the sky to the whole Earth in space ("Everyone you love, / in one orbit."), then the black of
/// space falls away and the globe shrinks into a glass orb on a white page. Your friends pop out
/// of it in one crisp body of flat liquid, five first (the pentagon the user circled), then more
/// out of them. Drag around Earth to spin everyone, the globe with them. "Continue" melts everyone
/// back into Earth and dives back into the city, the first frame, so a screen recording loops.
///
/// Timings are mirrored in `tools/preview/render_v3.py` (V3_*) and `tools/engine/record.swift`.
struct WorldOnboardingView: View {
    enum Mode {
        case onboarding
        /// The placeholder home screen: straight to the bloom, no copy or buttons.
        case home
    }

    var mode: Mode
    var onFinish: () -> Void

    private enum Phase { case intro, ready, leaving }

    @State private var phase = Phase.intro
    @State private var camera: MapCameraPosition
    @State private var zoomTrigger = 0
    @State private var zoomDirection = EarthZoom.Direction.out
    @State private var measureTrigger = 0
    @State private var globe: EarthZoom.Globe?
    @State private var mapOpacity = 0.0
    /// The circle the map is cut to, as a fraction of the globe's radius; nil shows all of it.
    @State private var wipe: CGFloat?
    /// The map scaled down so the globe is the orb, at Earth's place in the bloom.
    @State private var shrunk = false
    @State private var showGlass = false
    @State private var showSpaceText = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showFooter = false
    @State private var stageScene = OrbitScene.space
    @State private var spin = SpinDial()
    @State private var sequence: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mode: Mode = .onboarding, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish
        _camera = State(initialValue: .camera(mode == .home ? EarthZoom.space() : EarthZoom.street))
    }

    var body: some View {
        ZStack {
            Theme.worldCanvas.ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size
                let metrics = StageMetrics(slot: CGRect(origin: .zero, size: size))
                let orbCenter = metrics.point(OrbitChoreography.bloomEarth.center)
                let orbRadius = OrbitChoreography.globeRadius * metrics.scale
                ZStack {
                    BubbleStage(scene: stageScene, look: .v3, spin: spin, startsSettled: true)
                    earth(size: size, orbCenter: orbCenter, orbRadius: orbRadius)
                    EarthGlass(diameter: orbRadius * 2)
                        .position(orbCenter)
                        .opacity(showGlass ? 1 : 0)
                    if mode == .onboarding {
                        copy(size: size, metrics: metrics)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(spinGesture(around: orbCenter))
            }
            .ignoresSafeArea()

            if mode == .onboarding {
                VStack(spacing: 0) {
                    Spacer()
                    if showFooter {
                        footer
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        // The map fills the screen until it has shrunk into Earth: no status bar over the sky.
        .statusBarHidden(!shrunk)
        .sensoryFeedback(.impact(weight: .medium), trigger: showGlass)
        .onAppear { start() }
        .onDisappear { sequence?.cancel() }
    }

    // MARK: Earth

    /// The map, centred on the screen in a square as tall as the screen (so a globe wider than
    /// the screen still has its edges), cut to a circle around the globe and scaled into the orb.
    @ViewBuilder
    private func earth(size: CGSize, orbCenter: CGPoint, orbRadius: CGFloat) -> some View {
        let side = max(size.width, size.height)
        let found = globe ?? EarthZoom.Globe(center: CGPoint(x: side / 2, y: side / 2), radius: side * 0.3)
        let maskRadius = wipe.map { found.radius * $0 } ?? side
        // Where the globe's centre is on screen.
        let onScreen = CGPoint(x: size.width / 2 - side / 2 + found.center.x, y: size.height / 2 - side / 2 + found.center.y)
        let scale = shrunk ? orbRadius / max(found.radius * EarthZoom.limbCut, 1) : 1
        Color.clear
            .overlay {
                EarthMapView(camera: $camera, zoomTrigger: zoomTrigger, direction: zoomDirection,
                             measureTrigger: measureTrigger, size: CGSize(width: side, height: side)) { measured in
                    globe = measured
                }
                .mask {
                    Circle()
                        .frame(width: maskRadius * 2, height: maskRadius * 2)
                        .position(found.center)
                }
                .scaleEffect(scale, anchor: UnitPoint(x: found.center.x / side, y: found.center.y / side))
                .offset(shrunk ? CGSize(width: orbCenter.x - onScreen.x, height: orbCenter.y - onScreen.y) : .zero)
            }
            .opacity(mapOpacity)
            .allowsHitTesting(false)
    }

    // MARK: Copy

    private func copy(size: CGSize, metrics: StageMetrics) -> some View {
        // Just under the bloom: its lowest liquid reaches about 172 below Earth's middle.
        let titleTop = size.height / 2 + (OrbitChoreography.bloomEarth.center.y + 205) * metrics.scale
        return ZStack {
            VStack(spacing: 2) {
                Text("Everyone you love,")
                Text("in one orbit.")
            }
            .font(.system(size: 27, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .opacity(showSpaceText ? 1 : 0)
            .blur(radius: showSpaceText ? 0 : 6)
            .position(x: size.width / 2, y: size.height * 0.17)

            VStack(spacing: 2) {
                Text("Meet Orbit.")
                    .foregroundStyle(Theme.ink)
                    .opacity(showTitle ? 1 : 0)
                    .blur(radius: showTitle ? 0 : 6)
                Text("Your friends, always\nwithin reach.")
                    .foregroundStyle(Theme.inkSecondary)
                    .opacity(showSubtitle ? 1 : 0)
                    .blur(radius: showSubtitle ? 0 : 6)
            }
            .font(.system(size: 27, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .fixedSize()
            .position(x: size.width / 2, y: titleTop + 52)
        }
        .allowsHitTesting(false)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            WorldButton(title: "Continue with Apple", systemImage: "apple.logo", prominent: true, action: finish)
            WorldButton(title: "Continue with phone number", systemImage: "phone.fill", prominent: false, action: finish)
            Text("By continuing, you agree to our Terms and Privacy Policy.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    // MARK: Spin

    /// Drag around Earth to spin everyone, and the globe with them; let go and it coasts.
    private func spinGesture(around center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard phase == .ready else { return }
                let finger = Double(atan2(value.location.y - center.y, value.location.x - center.x))
                spin.drag(finger: finger, at: now)
                turnGlobe(to: spin.angle(at: now), animated: false)
            }
            .onEnded { value in
                guard phase == .ready else { return }
                // Angular speed around Earth: the finger's speed across the line to Earth's centre.
                let rx = value.location.x - center.x, ry = value.location.y - center.y
                let reach = max(rx * rx + ry * ry, 900)
                let omega = Double((rx * value.velocity.height - ry * value.velocity.width) / reach)
                spin.release(velocity: omega, at: now)
                turnGlobe(to: spin.finalAngle, animated: true)
            }
    }

    /// The globe turns with the bloom: the map's heading is the spin, the other way round
    /// (raising the heading turns the map anticlockwise).
    private func turnGlobe(to angle: Double, animated: Bool) {
        let degrees = -angle * 180 / .pi
        let heading = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let target = MapCameraPosition.camera(EarthZoom.space(heading: heading))
        if animated {
            withAnimation(.easeOut(duration: SpinDial.coast * 3)) { camera = target }
        } else {
            camera = target
        }
    }

    private var now: Double { Date.timeIntervalSinceReferenceDate }

    // MARK: Sequence

    private func start() {
        sequence?.cancel()
        sequence = Task { @MainActor in
            switch mode {
            case .home: await settleIntoBloom()
            case .onboarding: await playIntro()
            }
        }
    }

    /// City, sky, space, then the globe shrinks into Earth and everyone pops out.
    private func playIntro() async {
        if reduceMotion {
            // No zoom: straight to the globe, then into the bloom.
            camera = .camera(EarthZoom.space())
            withAnimation(.easeOut(duration: 0.4)) { mapOpacity = 1 }
            guard await pause(0.4) else { return }
            measureTrigger += 1
            guard await pause(0.2) else { return }
            await shrinkIntoEarth()
            return
        }
        withAnimation(.easeOut(duration: 0.6)) { mapOpacity = 1 }
        guard await pause(1.2) else { return }
        zoomDirection = .out
        zoomTrigger += 1
        guard await pause(EarthZoom.duration - 1.0) else { return }
        withAnimation(.easeOut(duration: 0.7)) { showSpaceText = true }
        guard await pause(1.1) else { return }
        // Pin the camera where the zoom ended, then find the globe on screen.
        camera = .camera(EarthZoom.space())
        measureTrigger += 1
        guard await pause(0.6) else { return }
        withAnimation(.easeIn(duration: 0.3)) { showSpaceText = false }
        await shrinkIntoEarth()
    }

    /// Space falls away around the globe, the globe shrinks into its place in the bloom and
    /// becomes glass, everyone pops out, then the copy and buttons come in.
    private func shrinkIntoEarth() async {
        // The two overlap, so the ring of space left around the globe thins as it all shrinks.
        withAnimation(.smooth(duration: 0.7)) { wipe = EarthZoom.limbCut }
        guard await pause(0.2) else { return }
        withAnimation(.spring(response: 0.85, dampingFraction: 0.86)) { shrunk = true }
        guard await pause(0.9) else { return }
        withAnimation(.easeOut(duration: 0.4)) { showGlass = true }
        stageScene = .bloom
        phase = .ready
        guard await pause(0.5) else { return }
        withAnimation(.smooth(duration: 0.6)) { showTitle = true }
        guard await pause(0.3) else { return }
        withAnimation(.smooth(duration: 0.6)) { showSubtitle = true }
        guard await pause(0.8) else { return }
        withAnimation(.smooth(duration: 0.6)) { showFooter = true }
    }

    /// The home screen: the globe already in its orb, everyone popping out.
    private func settleIntoBloom() async {
        guard await pause(0.35) else { return }
        measureTrigger += 1
        guard await pause(0.15) else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            wipe = EarthZoom.limbCut
            shrunk = true
        }
        withAnimation(.easeOut(duration: 0.5)) {
            mapOpacity = 1
            showGlass = true
        }
        stageScene = .bloom
        phase = .ready
    }

    /// Everyone melts back into Earth, the globe grows back into space, and the camera dives
    /// into the city, then the app takes over.
    private func finish() {
        guard phase == .ready else { return }
        phase = .leaving
        sequence?.cancel()
        sequence = Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) {
                showFooter = false
                showTitle = false
                showSubtitle = false
            }
            stageScene = .space
            guard await pause(reduceMotion ? 0.4 : 1.2) else { return }
            if reduceMotion {
                onFinish()
                return
            }
            withAnimation(.easeIn(duration: 0.25)) { showGlass = false }
            withAnimation(.smooth(duration: 0.8)) { shrunk = false }
            withAnimation(.smooth(duration: 0.7).delay(0.35)) { wipe = nil }
            guard await pause(0.9) else { return }
            zoomDirection = .back
            zoomTrigger += 1
            guard await pause(EarthZoom.duration + 0.2) else { return }
            onFinish()
        }
    }

    /// Waits, and says whether to carry on (false once the sequence was cancelled).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// v3's buttons: flat capsules, like the liquid. The first is ink, the second the liquid's grey.
struct WorldButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(prominent ? Theme.ink : Theme.worldLiquid, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    WorldOnboardingView()
}
