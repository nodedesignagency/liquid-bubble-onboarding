import SwiftUI
import MapKit

/// v3: one dark screen. It opens on a real city in 3D (Apple's map), shown only once every view
/// the opening passes through has rendered, with a big dome of clear glass rising from the bottom
/// edge: "Swipe up to enter". Swipe it up and it sweeps off over the city, the map flattens, rises
/// and pulls all the way back (from satellite snapshots fetched while it loaded, so it never waits
/// on the network), and a glowing ring sweeps out from the city turning the real Earth into a
/// holographic globe ("Everyone you love, / in one orbit."). Six friends pop up as pins on their
/// cities, then lift off into orbit round Earth, joined to it by necks of liquid glass, over a
/// faint dot grid. Drag around Earth to spin everyone, the globe with them. Tap a friend and they
/// take the middle, globe-size, their own friends budding out of them; tap Earth to come back.
/// "Continue" melts everyone back into Earth and dives back into the city, and the dome rises
/// again: the first frame, so a screen recording loops.
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

    private enum Phase { case loading, gate, zooming, ready, leaving }

    /// The words under the constellation.
    private enum Headline: Hashable {
        case space, meet, focus(Int)

        var title: String {
            switch self {
            case .space: "Everyone you love,\nin one orbit."
            case .meet: "Meet Orbit."
            case .focus(let id): "\(Person.samples[(id - 1) % Person.samples.count].name)'s orbit."
            }
        }

        var subtitle: String? {
            switch self {
            case .space: nil
            case .meet: "Your friends, always\nwithin reach."
            case .focus(let id):
                "\(OrbitChoreography.city(of: id)) · \(OrbitChoreography.friends(of: id).count) friends\nTap Earth to come back."
            }
        }
    }

    @State private var phase = Phase.loading
    /// Made when the onboarding starts (never on the home screen): an `MKMapView` is heavy, and
    /// a property's initial value is built every time the view is.
    @State private var city: CityMapController?
    @State private var imagery = ZoomImagery()
    @State private var stageSize = CGSize.zero
    /// The dark cover over the city until it has rendered, and a spinner if that takes a while.
    @State private var cityCover = 1.0
    @State private var showLoader = false
    @State private var path: ZoomPath?
    @State private var zoomStart: Double?
    @State private var backStart: Double?
    /// When the friends lifted off: the globe starts turning slowly from then.
    @State private var bloomStart: Double?
    @State private var stageScene: OrbitScene
    /// Shared with the stage, so taps can find who is where.
    @State private var engine: BubbleEngine
    /// The friend in the middle, if you tapped one.
    @State private var focus: Int?
    @State private var gridOpacity = 0.0
    @State private var headline: Headline?
    @State private var showFooter = false
    @State private var spin = SpinDial()
    @State private var sequence: Task<Void, Never>?

    // The gate: the dome rises when the city is ready, follows the finger, and sweeps off the top.
    @State private var domeLift = EarthLift()
    @State private var domeShownAt: Double?
    @State private var domeExitAt: Double?
    @State private var domeExitFrom: CGFloat = 0
    @State private var domeVisible = false
    @State private var pastThreshold = false
    /// The soft shade at the top and bottom of the city while the dome waits.
    @State private var gateShade = 0.0

    @AppStorage(GlobePalette.storageKey) private var paletteName = GlobePalette.dusk.name
    @State private var paletteNote: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Degrees per second the globe turns at rest, and how far it turns per radian of spin.
    private static let drift = 1.2
    private static let spinTurn = 28.0
    /// How far up the finger has to lift the dome before letting go enters.
    private static let threshold: CGFloat = 90
    /// The top of the copy, in reference points below the stage's middle: under the lowest
    /// friend's glass (about 43) with room to spare.
    private static let copyTop: CGFloat = 66

    init(mode: Mode = .onboarding, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish
        // Settled on its first scene, as if it had started long ago: the home screen is simply
        // there, and Earth waits at its place, so its glass seeps out from under the globe.
        let first: OrbitScene = mode == .home ? .bloom : .space
        let engine = BubbleEngine(bubbleCount: OrbitChoreography.bubbleCount)
        if let layout = OrbitChoreography.keyframes(for: first).first?.layout {
            engine.transition(to: layout, at: Date.timeIntervalSinceReferenceDate - 60)
        }
        _engine = State(initialValue: engine)
        _stageScene = State(initialValue: first)
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
                        gateShadeLayer(size: size)
                    }
                    BubbleStage(scene: stageScene, look: .v3, spin: spin,
                                centerpiece: { earth in AnyView(globeLayer(earth: earth, size: size)) },
                                engine: engine)
                    if mode == .onboarding {
                        copy(size: size, metrics: metrics)
                        if domeVisible {
                            gate(size: size)
                        }
                        ProgressView()
                            .tint(.white)
                            .opacity(showLoader ? 0.6 : 0)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(around: orbCenter))
                .onTapGesture(coordinateSpace: .local) { location in
                    tap(at: location, size: size)
                }
                #if DEBUG
                .onLongPressGesture(minimumDuration: 0.8) { cyclePalette() }
                #endif
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

            if let paletteNote {
                VStack {
                    Text(paletteNote)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.worldInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.worldGlass, in: Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: stageScene)
        .sensoryFeedback(.selection, trigger: pastThreshold)
        .onAppear { start() }
        .onDisappear { sequence?.cancel() }
    }

    private var palette: GlobePalette { GlobePalette.named(paletteName) }

    // MARK: The zoom

    /// The city, then the snapshots zooming out, under the stage. The snapshots lose their colour
    /// as the globe's ring sweeps out over them, so the real Earth fades into the hologram.
    private func zoomLayer(size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let u = progress(at: t)
            let stack = stackOpacity(at: t, u: u)
            let sweep = path.flatMap { path in u.map { path.sweep(at: $0) } } ?? 0
            ZStack {
                if let city {
                    CityMapView(controller: city)
                        .overlay { Theme.worldCanvas.opacity(cityCover) }
                        .opacity(showsCity(u: u, stack: stack) ? 1 : 0)
                }
                if let path, let u, stack > 0 {
                    ZoomStack(levels: imagery.levels, metersPerPoint: path.scale(at: u), roll: path.roll(at: u),
                              center: CGPoint(x: size.width / 2, y: size.height / 2), size: size)
                        .saturation(1 - 0.65 * sweep)
                        .brightness(-0.14 * sweep)
                        .opacity(stack)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The globe, between the glass and the photos, given Earth's bubble as the stage has it.
    @ViewBuilder
    private func globeLayer(earth: RenderedBubble?, size: CGSize) -> some View {
        let t = now
        if let state = globe(at: t, earth: earth, size: size) {
            HoloGlobeView(state: state, palette: palette, time: t)
        }
    }

    /// 0 at the handover, 1 at rest; nil before the zoom.
    private func progress(at t: Double) -> Double? {
        guard path != nil, let start = zoomStart else { return nil }
        if let back = backStart { return 1 - min(max((t - back) / EarthZoom.zoomBack, 0), 1) }
        return min(max((t - start) / EarthZoom.zoomOut, 0), 1)
    }

    /// The snapshots fade in over the map as the zoom starts and are dropped once the globe has
    /// swept over the whole screen; on the way back they fade out over the map at the end.
    private func stackOpacity(at t: Double, u: Double?) -> Double {
        guard let path, let u, let start = zoomStart, path.showsSnapshots(at: u) else { return 0 }
        if let back = backStart {
            let left = EarthZoom.zoomBack - (t - back)
            return ZoomPath.ease(left / 0.35)
        }
        return ZoomPath.ease((t - start) / 0.35)
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

    /// Where the globe is at `t`: on its way in (or back), else inside Earth's glass wherever Earth
    /// is (in the middle, or among a friend's friends), turning slowly once the friends are in orbit
    /// and with the spin. Nil before the zoom has reached it.
    private func globe(at t: Double, earth: RenderedBubble?, size: CGSize) -> GlobeState? {
        if let path, let u = progress(at: t), u < 1 {
            return path.globe(at: u)
        }
        guard path != nil || mode == .home || stageScene != .space else { return nil }
        var state = path?.rest ?? restGlobe(size: size)
        if let earth, earth.radius > 0.5 {
            let metrics = StageMetrics(slot: CGRect(origin: .zero, size: size))
            state.center = metrics.point(earth.center)
            state.radius = WorldPhoto.globeRadius(for: earth) * metrics.scale
        }
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

    // MARK: The gate

    /// Where the dome sits: its radius and resting top (about three quarters down, like Wabi's),
    /// how far below that it waits before rising, and how far up it sweeps to leave the screen.
    private struct DomeGeometry {
        let radius: CGFloat
        let restTop: CGFloat
        let hidden: CGFloat
        let gone: CGFloat
        var restCenterY: CGFloat { restTop + radius }

        init(size: CGSize) {
            radius = size.width * 0.62
            restTop = size.height * 0.76
            hidden = size.height - restTop + 90
            gone = -(restTop + radius * 2 + 40)
        }
    }

    /// The dome's offset from its resting place at `t`, negative up.
    private func domeOffset(at t: Double, _ g: DomeGeometry) -> CGFloat {
        if let exitAt = domeExitAt {
            let p = CGFloat(SpringCurve.domeOut.progress(at: t - exitAt))
            return domeExitFrom + (g.gone - domeExitFrom) * p
        }
        let shown = domeShownAt.map { CGFloat(SpringCurve.domeIn.progress(at: t - $0)) } ?? 0
        return g.hidden * (1 - shown) + domeLift.offset(at: t)
    }

    private func gate(size: CGSize) -> some View {
        let g = DomeGeometry(size: size)
        return TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let offset = domeOffset(at: t, g)
            ZStack {
                GateDome(diameter: g.radius * 2)
                    .position(x: size.width / 2, y: g.restCenterY + offset)
                hint(bob: reduceMotion ? 0 : CGFloat(sin(t * 3.4)) * 2)
                    .opacity(hintOpacity(at: t))
                    .position(x: size.width / 2, y: g.restTop + offset - 46)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// The hint fades in once the dome has risen, and out at once when it is swiped away.
    private func hintOpacity(at t: Double) -> Double {
        if let exitAt = domeExitAt { return 1 - ZoomPath.ease((t - exitAt) / 0.2) }
        guard let shownAt = domeShownAt else { return 0 }
        return ZoomPath.ease((t - shownAt - 0.5) / 0.6)
    }

    private func hint(bob: CGFloat) -> some View {
        Button(action: passGate) {
            VStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .offset(y: bob - 1)
                Text("Swipe up to enter")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 1)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(phase != .gate)
        .accessibilityLabel("Enter")
    }

    /// A soft shade at the top (under the status bar) and bottom (under the dome and its hint)
    /// of the bright city while the dome waits.
    private func gateShadeLayer(size: CGSize) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * 0.42)
        }
        .frame(width: size.width, height: size.height)
        .opacity(gateShade)
        .allowsHitTesting(false)
    }

    // MARK: Copy

    private func copy(size: CGSize, metrics: StageMetrics) -> some View {
        let top = size.height / 2 + Self.copyTop * metrics.scale
        return Color.clear
            .frame(width: size.width, height: 0)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if let headline {
                        HeadlineView(title: headline.title, subtitle: headline.subtitle)
                            .id(headline)
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .modifier(active: Soften(amount: 1), identity: Soften(amount: 0))
                                    .animation(.smooth(duration: 0.35))
                            ))
                    }
                }
            }
            .position(x: size.width / 2, y: top)
            .allowsHitTesting(false)
    }

    private func show(_ next: Headline?) {
        withAnimation(.smooth(duration: 0.35)) { headline = next }
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

    // MARK: Touch

    /// Swipe the dome up at the gate; once everyone is in orbit, drag around the middle to spin
    /// them, the globe with them, and let go to coast.
    private func dragGesture(around center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                switch phase {
                case .gate:
                    domeLift.move(to: value.translation.height, at: now)
                    let past = -value.translation.height > Self.threshold
                    if past != pastThreshold { pastThreshold = past }
                case .ready:
                    let finger = Double(atan2(value.location.y - center.y, value.location.x - center.x))
                    spin.drag(finger: finger, at: now)
                default:
                    break
                }
            }
            .onEnded { value in
                switch phase {
                case .gate:
                    let lifted = -value.translation.height
                    let flicked = value.predictedEndTranslation.height < -260
                    if lifted > Self.threshold || flicked {
                        passGate()
                    } else {
                        domeLift.release(at: now)
                        pastThreshold = false
                    }
                case .ready:
                    // Angular speed around the middle: the finger's speed across the line to it.
                    let rx = value.location.x - center.x, ry = value.location.y - center.y
                    let reach = max(rx * rx + ry * ry, 900)
                    let omega = Double((rx * value.velocity.height - ry * value.velocity.width) / reach)
                    spin.release(velocity: omega, at: now)
                default:
                    break
                }
            }
    }

    /// At the gate, a tap on the dome enters. Once everyone is in orbit, tapping a friend gives
    /// them the middle, and tapping Earth among them comes back.
    private func tap(at location: CGPoint, size: CGSize) {
        switch phase {
        case .gate:
            if location.y > DomeGeometry(size: size).restTop - 70 { passGate() }
        case .ready:
            guard let id = bubble(at: location, size: size) else { return }
            let middle = focus ?? OrbitChoreography.earth
            guard id != middle else { return }
            if id == OrbitChoreography.earth {
                focus = nil
                stageScene = .bloom
                if mode == .onboarding { show(.meet) }
            } else {
                focus = id
                stageScene = .focus(id)
                if mode == .onboarding { show(.focus(id)) }
            }
        default:
            break
        }
    }

    /// Who is under `location`, as the stage draws them (turned by the spin). The smallest wins,
    /// so a friend overlapping the middle's glass is still theirs to tap.
    private func bubble(at location: CGPoint, size: CGSize) -> Int? {
        let metrics = StageMetrics(slot: CGRect(origin: .zero, size: size))
        let t = now
        let bubbles = BubbleStage.turned(engine.snapshot(at: t), by: spin.angle(at: t))
        let hits = bubbles.filter { bubble in
            guard bubble.radius > 4, bubble.id == OrbitChoreography.earth || WorldPhoto.hasPhoto(bubble.id) else {
                return false
            }
            let c = metrics.point(bubble.center)
            return hypot(location.x - c.x, location.y - c.y) <= bubble.radius * metrics.scale + 8
        }
        return hits.min { $0.radius < $1.radius }?.id
    }

    /// Debug builds: a long press tries the next of the globe's colours.
    private func cyclePalette() {
        guard phase == .ready else { return }
        let next = palette.next
        paletteName = next.name
        let index = (GlobePalette.all.firstIndex(of: next) ?? 0) + 1
        withAnimation(.smooth(duration: 0.25)) { paletteNote = "Globe: \(next.name) (\(index) of \(GlobePalette.all.count))" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if paletteNote?.hasPrefix("Globe: \(next.name)") == true {
                withAnimation(.smooth(duration: 0.4)) { paletteNote = nil }
            }
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

    /// The city, rendered behind its cover at every view the opening passes through (MapKit loads
    /// as it goes, and the rise showed grey wedges of ground it hadn't loaded yet), and the zoom's
    /// imagery fetched meanwhile; then the dome rises and waits for the swipe.
    private func playIntro() async {
        let size = stageSize
        let diagonal = hypot(size.width, size.height)
        let city = CityMapController()
        self.city = city
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if phase == .loading { withAnimation(.easeIn(duration: 0.4)) { showLoader = true } }
        }
        // It starts at the handover camera, looking straight down: the zoom's imagery can be
        // fetched as soon as the map knows its scale.
        _ = await waitUntil(3, { city.handoffEstimate != nil })
        imagery.fetch(handoff: city.handoffEstimate ?? 3.5, diagonal: diagonal)
        _ = await waitUntil(4, { city.isReady })
        city.jump(to: EarthZoom.midCamera)
        _ = await waitUntil(3, { city.isReady })
        city.jump(to: EarthZoom.startCamera)
        _ = await waitUntil(5, { city.isReady })
        guard await waitUntil(4, { imagery.isComplete }) else { return }

        phase = .gate
        withAnimation(.easeOut(duration: 0.8)) {
            cityCover = 0
            showLoader = false
            gateShade = 1
        }
        showDome(after: 0.45)
    }

    /// The dome rises from below the screen, and its hint fades in above it.
    private func showDome(after delay: Double) {
        domeLift = EarthLift()
        domeExitAt = nil
        domeShownAt = now + delay
        domeVisible = true
        pastThreshold = false
    }

    /// Swiped (or tapped): the dome sweeps up off the screen over the city, the map rises, and the
    /// zoom pulls back to the globe.
    private func passGate() {
        guard phase == .gate else { return }
        phase = .zooming
        let t = now
        domeExitFrom = domeOffset(at: t, DomeGeometry(size: stageSize))
        domeExitAt = t
        withAnimation(.easeInOut(duration: 0.7)) { gateShade = 0 }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        sequence?.cancel()
        sequence = Task { @MainActor in
            guard await pause(0.3), let city else { return }
            city.rise()
            guard await pause(EarthZoom.rise + 0.05) else { return }
            domeVisible = false
            let size = stageSize
            let handoff = city.metersPerPoint() ?? city.handoffEstimate ?? 3.5
            path = ZoomPath(startScale: handoff, levels: imagery.levels, rest: restGlobe(size: size), size: size)
            zoomStart = now
            guard await pause(EarthZoom.zoomOut * 0.8) else { return }
            show(.space)
            guard await pause(EarthZoom.zoomOut * 0.2 + 0.15) else { return }
            await popPinsAndLiftOff()
        }
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
        show(.space)
        await popPinsAndLiftOff()
    }

    private func popPinsAndLiftOff() async {
        stageScene = .pins
        guard await pause(1.4) else { return }
        stageScene = .bloom
        bloomStart = now
        phase = .ready
        withAnimation(.easeInOut(duration: 1.0)) { gridOpacity = 1 }
        show(.meet)
        guard await pause(1.2) else { return }
        withAnimation(.smooth(duration: 0.6)) { showFooter = true }
    }

    /// Back to Earth in the middle if a friend has it, everyone melts back into Earth, the globe
    /// pulls back into the city, the dome rises again, then the app takes over.
    private func finish() {
        guard phase == .ready else { return }
        phase = .leaving
        sequence?.cancel()
        sequence = Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) { showFooter = false }
            show(nil)
            withAnimation(.easeInOut(duration: 0.8)) { gridOpacity = 0 }
            if focus != nil {
                focus = nil
                stageScene = .bloom
                guard await pause(0.8) else { return }
            }
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
            withAnimation(.easeInOut(duration: EarthZoom.rise)) { gateShade = 1 }
            guard await pause(EarthZoom.rise * 0.6) else { return }
            showDome(after: 0)
            guard await pause(1.4) else { return }
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

/// The words under the constellation: the title, then the subtitle, each easing in out of a blur.
private struct HeadlineView: View {
    let title: String
    let subtitle: String?
    @State private var shown = false

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .foregroundStyle(Theme.worldInk)
                .modifier(Soften(amount: shown ? 0 : 1))
                .animation(.smooth(duration: 0.6).delay(0.2), value: shown)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(Theme.worldInkSecondary)
                    .modifier(Soften(amount: shown ? 0 : 1))
                    .animation(.smooth(duration: 0.6).delay(0.45), value: shown)
            }
        }
        .font(.system(size: 27, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .lineSpacing(1)
        .fixedSize()
        .onAppear { shown = true }
    }
}

/// Faded and blurred by `amount` (0 is sharp and fully there).
private struct Soften: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 6 * amount)
    }
}

/// The gate's dome: a big disc of clear glass, its top showing above the bottom of the screen like
/// Wabi's, bending the city behind it (real Liquid Glass on iOS 26; frosted before), with a soft
/// window light along its top rim.
private struct GateDome: View {
    let diameter: CGFloat

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: diameter, height: diameter)
                    .glassEffect(.clear, in: Circle())
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: diameter, height: diameter)
            }
        }
        .overlay {
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1.5
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
