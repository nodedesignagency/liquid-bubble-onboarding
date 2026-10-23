import SwiftUI
import MapKit

/// v3's opening, after Bump's Earth zoom: a real city in 3D (Apple's map) pulling back to a
/// glowing globe. MapKit streams its tiles as the camera moves, and a fast zoom through every
/// level outran them (the user's recording was grey for three seconds), so the zoom is drawn here
/// instead, from imagery fetched before it starts:
///
/// 1. The city: a live `MKMapView` (3D Paris), shown only once it has rendered.
/// 2. While it holds, satellite snapshots of the same spot at widening spans are fetched
///    (`ZoomImagery`), each about 3x wider than the last, up to a few thousand kilometres. The
///    first ones are drawn in 3D like the live map, so the handover is seamless.
/// 3. The map flattens to looking straight down and rises a little (still MapKit), then hands
///    over to the snapshots, which zoom out smoothly (`ZoomStack`). The hologram fades in over
///    them as a flat map with the same projection, scale and turn (`GlobeState.flatness`), so
///    the photo turns into it coast on coast; pulling back further, it curls into the globe
///    (`HoloGlobeView`), which drifts to its place on the page.
///
/// Everything after the handover is a pure function of time (`ZoomPath`), so nothing can load late.
enum EarthZoom {
    /// The Eiffel Tower, seen across the river from a few rooftops up. Other Flyover cities that
    /// look good (latitude, longitude): New York's Lower Manhattan (40.7061, -74.0087), San
    /// Francisco's Golden Gate (37.8078, -122.4750), Tokyo Tower (35.6586, 139.7454). The real app
    /// would start where the user is.
    static let city = CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)
    static let heading: Double = 330
    static let startDistance: Double = 1_500
    static let startPitch: CGFloat = 62
    /// Where MapKit hands over to the snapshots: straight down, a little higher.
    static let handoffDistance: Double = 2_600

    static var startCamera: MKMapCamera {
        MKMapCamera(lookingAtCenter: city, fromDistance: startDistance, pitch: startPitch, heading: heading)
    }
    static var handoffCamera: MKMapCamera {
        MKMapCamera(lookingAtCenter: city, fromDistance: handoffDistance, pitch: 0, heading: heading)
    }
    /// Halfway through the rise: rendered once while the city is still covered, with the other two,
    /// so the rise never shows ground MapKit hasn't loaded (the user saw grey wedges open up).
    static var midCamera: MKMapCamera {
        MKMapCamera(lookingAtCenter: city, fromDistance: (startDistance + handoffDistance) / 2, pitch: startPitch / 2, heading: heading)
    }

    /// Seconds: the city flattening and rising, the zoom out to the globe, and the zoom back in.
    static let rise: Double = 1.3
    static let zoomOut: Double = 5.0
    static let zoomBack: Double = 3.6
    /// The map's heading turns the snapshots and the globe on screen at first; this unwinds to
    /// north up over the first three quarters of the zoom.
    static var startRoll: Double { 360 - heading }

    /// Each snapshot covers this many times the span of the one before, up to `largestSpan`.
    static let spanStep: Double = 3.2
    static let largestSpan: Double = 6_000_000
    /// Snapshots narrower than this are drawn in 3D like the live map (the same photogrammetry and
    /// grading), so the handover from the map doesn't jump; wider ones are flat satellite imagery.
    static let realisticSpan: Double = 20_000
    static let earthRadius: Double = 6_371_000

    /// The point `meters` from `start` along `bearing` (degrees clockwise from north).
    static func destination(from start: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        let angle = meters / earthRadius, theta = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180, lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angle) + cos(lat1) * sin(angle) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angle) * cos(lat1), cos(angle) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

// MARK: - The city

/// Owns the live map, reports when the view it was last given has fully rendered, measures its
/// scale, and moves its camera with UIKit animations. It starts at the handover camera, so the
/// screen can render the rise's cameras one by one behind its cover (see `jump(to:)`) before
/// showing the start.
final class CityMapController: NSObject, MKMapViewDelegate {
    let mapView = MKMapView(frame: .zero)
    /// The camera last jumped to has fully rendered.
    private(set) var isRendered = false
    /// MapKit started drawing since the last jump. It doesn't when it already has the view, so
    /// `isReady` stops waiting shortly after a jump that never started rendering.
    private var startedRendering = false
    private var jumpedAt = Date.timeIntervalSinceReferenceDate
    /// Metres per screen point at the handover camera, measured as soon as the map has a size
    /// (across the middle, pitch doesn't change the horizontal scale).
    private(set) var handoffEstimate: Double?

    override init() {
        super.init()
        mapView.delegate = self
        mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        mapView.isUserInteractionEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.camera = EarthZoom.handoffCamera
    }

