import SwiftUI
import MapKit

/// v3: one dark screen. It opens on a real city in 3D (Apple's map), held until it has rendered,
/// then flattens, rises and pulls all the way back (from satellite snapshots fetched while it held,
/// so it never waits on the network), dissolving into a glowing holographic globe on the dark page
/// ("Everyone you love, / in one orbit."). Four friends pop up as pins on their cities, then lift
/// off into orbit round Earth, joined to it by necks of liquid glass, over a faint dot grid. Drag
/// around Earth to spin everyone, the globe with them. "Continue" melts everyone back into Earth
/// and dives back into the city, the first frame, so a screen recording loops.
///
/// Timings are mirrored in `tools/preview/render_v3.py` (V3_*) and `tools/engine/record.swift`.
struct WorldOnboardingView: View {
    enum Mode {
        case onboarding
        /// The placeholder home screen: the globe and friends at rest, no city, copy or buttons.
        case home
    }

    var mode: Mode
    var onFinish: () -> Void

    private enum Phase { case intro, ready, leaving }

    @State private var phase = Phase.intro
    /// Made when the onboarding starts (never on the home screen): an `MKMapView` is heavy, and
    /// a property's initial value is built every time the view is.
    @State private var city: CityMapController?
    @State private var imagery = ZoomImagery()
    @State private var stageSize = CGSize.zero
    /// The dark cover over the city until it has rendered.
    @State private var cityCover = 1.0
    @State private var path: ZoomPath?
    @State private var zoomStart: Double?
    @State private var backStart: Double?
    /// When the friends lifted off: the globe starts turning slowly from then.
    @State private var bloomStart: Double?
    @State private var stageScene = OrbitScene.space
    @State private var gridOpacity = 0.0
    @State private var showSpaceText = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showFooter = false
    @State private var spin = SpinDial()
    @State private var sequence: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Degrees per second the globe turns at rest, and how far it turns per radian of spin.
    private static let drift = 1.2
    private static let spinTurn = 28.0

