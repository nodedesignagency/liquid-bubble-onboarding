import SwiftUI
import MapKit

/// v3's opening, after Bump's Earth zoom: a real city in 3D (Apple's map) pulling back to a
/// glowing globe. MapKit streams its tiles as the camera moves, and a fast zoom through every
/// level outran them (the user's recording was grey for three seconds), so the zoom is drawn here
/// instead, from imagery fetched before it starts:
///
/// 1. The city: a live `MKMapView` (3D Paris), shown only once it has rendered.
/// 2. While it holds, satellite snapshots of the same spot at widening spans are fetched
///    (`ZoomImagery`), each about 3x wider than the last, up to a few thousand kilometres.
/// 3. The map flattens to looking straight down and rises a little (still MapKit), then hands
///    over to the snapshots, which zoom out smoothly (`ZoomStack`), and those dissolve into the
///    holographic globe (`HoloGlobeView`), which pulls back to its place on the page.
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
    static let zoomOut: Double = 4.6
    static let zoomBack: Double = 3.4
    /// The map's heading turns the snapshots and the globe on screen at first; this unwinds to
    /// north up over the first three quarters of the zoom.
    static var startRoll: Double { 360 - heading }

    /// Each snapshot covers this many times the span of the one before, up to `largestSpan`.
    static let spanStep: Double = 3.2
    static let largestSpan: Double = 4_600_000
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
        /// Metres per image point, measured on the snapshot itself.
        let metersPerPoint: Double
        /// Where the city is in the image, relative to its middle, in image points.
        let cityOffset: CGPoint
        /// The image's side, in points.
        let side: CGFloat
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
        options.mapType = .satellite
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: scale)
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotters.append(snapshotter)
        snapshotter.start(with: .main) { [weak self] snapshot, _ in
            guard let self else { return }
            self.pending -= 1
            guard let snapshot else { return }
            let c = snapshot.point(for: EarthZoom.city)
            let probe = EarthZoom.destination(from: EarthZoom.city, bearing: 90, meters: span * 0.1)
            let p = snapshot.point(for: probe)
            let distance = Double(hypot(p.x - c.x, p.y - c.y))
            guard distance > 1 else { return }
            let size = snapshot.image.size
            self.levels.append(Level(image: snapshot.image, metersPerPoint: span * 0.1 / distance,
                                     cityOffset: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
                                     side: size.width))
            self.levels.sort { $0.metersPerPoint < $1.metersPerPoint }
        }
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
/// to orbit keep one steady sense of speed, except that it slows while the globe sweeps out from
/// the city over the snapshots (a glowing ring turning the real Earth into the globe), so that
/// moment reads.
struct ZoomPath {
    /// Metres per point at the handover (measured on the map) and of the globe at rest.
    var startScale: Double
    var endScale: Double
    /// The globe sweeps out from the city between these scales; at the second the coarsest
    /// snapshot stops covering the screen, and the globe has it all.
    var revealFrom: Double
    var revealTo: Double
    /// The globe at rest, on screen.
    var rest: GlobeState
    /// The screen's middle, where the city is during the zoom, and how far the sweep must reach.
    var screenCenter: CGPoint
    var reach: CGFloat
    /// How far through the zoom (in log scale) at each of 257 even steps of `u`.
    private var depths: [Double] = []

    /// The camera's focal length for the globe, in points: fixed, so it pulls back like a camera.
    var focal: CGFloat { rest.radius * CGFloat((rest.distance * rest.distance - 1).squareRoot()) }

    init(startScale: Double, levels: [ZoomImagery.Level], rest: GlobeState, size: CGSize) {
        self.rest = rest
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        reach = hypot(size.width, size.height) / 2 + 40
        let focal = Double(rest.radius) * (rest.distance * rest.distance - 1).squareRoot()
        self.startScale = startScale
        endScale = EarthZoom.earthRadius * (rest.distance - 1) / focal
        let diagonal = Double(hypot(size.width, size.height))
        if let coarsest = levels.last {
            let leaves = coarsest.metersPerPoint * Double(coarsest.side) * 0.8 / diagonal
            revealTo = max(leaves, startScale * 2)
        } else {
            // No snapshots (offline): sweep in early.
            revealTo = startScale * 40
        }
        revealFrom = max(revealTo / 7, startScale * 1.2)

        // The speed of the zoom: a smooth bell (smoothstep's), with a dip where the sweep happens.
        let total = log(endScale) - log(startScale)
        let middle = (log((revealFrom * revealTo).squareRoot()) - log(startScale)) / total
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if Self.ease(mid) < middle { lo = mid } else { hi = mid }
        }
        let dip = (lo + hi) / 2
        var cumulative = [0.0]
        let steps = 256
        for step in 0..<steps {
            let u = (Double(step) + 0.5) / Double(steps)
            let g = (u - dip) / 0.1
            let speed = 6 * u * (1 - u) * (1 - 0.55 * exp(-g * g))
            cumulative.append(cumulative[step] + speed)
        }
        let sum = cumulative[steps]
        depths = cumulative.map { $0 / sum }
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

    /// How far the sweep has gone: 0 before it starts, 1 once the globe has the whole screen.
    func sweep(at u: Double) -> Double {
        let s = scale(at: u)
        guard s > revealFrom else { return 0 }
        return min(max((log(s) - log(revealFrom)) / (log(revealTo) - log(revealFrom)), 0), 1)
    }

    /// The snapshots are needed until the sweep has passed the screen's corners.
    func showsSnapshots(at u: Double) -> Bool { sweep(at: u) < 1 }

    /// The globe at `u`: facing the city at the screen's middle while it sweeps out over the
    /// snapshots, then drifting to its place, turning to face its resting point.
    func globe(at u: Double) -> GlobeState {
        let s = scale(at: u)
        let distance = 1 + s * Double(focal) / EarthZoom.earthRadius
        let radius = focal / CGFloat((distance * distance - 1).squareRoot())
        let k = between(s, revealTo, endScale)
        var state = rest
        state.distance = distance
        state.radius = radius
        state.center = CGPoint(x: screenCenter.x + (rest.center.x - screenCenter.x) * CGFloat(k),
                               y: screenCenter.y + (rest.center.y - screenCenter.y) * CGFloat(k))
        state.latitude = EarthZoom.city.latitude + (rest.latitude - EarthZoom.city.latitude) * k
        state.longitude = EarthZoom.city.longitude + (rest.longitude - EarthZoom.city.longitude) * k
        state.roll = roll(at: u)
        state.glow = rest.glow * k
        let swept = sweep(at: u)
        state.opacity = s > revealFrom ? 1 : 0
        // Eased, so the ring sets off gently from the city and reaches the corners at speed.
        state.reveal = swept < 1 ? (screenCenter, reach * CGFloat(pow(swept, 1.25))) : nil
        return state
    }
}