    /// Shows `camera` at once; `isRendered` turns true again once MapKit has drawn it all.
    func jump(to camera: MKMapCamera) {
        isRendered = false
        startedRendering = false
        jumpedAt = Date.timeIntervalSinceReferenceDate
        mapView.camera = camera
    }

    /// The camera last jumped to is on screen in full: rendered, or never needed rendering.
    var isReady: Bool {
        isRendered || (!startedRendering && Date.timeIntervalSinceReferenceDate - jumpedAt > 0.8)
    }

    func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
        startedRendering = true
        estimateIfNeeded()
    }

    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        estimateIfNeeded()
        if fullyRendered { isRendered = true }
    }

    private func estimateIfNeeded() {
        guard handoffEstimate == nil, let measured = metersPerPoint() else { return }
        handoffEstimate = measured * EarthZoom.handoffDistance / mapView.camera.centerCoordinateDistance
    }

    /// Metres per screen point across the middle of the map, along the screen's horizontal.
    func metersPerPoint() -> Double? {
        guard mapView.bounds.width > 0 else { return nil }
        let center = mapView.convert(EarthZoom.city, toPointTo: mapView)
        let probe = EarthZoom.destination(from: EarthZoom.city, bearing: mapView.camera.heading + 90, meters: 200)
        let point = mapView.convert(probe, toPointTo: mapView)
        let distance = Double(hypot(point.x - center.x, point.y - center.y))
        guard distance.isFinite, distance > 1 else { return nil }
        return 200 / distance
    }

    /// Flatten to looking straight down and rise to the handover camera.
    func rise() {
        UIView.animate(withDuration: EarthZoom.rise, delay: 0, options: [.curveEaseInOut]) {
            self.mapView.camera = EarthZoom.handoffCamera
        }
    }

    /// Back down to the start camera, tilting up to the tower.
    func settle() {
        UIView.animate(withDuration: EarthZoom.rise, delay: 0, options: [.curveEaseInOut]) {
            self.mapView.camera = EarthZoom.startCamera
        }
    }
}

struct CityMapView: UIViewRepresentable {
    let controller: CityMapController

    func makeUIView(context: Context) -> MKMapView { controller.mapView }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
}

// MARK: - The zoom's imagery

/// Satellite snapshots of the city at widening spans, fetched while the city holds.
final class ZoomImagery {
    struct Level {
        let image: UIImage
        /// Metres per image point at the city (east-west, which Web Mercator keeps north-south
        /// too), measured on the snapshot itself.
        let metersPerPoint: Double
        /// Where the city is in the image, relative to its middle, in image points.
        let cityOffset: CGPoint
        /// The image's side, in points.
        let side: CGFloat

        /// Metres across, at the city.
        var span: Double { Double(side) * metersPerPoint }
    }

    /// Finest first.
    private(set) var levels: [Level] = []
    private(set) var started = false
    private var pending = 0
    private var snapshotters: [MKMapSnapshotter] = []

    var isComplete: Bool { started && pending == 0 }

    /// `handoff` is metres per point when MapKit hands over; `diagonal` the screen's, in points.
    /// The first snapshot covers the screen's diagonal with room to spare at that scale.
    func fetch(handoff: Double, diagonal: CGFloat) {
        guard !started else { return }
        started = true
        var span = handoff * Double(diagonal) * 1.45
        var spans: [Double] = []
        while span <= EarthZoom.largestSpan {
            spans.append(span)
            span *= EarthZoom.spanStep
        }
        pending = spans.count
        for (index, span) in spans.enumerated() {
            // The first is seen largest, right as MapKit hands over, so it gets the most pixels.
            request(span: span, side: index == 0 ? 1_100 : 800, scale: index == 0 ? 3 : 2)
        }
    }

    private func request(span: Double, side: CGFloat, scale: CGFloat) {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: EarthZoom.city, latitudinalMeters: span, longitudinalMeters: span)
        options.size = CGSize(width: side, height: side)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: span < EarthZoom.realisticSpan ? .realistic : .flat)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: scale)
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotters.append(snapshotter)
        snapshotter.start(with: .main) { [weak self] snapshot, _ in
            guard let self else { return }
            self.pending -= 1
            guard let snapshot, let level = Self.measure(snapshot, span: span) else { return }
            self.levels.append(level)
            self.levels.sort { $0.metersPerPoint < $1.metersPerPoint }
        }
    }

    /// The snapshot's scale at the city: a step east, a tenth of the span, in image points.
    private static func measure(_ snapshot: MKMapSnapshotter.Snapshot, span: Double) -> Level? {
        let city = EarthZoom.city
        let size = snapshot.image.size
        guard size.width > 1 else { return nil }
        let c = snapshot.point(for: city)
        let latitude = city.latitude * .pi / 180
        let stepEast = span * 0.1 / (EarthZoom.earthRadius * cos(latitude))   // radians of longitude
        let east = snapshot.point(for: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude + stepEast * 180 / .pi))
        let pointsPerRadian = Double(east.x - c.x) / stepEast
        guard pointsPerRadian.isFinite, pointsPerRadian > 1 else { return nil }
        return Level(image: snapshot.image,
                     metersPerPoint: EarthZoom.earthRadius * cos(latitude) / pointsPerRadian,
                     cityOffset: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
                     side: size.width)
    }
}