    init(mode: Mode = .onboarding, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Theme.worldCanvas.ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size
                let metrics = StageMetrics(slot: CGRect(origin: .zero, size: size))
                let orbCenter = metrics.point(OrbitChoreography.bloomEarth.center)
                ZStack {
                    DotGrid(focus: orbCenter)
                        .opacity(gridOpacity)
                    if mode == .onboarding {
                        zoomLayer(size: size)
                    }
                    BubbleStage(scene: stageScene, look: .v3, spin: spin,
                                centerpiece: AnyView(globeLayer(size: size)),
                                startsSettled: true)
                    if mode == .onboarding {
                        copy(size: size, metrics: metrics)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(spinGesture(around: orbCenter))
                .onAppear { stageSize = size }
                .onChange(of: size) { _, newSize in stageSize = newSize }
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
        .sensoryFeedback(.impact(weight: .light), trigger: stageScene)
        .onAppear { start() }
        .onDisappear { sequence?.cancel() }
    }

    // MARK: The zoom

    /// The city, then the snapshots zooming out, under the stage. Hidden once the globe has taken over.
    private func zoomLayer(size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let u = progress(at: t)
            let stack = stackOpacity(at: t, u: u)
            ZStack {
                if let city {
                    CityMapView(controller: city)
                        .overlay { Theme.worldCanvas.opacity(cityCover) }
                        .opacity(showsCity(u: u, stack: stack) ? 1 : 0)
                }
                if let path, let u, stack > 0 {
                    ZoomStack(levels: imagery.levels, metersPerPoint: path.scale(at: u), roll: path.roll(at: u),
                              center: CGPoint(x: size.width / 2, y: size.height / 2), size: size)
                        .opacity(stack)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The globe, between the glass and the photos.
    private func globeLayer(size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            if let state = globe(at: t, size: size) {
                HoloGlobeView(state: state, time: t)
            }
        }
    }

    /// 0 at the handover, 1 at rest; nil before the zoom.
    private func progress(at t: Double) -> Double? {
        guard path != nil, let start = zoomStart else { return nil }
        if let back = backStart { return 1 - min(max((t - back) / EarthZoom.zoomBack, 0), 1) }
        return min(max((t - start) / EarthZoom.zoomOut, 0), 1)
    }

    /// The snapshots fade in over the map as the zoom starts, give way to the globe, and on the
    /// way back fade out over the map at the end.
    private func stackOpacity(at t: Double, u: Double?) -> Double {
        guard let path, let u, let start = zoomStart else { return 0 }
        let underGlobe = 1 - path.globeOpacity(at: u)
        if let back = backStart {
            let left = EarthZoom.zoomBack - (t - back)
            return underGlobe * ZoomPath.ease(left / 0.35)
        }
        return underGlobe * ZoomPath.ease((t - start) / 0.35)
    }

    private func showsCity(u: Double?, stack: Double) -> Bool {
        guard let u else { return true }
        return stack < 1 && u < 0.2
    }

    /// The globe at rest, on this screen.
    private func restGlobe(size: CGSize) -> GlobeState {
        let metrics = StageMetrics(slot: CGRect(origin: .zero, size: size))
        let view = OrbitChoreography.globeView
        return GlobeState(center: metrics.point(OrbitChoreography.bloomEarth.center),
                          radius: OrbitChoreography.globeRadius * metrics.scale,
                          distance: view.distance, latitude: view.latitude, longitude: view.longitude)
    }

    /// Where the globe is at `t`: on its way in (or back), or at rest, turning slowly once the
    /// friends are in orbit and with the spin. Nil before the zoom has reached it.
    private func globe(at t: Double, size: CGSize) -> GlobeState? {
        if let path, let u = progress(at: t), u < 1 {
            return path.globe(at: u)
        }
        guard path != nil || mode == .home || stageScene != .space else { return nil }
        var state = path?.rest ?? restGlobe(size: size)
        state.longitude = turnedLongitude(state.longitude, at: t)
        return state
    }

    private func turnedLongitude(_ longitude: Double, at t: Double) -> Double {
        var turned = longitude - Self.spinTurn * spin.angle(at: t)
        if let bloomStart, backStart == nil {
            turned -= Self.drift * max(0, t - bloomStart)
        }
        return turned
    }

    // MARK: Copy

    private func copy(size: CGSize, metrics: StageMetrics) -> some View {
        // Just under the lower friends: their glass reaches about 143 below Earth's middle.
        let titleTop = size.height / 2 + (OrbitChoreography.bloomEarth.center.y + 182) * metrics.scale
        return ZStack {
            VStack(spacing: 2) {
                Text("Everyone you love,")
                Text("in one orbit.")
            }
            .foregroundStyle(Theme.worldInk)
            .opacity(showSpaceText ? 1 : 0)
            .blur(radius: showSpaceText ? 0 : 6)

            VStack(spacing: 2) {
                Text("Meet Orbit.")
                    .foregroundStyle(Theme.worldInk)
                    .opacity(showTitle ? 1 : 0)
                    .blur(radius: showTitle ? 0 : 6)
                Text("Your friends, always\nwithin reach.")
                    .foregroundStyle(Theme.worldInkSecondary)
                    .opacity(showSubtitle ? 1 : 0)
                    .blur(radius: showSubtitle ? 0 : 6)
            }
        }
        .font(.system(size: 27, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .lineSpacing(1)
        .fixedSize()
        .position(x: size.width / 2, y: titleTop + 52)
        .allowsHitTesting(false)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            WorldButton(title: "Continue with Apple", systemImage: "apple.logo", prominent: true, action: finish)
            WorldButton(title: "Continue with phone number", systemImage: "phone.fill", prominent: false, action: finish)
            Text("By continuing, you agree to our Terms and Privacy Policy.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.worldInkSecondary)
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
            }
            .onEnded { value in
                guard phase == .ready else { return }
                // Angular speed around Earth: the finger's speed across the line to Earth's centre.
                let rx = value.location.x - center.x, ry = value.location.y - center.y
                let reach = max(rx * rx + ry * ry, 900)
                let omega = Double((rx * value.velocity.height - ry * value.velocity.width) / reach)
                spin.release(velocity: omega, at: now)
            }
    }

    private var now: Double { Date.timeIntervalSinceReferenceDate }

    // MARK: Sequence

    private func start() {
        sequence?.cancel()
        sequence = Task { @MainActor in
            guard await waitUntil(2, { stageSize != .zero }) else { return }
            if mode == .home || reduceMotion {
                await settle()
            } else {
                await playIntro()
            }
        }
    }

    /// The city, held until it has rendered and the zoom's imagery is in; the rise; the zoom out to
    /// the globe; the pins; the lift-off; the copy and buttons.
    private func playIntro() async {
        let size = stageSize
        let diagonal = hypot(size.width, size.height)
        let city = CityMapController()
        self.city = city
        // Fetch the zoom's imagery as soon as the map knows its scale, while the city loads.
        _ = await waitUntil(3, { city.handoffEstimate != nil })
        imagery.fetch(handoff: city.handoffEstimate ?? 3.5, diagonal: diagonal)
        _ = await waitUntil(6, { city.isRendered })
        withAnimation(.easeOut(duration: 0.8)) { cityCover = 0 }
        guard await pause(1.5) else { return }
        _ = await waitUntil(3.5, { imagery.isComplete })

        city.rise()
        guard await pause(EarthZoom.rise + 0.05) else { return }
        let handoff = city.metersPerPoint() ?? city.handoffEstimate ?? 3.5
        path = ZoomPath(startScale: handoff, levels: imagery.levels, rest: restGlobe(size: size), size: size)
        zoomStart = now
        guard await pause(EarthZoom.zoomOut * 0.78) else { return }
        withAnimation(.easeOut(duration: 0.7)) { showSpaceText = true }
        guard await pause(EarthZoom.zoomOut * 0.22 + 0.15) else { return }
        await popPinsAndLiftOff()
    }

    /// Reduce Motion, and the home screen: the globe already at rest.
    private func settle() async {
        if mode == .home {
            stageScene = .bloom
            bloomStart = now
            phase = .ready
            gridOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { showSpaceText = true }
        await popPinsAndLiftOff()
    }

    private func popPinsAndLiftOff() async {
        stageScene = .pins
        guard await pause(1.4) else { return }
        stageScene = .bloom
        bloomStart = now
        phase = .ready
        withAnimation(.easeInOut(duration: 1.0)) { gridOpacity = 1 }
        withAnimation(.smooth(duration: 0.5)) { showSpaceText = false }
        guard await pause(0.35) else { return }
        withAnimation(.smooth(duration: 0.6)) { showTitle = true }
        guard await pause(0.3) else { return }
        withAnimation(.smooth(duration: 0.6)) { showSubtitle = true }
        guard await pause(0.6) else { return }
        withAnimation(.smooth(duration: 0.6)) { showFooter = true }
    }

    /// Everyone melts back into Earth, the globe pulls back into the city, then the app takes over.
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
            withAnimation(.easeInOut(duration: 0.8)) { gridOpacity = 0 }
            stageScene = .space
            guard await pause(1.0) else { return }
            guard let current = path, !reduceMotion else {
                onFinish()
                return
            }
            // Back the way it came, from wherever the globe has turned to.
            var rest = current.rest
            rest.longitude = turnedLongitude(rest.longitude, at: now)
            path = ZoomPath(startScale: current.startScale, levels: imagery.levels, rest: rest, size: stageSize)
            backStart = now
            guard await pause(EarthZoom.zoomBack) else { return }
            city?.settle()
            guard await pause(EarthZoom.rise + 0.1) else { return }
            onFinish()
        }
    }

    /// Waits, and says whether to carry on (false once the sequence was cancelled).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    /// Waits until `condition` holds, for at most `limit` seconds. False if cancelled.
    private func waitUntil(_ limit: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date.timeIntervalSinceReferenceDate + limit
        while !condition() && Date.timeIntervalSinceReferenceDate < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return false }
        }
        return !Task.isCancelled
    }
}

/// The faint dot grid of the AiOS reference, fading out away from Earth, so the glass has something
/// to bend.
private struct DotGrid: View {
    var focus: CGPoint

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let reach = max(size.width, size.height) * 0.62
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    let fall = 1 - min(hypot(x - focus.x, y - focus.y) / reach, 1)
                    if fall > 0.02 {
                        let dot = CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.11 * Double(fall))))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// v3's buttons on the dark page: a white capsule first, and a glass one (Liquid Glass on iOS 26).
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
            .foregroundStyle(prominent ? Theme.worldCanvas : Theme.worldInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(WorldButtonStyle(prominent: prominent))
    }
}

private struct WorldButtonStyle: ButtonStyle {
    let prominent: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
        if prominent {
            label.background(Color.white, in: Capsule())
        } else if #available(iOS 26.0, *) {
            label.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            label
                .background(Theme.worldGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}

#Preview {
    WorldOnboardingView()
}
