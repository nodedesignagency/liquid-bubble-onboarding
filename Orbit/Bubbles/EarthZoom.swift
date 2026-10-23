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

    /// Seconds: the city flattening and rising, the zoom out to the globe, and the zoom back in.
    static let rise: Double = 1.3
    static let zoomOut: Double = 3.6
    static let zoomBack: Double = 3.0
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

/// Owns the live map, reports when the city has fully rendered, measures its scale, and moves its
/// camera with UIKit animations.
final class CityMapController: NSObject, MKMapViewDelegate {
    let mapView = MKMapView(frame: .zero)
    /// The city at the start camera has fully rendered.
    private(set) var isRendered = false
    /// Metres per screen point at the handover camera, estimated as soon as the map has a size
    /// (from the start camera: across the middle, pitch doesn't change the horizontal scale).
    private(set) var handoffEstimate: Double?

    override init() {
        super.init()
        mapView.delegate = self
        mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        mapView.isUserInteractionEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.camera = EarthZoom.startCamera
    }

    func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
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
/// covers the screen, and every finer one over it, each fading out toward its edge so it melts into
/// the coarser one under it.
struct ZoomStack: View {
    var levels: [ZoomImagery.Level]
    var metersPerPoint: Double
    /// Clockwise, degrees.
    var roll: Double
    var center: CGPoint
    var size: CGSize

    /// A level covers the screen while its solid middle (80% of its radius) reaches the corners.
    static func drawn(_ levels: [ZoomImagery.Level], metersPerPoint: Double, diagonal: CGFloat) -> [ZoomImagery.Level] {
        let sides = levels.map { $0.side * CGFloat($0.metersPerPoint / metersPerPoint) }
        let base = sides.firstIndex { $0 * 0.8 >= diagonal } ?? (levels.count - 1)
        guard base >= 0 else { return [] }
        // Coarsest first: the base, then finer ones over it while they are still worth drawing.
        return (0...base).reversed().filter { $0 == base || sides[$0] > 6 }.map { levels[$0] }
    }

    var body: some View {
        let diagonal = hypot(size.width, size.height)
        let shown = Self.drawn(levels, metersPerPoint: metersPerPoint, diagonal: diagonal)
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, level in
                let k = CGFloat(level.metersPerPoint / metersPerPoint)
                let side = level.side * k
                Image(uiImage: level.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .mask {
                        if index == 0 {
                            Rectangle()
                        } else {
                            RadialGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                           center: .center, startRadius: 0, endRadius: side / 2)
                        }
                    }
                    .position(x: center.x - level.cityOffset.x * k, y: center.y - level.cityOffset.y * k)
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
/// to orbit keep one steady sense of speed.
struct ZoomPath {
    /// Metres per point at the handover (measured on the map) and of the globe at rest.
    var startScale: Double
    var endScale: Double
    /// The snapshots dissolve into the globe between these scales (the coarsest snapshot stops
    /// covering the screen at the second).
    var globeFrom: Double
    var globeTo: Double
    /// The globe at rest, on screen.
    var rest: GlobeState
    /// The screen's middle, where the city is during the zoom.
    var screenCenter: CGPoint

    /// The camera's focal length for the globe, in points: fixed, so it pulls back like a camera.
    var focal: CGFloat { rest.radius * CGFloat((rest.distance * rest.distance - 1).squareRoot()) }

    init(startScale: Double, levels: [ZoomImagery.Level], rest: GlobeState, size: CGSize) {
        self.rest = rest
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let focal = Double(rest.radius) * (rest.distance * rest.distance - 1).squareRoot()
        self.startScale = startScale
        endScale = EarthZoom.earthRadius * (rest.distance - 1) / focal
        let diagonal = Double(hypot(size.width, size.height))
        if let coarsest = levels.last {
            let leaves = coarsest.metersPerPoint * Double(coarsest.side) * 0.8 / diagonal
            globeTo = max(leaves, startScale * 1.5)
            globeFrom = globeTo / 1.6
        } else {
            // No snapshots (offline): bring the globe in early in the zoom.
            globeFrom = startScale * 4
            globeTo = startScale * 40
        }
    }

    static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    func scale(at u: Double) -> Double {
        exp(log(startScale) + (log(endScale) - log(startScale)) * Self.ease(u))
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

    /// How much of the globe shows over the snapshots.
    func globeOpacity(at u: Double) -> Double {
        between(scale(at: u), globeFrom, globeTo)
    }

    /// The globe at `u`: facing the city at the screen's middle while it takes over from the
    /// snapshots, then drifting to its place, turning to face its resting point.
    func globe(at u: Double) -> GlobeState {
        let s = scale(at: u)
        let distance = 1 + s * Double(focal) / EarthZoom.earthRadius
        let radius = focal / CGFloat((distance * distance - 1).squareRoot())
        let k = between(s, globeTo, endScale)
        var state = rest
        state.distance = distance
        state.radius = radius
        state.center = CGPoint(x: screenCenter.x + (rest.center.x - screenCenter.x) * CGFloat(k),
                               y: screenCenter.y + (rest.center.y - screenCenter.y) * CGFloat(k))
        state.latitude = EarthZoom.city.latitude + (rest.latitude - EarthZoom.city.latitude) * k
        state.longitude = EarthZoom.city.longitude + (rest.longitude - EarthZoom.city.longitude) * k
        state.roll = roll(at: u)
        state.glow = rest.glow * k
        state.opacity = globeOpacity(at: u)
        return state
    }
}