/// The snapshots, zoomed to `metersPerPoint` with the city at `center`: the finest one that still
/// covers the screen, and the finer ones over it fading out as they shrink below covering it.
/// Apple's imagery is graded differently at each span, so a finer snapshot left sitting in the
/// middle read as a patch that hadn't loaded; crossfading from one span to the next doesn't.
struct ZoomStack: View {
    var levels: [ZoomImagery.Level]
    var metersPerPoint: Double
    /// Clockwise, degrees.
    var roll: Double
    var center: CGPoint
    var size: CGSize

    struct Layer: Identifiable {
        let level: ZoomImagery.Level
        let opacity: Double
        let isBase: Bool
        var id: Double { level.metersPerPoint }
    }

    /// Coarsest first. A level covers the screen while its solid middle (80% of its radius)
    /// reaches the corners; a finer one fades out between covering and covering half.
    static func layers(_ levels: [ZoomImagery.Level], metersPerPoint: Double, diagonal: CGFloat) -> [Layer] {
        let cover = levels.map { Double($0.side) * $0.metersPerPoint / metersPerPoint * 0.8 / Double(diagonal) }
        let base = cover.firstIndex { $0 >= 1 } ?? (levels.count - 1)
        guard base >= 0 else { return [] }
        var out = [Layer(level: levels[base], opacity: 1, isBase: true)]
        for index in stride(from: base - 1, through: 0, by: -1) {
            let fade = ZoomPath.ease((log(max(cover[index], 1e-6)) - log(0.5)) / (log(1.0) - log(0.5)))
            if fade > 0.01 {
                out.append(Layer(level: levels[index], opacity: fade, isBase: false))
            }
        }
        return out
    }

    var body: some View {
        let diagonal = hypot(size.width, size.height)
        ZStack {
            ForEach(Self.layers(levels, metersPerPoint: metersPerPoint, diagonal: diagonal)) { layer in
                let k = CGFloat(layer.level.metersPerPoint / metersPerPoint)
                let side = layer.level.side * k
                Image(uiImage: layer.level.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .mask {
                        if layer.isBase {
                            Rectangle()
                        } else {
                            RadialGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 1)],
                                           center: .center, startRadius: 0, endRadius: side / 2)
                        }
                    }
                    .opacity(layer.opacity)
                    .position(x: center.x - layer.level.cityOffset.x * k, y: center.y - layer.level.cityOffset.y * k)
            }
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(roll), anchor: UnitPoint(x: center.x / max(size.width, 1), y: center.y / max(size.height, 1)))
        .allowsHitTesting(false)
    }
}

// MARK: - The path

/// The zoom from the handover to the globe at rest, as a function of its progress `u` (0 at the
/// handover, 1 at rest; the zoom back runs it backwards). Scale is eased in log space, so rooftops
/// to orbit keep one steady sense of speed, slowing while the photo turns into the hologram so that
/// moment reads:
///
/// 1. The flat snapshots (`ZoomStack`) pull back from the city.
/// 2. While the widest snapshot still covers the screen, the hologram fades in over them as a flat
///    map in the same projection, at the same scale and turn (`hologramFrom`...`hologramTo`): the
///    photo turns into the glowing map in place, coast on coast. (A sphere over a flat photo
///    doubled the coastlines; a ring sweeping out from the city was hated.)
/// 3. Pulling back further, the map curls into the sphere (`curlTo`) while the globe's edge is
///    still off the screen, so the curl never shows an edge; then its aura grows in, and it drifts
///    to its place on the page and turns to its resting view (from `driftFrom`).
struct ZoomPath {
    /// Metres per point at the handover (measured on the map) and of the globe at rest.
    var startScale: Double
    var endScale: Double
    var hologramFrom: Double
    var hologramTo: Double
    var curlTo: Double
    var glowTo: Double
    var driftFrom: Double
    /// The globe at rest, on screen.
    var rest: GlobeState
    /// The screen's middle, where the city is during the zoom.
    var screenCenter: CGPoint
    /// How far through the zoom (in log scale) at each of 257 even steps of `u`.
    private var depths: [Double] = []

    /// The camera's focal length for the globe, in points: fixed, so it pulls back like a camera.
    var focal: CGFloat { rest.radius * CGFloat((rest.distance * rest.distance - 1).squareRoot()) }

