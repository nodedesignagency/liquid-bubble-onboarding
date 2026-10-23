import SwiftUI
import MapKit

/// v3's opening, after Bump's Earth zoom: a real city in 3D (Apple's map) pulling back to a
/// glowing globe. MapKit streams its tiles as the camera moves, and a fast zoom through every
/// level outran them (the user's recording was grey for three seconds), so the zoom is drawn here
/// instead, from imagery fetched before it starts:
///
/// 1. The city: a live `MKMapView` (3D Paris), shown only once it has rendered.
/// 2. While it holds, satellite snapshots of the same spot at widening spans are fetched
///    (`ZoomImagery`), each about 3x wider than the last, up to a few thousand kilometres, and one
///    of the whole world. The first is drawn in 3D like the live map, so the handover is seamless.
/// 3. The map flattens to looking straight down and rises a little (still MapKit), then hands
///    over to the snapshots, which zoom out smoothly (`ZoomStack`). Before the Earth's curve
///    could show, the globe takes over with the same snapshots on the sphere (`GlobeImagery`),
///    so the real Earth pulls back into a ball, then dissolves in place into the holographic
///    globe (`HoloGlobeView`) and drifts to its place on the page.
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

    /// Web Mercator's y for a latitude in degrees (radians of the map's height).
    static func mercator(_ latitude: Double) -> Double {
        let phi = min(max(latitude, -85.05), 85.05) * .pi / 180
        return log(tan(.pi / 4 + phi / 2))
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

/// Satellite snapshots of the city at widening spans, and one of the whole world, fetched while
/// the city holds.
final class ZoomImagery {
    struct Level {
        let image: UIImage
        /// The same, for the globe's shader (made once, so it isn't uploaded again every frame).
        let shaderImage: Image
        /// Metres per image point at the city, measured on the snapshot itself.
        let metersPerPoint: Double
        /// Where the city is in the image, relative to its middle, in image points.
        let cityOffset: CGPoint
        /// The image's side, in points.
        let side: CGFloat
        /// Web Mercator, as measured: the city in uv (0...1) and uv per radian of longitude (the
        /// same per Mercator unit north). False if the snapshot didn't measure as Mercator, and then
        /// the globe doesn't use it.
        let cityUV: CGPoint
        let uvPerRadian: Double
        let isMercator: Bool

        /// Metres across, at the city.
        var span: Double { Double(side) * metersPerPoint }
    }

    /// Finest first.
    private(set) var levels: [Level] = []
    /// The whole world, and where it maps.
    private(set) var world: (image: Image, map: GlobeImagery.Map)?
    private(set) var started = false
    private var pending = 0
    private var snapshotters: [MKMapSnapshotter] = []

    var isComplete: Bool { started && pending == 0 }

    /// What the globe draws while it is still the real Earth: the world, and the three widest
    /// regional snapshots (the finer ones are only seen flat, before the globe takes over).
    var globe: GlobeImagery? {
        let layers = levels.filter(\.isMercator).suffix(3).map {
            GlobeImagery.Layer(image: $0.shaderImage, cityUV: $0.cityUV, uvPerRadian: $0.uvPerRadian, span: $0.span)
        }
        guard world != nil || !layers.isEmpty else { return nil }
        return GlobeImagery(world: world?.image, worldMap: world?.map ?? GlobeImagery.Map(u0: 0, uPerRadian: 0, v0: 0, vPerMercator: 0),
                            layers: Array(layers),
                            cityRadians: CGPoint(x: EarthZoom.city.latitude * .pi / 180, y: EarthZoom.city.longitude * .pi / 180))
    }

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
        pending = spans.count + 1
        for (index, span) in spans.enumerated() {
            // The first is seen largest, right as MapKit hands over, so it gets the most pixels.
            request(span: span, side: index == 0 ? 1_100 : 800, scale: index == 0 ? 3 : 2)
        }
        requestWorld()
    }

    private func request(span: Double, side: CGFloat, scale: CGFloat) {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: EarthZoom.city, latitudinalMeters: span, longitudinalMeters: span)
        options.size = CGSize(width: side, height: side)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: span < EarthZoom.realisticSpan ? .realistic : .flat)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: scale)
        start(options) { [weak self] snapshot in
            guard let self, let level = Self.measure(snapshot, span: span) else { return }
            self.levels.append(level)
            self.levels.sort { $0.metersPerPoint < $1.metersPerPoint }
        }
    }

    private func requestWorld() {
        let options = MKMapSnapshotter.Options()
        options.mapRect = .world
        options.size = CGSize(width: 1_536, height: 1_536)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: 2)
        start(options) { [weak self] snapshot in
            guard let self else { return }
            let size = snapshot.image.size
            guard size.width > 1, size.height > 1 else { return }
            func uv(_ latitude: Double, _ longitude: Double) -> CGPoint {
                let p = snapshot.point(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                return CGPoint(x: p.x / size.width, y: p.y / size.height)
            }
            // Fitted on four points and checked on a fifth, so a snapshot that isn't the flat
            // Mercator world (MapKit could draw a globe) is never mapped onto the sphere.
            let west = uv(0, -90), east = uv(0, 90), north = uv(60, 0), south = uv(-60, 0)
            let uPerRadian = Double(east.x - west.x) / .pi
            let u0 = Double(west.x) + uPerRadian * .pi / 2
            let m60 = EarthZoom.mercator(60)
            let vPerMercator = Double(south.y - north.y) / (2 * m60)
            let v0 = Double(north.y) + vPerMercator * m60
            let probe = uv(45, 45)
            guard uPerRadian > 0.05, vPerMercator > 0.05,
                  abs(Double(probe.x) - (u0 + uPerRadian * .pi / 4)) < 0.01,
                  abs(Double(probe.y) - (v0 - vPerMercator * EarthZoom.mercator(45))) < 0.01 else { return }
            self.world = (Image(uiImage: snapshot.image),
                          GlobeImagery.Map(u0: u0, uPerRadian: uPerRadian, v0: v0, vPerMercator: vPerMercator))
        }
    }

    private func start(_ options: MKMapSnapshotter.Options, done: @escaping (MKMapSnapshotter.Snapshot) -> Void) {
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotters.append(snapshotter)
        snapshotter.start(with: .main) { [weak self] snapshot, _ in
            guard let self else { return }
            self.pending -= 1
            if let snapshot { done(snapshot) }
        }
    }

    /// The snapshot's scale and Mercator mapping, measured on it: a step east and a step north of
    /// the city, a tenth of the span each.
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
        let stepNorth = span * 0.1 / EarthZoom.earthRadius * 180 / .pi           // degrees of latitude
        let north = snapshot.point(for: CLLocationCoordinate2D(latitude: city.latitude + stepNorth, longitude: city.longitude))
        let expected = -pointsPerRadian * (EarthZoom.mercator(city.latitude + stepNorth) - EarthZoom.mercator(city.latitude))
        let isMercator = abs(Double(north.y - c.y) - expected) < 0.02 * abs(expected) && abs(north.x - c.x) < 1
        return Level(image: snapshot.image, shaderImage: Image(uiImage: snapshot.image),
                     metersPerPoint: EarthZoom.earthRadius * cos(latitude) / pointsPerRadian,
                     cityOffset: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
                     side: size.width,
                     cityUV: CGPoint(x: c.x / size.width, y: c.y / size.height),
                     uvPerRadian: pointsPerRadian / Double(size.width),
                     isMercator: isMercator)
    }
}