    init(startScale: Double, levels: [ZoomImagery.Level], rest: GlobeState, size: CGSize) {
        self.rest = rest
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let diagonal = Double(hypot(size.width, size.height))
        let focal = Double(rest.radius) * (rest.distance * rest.distance - 1).squareRoot()
        self.startScale = startScale
        endScale = EarthZoom.earthRadius * (rest.distance - 1) / focal
        // The scale at which the globe's edge is `radius` points from its centre.
        func scale(forRadius radius: Double) -> Double {
            EarthZoom.earthRadius * ((1 + (focal / radius) * (focal / radius)).squareRoot() - 1) / focal
        }
        // The curl ends with the globe's edge still just off the screen's corners.
        curlTo = scale(forRadius: diagonal / 2 * 1.12)
        // The hologram is in before the widest snapshot stops covering the screen (and no
        // earlier than a scale where its coastlines are crisp, about 2 km a point).
        if let widest = levels.last {
            hologramTo = min(widest.span * 0.8 / diagonal * 0.92, curlTo / 1.3)
        } else {
            hologramTo = curlTo / 1.6
        }
        hologramTo = max(hologramTo, startScale * 2)
        hologramFrom = max(hologramTo / 2.6, startScale * 1.4)
        glowTo = scale(forRadius: 200)
        driftFrom = scale(forRadius: 240)

        // The speed of the zoom: a smooth bell (smoothstep's), with a dip while the photo turns
        // into the hologram and curls into the globe, placed by bisection so the zoom, slowed by
        // it, is in the middle of that right at the slowest point.
        let total = log(endScale) - log(startScale)
        let middle = (log((hologramFrom * curlTo).squareRoot()) - log(startScale)) / total
        func profile(dip: Double) -> [Double] {
            let steps = 256
            var cumulative = [0.0]
            for step in 0..<steps {
                let u = (Double(step) + 0.5) / Double(steps)
                let g = (u - dip) / 0.17
                let speed = 6 * u * (1 - u) * (1 - 0.8 * exp(-g * g))
                cumulative.append(cumulative[step] + speed)
            }
            let sum = cumulative[steps]
            return cumulative.map { $0 / sum }
        }
        var lo = 0.1, hi = 0.95
        for _ in 0..<30 {
            let dip = (lo + hi) / 2
            let reached = profile(dip: dip)[Int(dip * 256)]
            if reached < middle { lo = dip } else { hi = dip }
        }
        depths = profile(dip: (lo + hi) / 2)
    }

    static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func depth(atProgress u: Double) -> Double {
        let x = min(max(u, 0), 1) * Double(depths.count - 1)
        let i = min(Int(x), depths.count - 2)
        let f = x - Double(i)
        return depths[i] * (1 - f) + depths[i + 1] * f
    }

    func scale(at u: Double) -> Double {
        exp(log(startScale) + (log(endScale) - log(startScale)) * depth(atProgress: u))
    }

    /// How far through the zoom the scale is, in log space (0 at the handover, 1 at rest).
    private func depth(_ scale: Double) -> Double {
        (log(scale) - log(startScale)) / (log(endScale) - log(startScale))
    }

    private func between(_ scale: Double, _ a: Double, _ b: Double) -> Double {
        Self.ease((log(scale) - log(a)) / max(log(b) - log(a), 1e-6))
    }

    /// Turned on screen like the map's heading at first, unwinding to north up.
    func roll(at u: Double) -> Double {
        EarthZoom.startRoll * (1 - Self.ease(depth(scale(at: u)) / 0.75))
    }

    /// The flat snapshots are needed until the hologram covers them.
    func showsSnapshots(at u: Double) -> Bool { scale(at: u) < hologramTo }

    /// The globe at `u`: a flat map over the snapshots at first, fading in, then curling into the
    /// sphere, its aura growing, drifting to its place and turning to face its resting point.
    func globe(at u: Double) -> GlobeState {
        let s = scale(at: u)
        let distance = 1 + s * Double(focal) / EarthZoom.earthRadius
        let radius = focal / CGFloat((distance * distance - 1).squareRoot())
        let k = between(s, driftFrom, endScale)
        var state = rest
        state.distance = distance
        state.radius = radius
        state.center = CGPoint(x: screenCenter.x + (rest.center.x - screenCenter.x) * CGFloat(k),
                               y: screenCenter.y + (rest.center.y - screenCenter.y) * CGFloat(k))
        state.latitude = EarthZoom.city.latitude + (rest.latitude - EarthZoom.city.latitude) * k
        state.longitude = EarthZoom.city.longitude + (rest.longitude - EarthZoom.city.longitude) * k
        state.roll = roll(at: u)
        state.opacity = between(s, hologramFrom, hologramTo)
        state.flatness = 1 - between(s, hologramTo, curlTo)
        state.glow = rest.glow * between(s, curlTo, glowTo)
        return state
    }
}