/// The real Earth on the globe while the zoom pulls back: Web Mercator snapshots, mapped onto the
/// sphere by the `holoGlobe` shader. Made by `ZoomImagery`.
struct GlobeImagery {
    /// Where a point lands on the world snapshot: u = u0 + uPerRadian * longitude, v = v0 -
    /// vPerMercator * mercator(latitude), longitude in radians.
    struct Map {
        var u0: Double
        var uPerRadian: Double
        var v0: Double
        var vPerMercator: Double
    }

    struct Layer {
        let image: Image
        /// The city in the image (0...1), and the image's scale in uv per radian of longitude
        /// (Mercator's is the same north-south).
        let cityUV: CGPoint
        let uvPerRadian: Double
        /// Metres across the image, at the city (it fades out by this as the zoom pulls back).
        let span: Double
    }

    var world: Image?
    var worldMap: Map
    /// Up to three regional snapshots, finest first.
    var layers: [Layer]
    /// The city the regional snapshots are centred near: latitude (x) and longitude (y), radians.
    var cityRadians: CGPoint
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
/// to orbit keep one steady sense of speed, slowing while the real Earth dissolves into the
/// hologram so that moment reads:
///
/// 1. The flat snapshots (`ZoomStack`) pull back from the city.
/// 2. Before the Earth's curve could show (the sphere and the flat picture differ by under 3 points
///    at the corners), the globe takes over with the same snapshots on the sphere
///    (`sphereFrom`...`sphereTo`), and the real Earth pulls back into a ball.
/// 3. Once the whole Earth is in view, it dissolves in place into the hologram, coast on coast,
///    its aura growing (`dissolveFrom`...`dissolveTo`); it drifts to its place on the page and turns
///    to its resting view meanwhile (from `driftFrom`).
///
/// Without imagery (offline) the hologram simply fades in over whatever there is.
struct ZoomPath {
    /// Metres per point at the handover (measured on the map) and of the globe at rest.
    var startScale: Double
    var endScale: Double
    var sphereFrom: Double
    var sphereTo: Double
    var dissolveFrom: Double
    var dissolveTo: Double
    var driftFrom: Double
    /// The globe at rest, on screen.
    var rest: GlobeState
    /// The screen's middle, where the city is during the zoom, and the screen's diagonal.
    var screenCenter: CGPoint
    var diagonal: Double
    /// Metres across each of the globe's regional snapshots, finest first.
    var layerSpans: [Double]
    /// Whether there is a real Earth to show at all.
    var hasImagery: Bool
    /// How far through the zoom (in log scale) at each of 257 even steps of `u`.
    private var depths: [Double] = []

    /// The camera's focal length for the globe, in points: fixed, so it pulls back like a camera.
    var focal: CGFloat { rest.radius * CGFloat((rest.distance * rest.distance - 1).squareRoot()) }

    init(startScale: Double, levels: [ZoomImagery.Level], imagery: GlobeImagery?, rest: GlobeState, size: CGSize) {
        self.rest = rest
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let diagonal = Double(hypot(size.width, size.height))
        self.diagonal = diagonal
        let focal = Double(rest.radius) * (rest.distance * rest.distance - 1).squareRoot()
        self.startScale = startScale
        endScale = EarthZoom.earthRadius * (rest.distance - 1) / focal
        // The scale at which the globe's edge is `radius` points from its centre.
        func scale(forRadius radius: Double) -> Double {
            EarthZoom.earthRadius * ((1 + (focal / radius) * (focal / radius)).squareRoot() - 1) / focal
        }
        layerSpans = imagery?.layers.map(\.span) ?? []
        let hasWorld = imagery?.world != nil
        hasImagery = hasWorld || !layerSpans.isEmpty

        // 2. The globe takes over once the flat snapshot just finer than its finest has faded out
        // of the stack (`ZoomStack.layers`: at half cover), so both show the same picture.
        if let finest = layerSpans.first {
            let finer = levels.last { $0.span < finest * 0.9 }
            let handover = finer.map { $0.span * 0.8 / diagonal / 0.5 } ?? startScale * 1.5
            sphereFrom = max(handover * 1.05, startScale * 1.2)
        } else if let coarsest = levels.last {
            sphereFrom = max(coarsest.span * 0.8 / diagonal, startScale * 1.2)
        } else {
            sphereFrom = startScale * 4
        }
        sphereTo = sphereFrom * 1.3

        // 3. The dissolve: the whole Earth in view, about 290 points to 145 points in radius. Without
        // the world snapshot, before the widest regional one stops covering the screen instead.
        if hasWorld || !hasImagery {
            dissolveFrom = scale(forRadius: 290)
            dissolveTo = scale(forRadius: 145)
        } else {
            let covers = (layerSpans.last ?? 0) * 0.8 / diagonal
            dissolveTo = max(min(covers * 1.4, scale(forRadius: 150)), sphereTo * 2.2)
            dissolveFrom = dissolveTo / 2.2
        }
        dissolveFrom = max(dissolveFrom, sphereTo * 1.2)
        driftFrom = (dissolveFrom * dissolveTo).squareRoot()
        if !hasImagery {
            // Nothing to hand over to: whatever is on screen stays until the hologram fades in.
            sphereFrom = dissolveFrom
            sphereTo = dissolveTo
        }

        // The speed of the zoom: a smooth bell (smoothstep's), with a dip where the dissolve happens.
        // The dip is placed by bisection, so that the zoom, slowed by it, is at the dissolve's middle
        // right at the slowest point.
        let total = log(endScale) - log(startScale)
        let middle = (log(driftFrom) - log(startScale)) / total
        func profile(dip: Double) -> [Double] {
            let steps = 256
            var cumulative = [0.0]
            for step in 0..<steps {
                let u = (Double(step) + 0.5) / Double(steps)
                let g = (u - dip) / 0.13
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

    /// The flat snapshots are needed until the globe has taken over.
    func showsSnapshots(at u: Double) -> Bool { scale(at: u) < sphereTo }

    /// The globe at `u`: the real Earth facing the city at the screen's middle, taking over from
    /// the flat snapshots, then dissolving into the hologram while it drifts to its place and turns
    /// to face its resting point.
    func globe(at u: Double) -> GlobeState {
        let s = scale(at: u)
        let distance = 1 + s * Double(focal) / EarthZoom.earthRadius
        let radius = focal / CGFloat((distance * distance - 1).squareRoot())
        let k = between(s, driftFrom, endScale)
        let holo = between(s, dissolveFrom, dissolveTo)
        var state = rest
        state.distance = distance
        state.radius = radius
        state.center = CGPoint(x: screenCenter.x + (rest.center.x - screenCenter.x) * CGFloat(k),
                               y: screenCenter.y + (rest.center.y - screenCenter.y) * CGFloat(k))
        state.latitude = EarthZoom.city.latitude + (rest.latitude - EarthZoom.city.latitude) * k
        state.longitude = EarthZoom.city.longitude + (rest.longitude - EarthZoom.city.longitude) * k
        state.roll = roll(at: u)
        state.glow = rest.glow * holo
        state.satellite = hasImagery ? 1 - holo : 0
        state.opacity = hasImagery ? between(s, sphereFrom, sphereTo) : holo
        // Each regional snapshot fades out as it shrinks from covering the screen to covering half
        // of it, like the flat ones (`ZoomStack.layers`); the world is always under them.
        state.layerOpacity = layerSpans.map { span in
            let cover = span * 0.8 / (s * diagonal)
            return Self.ease((log(max(cover, 1e-6)) - log(0.5)) / log(2))
        }
        return state
    }
}
