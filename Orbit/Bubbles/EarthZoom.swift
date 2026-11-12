import SwiftUI
import MapKit

/// v3's opening, after Bump's Earth zoom: a real city in 3D (Apple's map) pulling back to a
/// glowing globe. MapKit streams its tiles as the camera moves, and a fast zoom through every
/// level outran them (the user's recording was grey for three seconds), so the zoom is drawn here
/// instead, from imagery fetched before it starts:
///
/// 1. The city: a live `MKMapView` (3D New York), shown only once MapKit has loaded every view the
///    rise passes through.
/// 2. First, satellite snapshots of the same spot at widening spans are fetched (`ZoomImagery`),
///    each about 3x wider than the last, up to a few thousand kilometres; the first ones in 3D
///    like the live map, so the handover is seamless. Only then does the live map load its views:
///    on an iPhone the two together starved the map, which showed its grey loading grid.
/// 3. The map flattens to looking straight down and rises a little (still MapKit), then hands
///    over to the snapshots, which zoom out smoothly (`ZoomStack`). The hologram fades in over
///    them as a flat map with the same projection, scale and turn (`GlobeState.flatness`), so
///    the photo turns into it coast on coast; pulling back further, it curls into the globe
///    (`HoloGlobeView`), which drifts to its place on the page.
///
/// Everything after the handover is a pure function of time (`ZoomPath`), so nothing can load late.
enum EarthZoom {
    /// The Empire State Building, seen from the south up Manhattan's avenues (the grid runs 29
    /// degrees east of north), Midtown's towers behind it. It was the Eiffel Tower (48.8584,
    /// 2.2945, heading 330), but Apple's 3D city never loaded a block round it on the user's
    /// iPhone (the same block every time; fine in the Simulator), so they asked for New York.
    /// Other Flyover views (latitude, longitude): Lower Manhattan (40.7061, -74.0087), San
    /// Francisco's Golden Gate (37.8078, -122.4750), Tokyo Tower (35.6586, 139.7454). The real
    /// app would start where the user is.
    static let city = CLLocationCoordinate2D(latitude: 40.74844, longitude: -73.98566)
    static let heading: Double = 29
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
    /// A view along the rise, `t` from 0 (the start camera) to 1 (the handover camera).
    static func riseCamera(_ t: Double) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: city, fromDistance: startDistance + (handoffDistance - startDistance) * t,
                    pitch: startPitch * CGFloat(1 - t), heading: heading)
    }

    /// The views the rise passes through, from the tower (0) to straight down (1).
    static let riseSteps: [Double] = [0, 1.0 / 3, 2.0 / 3, 1]

    /// Seconds: the city flattening and rising, the zoom out to the globe, and the zoom back in.
    static let rise: Double = 1.3
    static let zoomOut: Double = 5.0
    static let zoomBack: Double = 3.6
    /// The map's heading turns the snapshots and the globe on screen at first; this unwinds to
    /// north up over the first three quarters of the zoom.
    /// The short way round (Paris's heading 330 gave 30; New York's 29 gives -29, not 331).
    static var startRoll: Double {
        let roll = (360 - heading).truncatingRemainder(dividingBy: 360)
        return roll > 180 ? roll - 360 : roll
    }

    /// Each snapshot covers this many times the span of the one before, up to `largestSpan`.
    static let spanStep: Double = 3.2
    static let largestSpan: Double = 6_000_000
    /// Snapshots narrower than this are drawn in 3D like the live map (the same photogrammetry and
    /// grading), so the handover from the map doesn't jump; wider ones are flat satellite imagery.
    static let realisticSpan: Double = 20_000

    /// Apple's 3D city, for the live map and the nearest snapshots.
    static var imagery: MKImageryMapConfiguration { MKImageryMapConfiguration(elevationStyle: .realistic) }

    /// How much of a picture of the map is MapKit's grey loading grid (or nothing): flat,
    /// colourless patches, which a photo of a city doesn't have. Measured on a small copy in
    /// blocks about 16pt wide; above 12% counts as holes. On the user's Simulator recordings the
    /// city never went above 5%; their iPhone's grey block covered 16-47% even in photos of the
    /// screen. nil if it can't be read.
    static func holeFraction(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let w = 96, h = max(8, Int(Double(cg.height) / Double(cg.width) * 96))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let block = 4
        var flat = 0, total = 0
        for by in stride(from: 0, through: h - block, by: block) {
            for bx in stride(from: 0, through: w - block, by: block) {
                var low = [255, 255, 255], high = [0, 0, 0], tint = 0
                for y in by..<(by + block) {
                    for x in bx..<(bx + block) {
                        let i = (y * w + x) * 4
                        let rgb = [Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])]
                        for c in 0..<3 {
                            low[c] = min(low[c], rgb[c])
                            high[c] = max(high[c], rgb[c])
                        }
                        tint = max(tint, rgb.max()! - rgb.min()!)
                    }
                }
                total += 1
                if (0..<3).allSatisfy({ high[$0] - low[$0] <= 10 }) && tint <= 24 { flat += 1 }
            }
        }
        return total > 0 ? Double(flat) / Double(total) : nil
    }

    /// A snapshot that didn't come, or came with holes in it.
    static func hasHoles(_ snapshot: MKMapSnapshotter.Snapshot?) -> Bool {
        guard let snapshot else { return true }
        return (holeFraction(snapshot.image) ?? 0) > 0.12
    }
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

/// Owns the live map, says when the view it was last given has loaded, measures its scale, and
/// moves its camera with UIKit animations (the rise and the tilt back up).
///
/// Loaded means MapKit downloaded what the view needs ("finished loading"), finished drawing it,
/// and has gone quiet; not that it reported a full render: in 3D (realistic elevation) it hardly
/// ever does, so a wait on that ran into every time limit. Those callbacks alone still let an
/// iPhone show the grey loading grid, so the views are first downloaded with `prefetch`.
final class CityMapController: NSObject, MKMapViewDelegate {
    let mapView = MKMapView(frame: .zero)
    /// Since the last move: MapKit is downloading, has downloaded, is drawing, has drawn (fully),
    /// or failed.
    private var loading = false
    private var startedLoading = false
    private var startedRendering = false
    private var rendering = false
    private var fullyRendered = false
    private var failed = false
    private var jumpedAt = Date.timeIntervalSinceReferenceDate
    /// When MapKit last said anything, to wait for it to go quiet.
    private var lastActivity = Date.timeIntervalSinceReferenceDate
    /// Metres per screen point at the handover camera, measured as soon as the map has a size
    /// (across the middle, pitch doesn't change the horizontal scale).
    private(set) var handoffEstimate: Double?

    override init() {
        super.init()
        mapView.delegate = self
        mapView.preferredConfiguration = EarthZoom.imagery
        mapView.isUserInteractionEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.camera = EarthZoom.handoffCamera
    }

    /// Forget what MapKit said about the last view: a new one is coming.
    private func resetLoadState() {
        loading = false
        startedLoading = false
        startedRendering = false
        rendering = false
        fullyRendered = false
        failed = false
        jumpedAt = Date.timeIntervalSinceReferenceDate
        lastActivity = jumpedAt
    }

    /// Shows `camera` at once.
    func jump(to camera: MKMapCamera) {
        resetLoadState()
        mapView.camera = camera
    }

    /// Moves to `camera` with the rise's own animation (the rise, the tilt back up).
    func animate(to camera: MKMapCamera) {
        resetLoadState()
        UIView.animate(withDuration: EarthZoom.rise, delay: 0, options: [.curveEaseInOut]) {
            self.mapView.camera = camera
        }
    }

    /// The view last moved to has loaded: MapKit finished downloading for it, finished drawing it
    /// (or stopped saying anything for a second) and has been quiet a moment; or it never needed
    /// anything.
    var isReady: Bool {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - jumpedAt > 0.4, !loading, !failed else { return false }
        let quiet = now - lastActivity
        if rendering && quiet < 1.0 { return false }
        if fullyRendered { return quiet > 0.2 }
        if startedLoading || startedRendering { return quiet > 0.6 }
        return now - jumpedAt > 1.5
    }

    /// Jumps to `camera` and waits until it has loaded, for at most `limit` seconds, asking again
    /// (at most every 2 s) if a download failed. True if it loaded.
    @MainActor
    func load(_ camera: MKMapCamera, within limit: Double) async -> Bool {
        jump(to: camera)
        return await waitUntilLoaded(camera, deadline: Date.timeIntervalSinceReferenceDate + limit)
    }

    /// Moves to `camera` with the rise's animation and waits, as `load` does, for the view it lands on.
    @MainActor
    func move(to camera: MKMapCamera, within limit: Double) async -> Bool {
        animate(to: camera)
        try? await Task.sleep(for: .seconds(EarthZoom.rise))
        if Task.isCancelled { return false }
        return await waitUntilLoaded(camera, deadline: Date.timeIntervalSinceReferenceDate + limit)
    }

    @MainActor
    private func waitUntilLoaded(_ camera: MKMapCamera, deadline: Double) async -> Bool {
        var tries = 0
        while Date.timeIntervalSinceReferenceDate < deadline {
            if isReady { return true }
            if failed, Date.timeIntervalSinceReferenceDate - jumpedAt > 2 {
                // A hair further away, so MapKit treats it as a new view and asks again.
                tries += 1
                jump(to: MKMapCamera(lookingAtCenter: camera.centerCoordinate,
                                     fromDistance: camera.centerCoordinateDistance * (1 + 0.0004 * Double(tries)),
                                     pitch: camera.pitch, heading: camera.heading))
            }
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return false }
        }
        return isReady
    }

    /// Downloads everything `camera` needs before the live map is shown it: a snapshot of exactly
    /// that view (the map's size, scale and 3D style), which MapKit finishes only once every tile
    /// is in, and keeps them for the map. The map's own callbacks said "loaded" while an iPhone
    /// still showed the grey loading grid; a snapshot can't finish with a tile missing. A failed
    /// one is asked again; at most `limit` seconds. The snapshot, if it finished.
    @MainActor @discardableResult
    func prefetch(_ camera: MKMapCamera, within limit: Double) async -> MKMapSnapshotter.Snapshot? {
        let size = mapView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = mapView.traitCollection.displayScale > 0 ? mapView.traitCollection.displayScale : 3
        let deadline = Date.timeIntervalSinceReferenceDate + limit
        while Date.timeIntervalSinceReferenceDate < deadline {
            let fetch = MapPrefetch(camera: camera, size: size, scale: scale)
            while !fetch.finished, Date.timeIntervalSinceReferenceDate < deadline {
                try? await Task.sleep(for: .milliseconds(60))
                if Task.isCancelled { fetch.cancel(); return nil }
            }
            if let snapshot = fetch.snapshot { return snapshot }
            fetch.cancel()
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return nil }
        }
        return nil
    }

    /// Where the city is on the live map, in its points.
    func cityPoint() -> CGPoint? {
        guard mapView.bounds.width > 0 else { return nil }
        let point = mapView.convert(EarthZoom.city, toPointTo: mapView)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
        loading = true
        startedLoading = true
        lastActivity = Date.timeIntervalSinceReferenceDate
    }

    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        loading = false
        lastActivity = Date.timeIntervalSinceReferenceDate
    }

    func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        loading = false
        failed = true
        lastActivity = Date.timeIntervalSinceReferenceDate
    }

    func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
        startedRendering = true
        rendering = true
        fullyRendered = false
        lastActivity = Date.timeIntervalSinceReferenceDate
        estimateIfNeeded()
    }

    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        rendering = false
        self.fullyRendered = fullyRendered
        lastActivity = Date.timeIntervalSinceReferenceDate
        estimateIfNeeded()
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
    func rise() { animate(to: EarthZoom.handoffCamera) }

    /// Back down to the start camera, tilting up to the tower.
    func settle() { animate(to: EarthZoom.startCamera) }
}

/// One snapshot of a view of the live map, taken only to download its tiles (see `prefetch`).
private final class MapPrefetch {
    private(set) var finished = false
    private(set) var snapshot: MKMapSnapshotter.Snapshot?
    private let snapshotter: MKMapSnapshotter

    init(camera: MKMapCamera, size: CGSize, scale: CGFloat) {
        let options = MKMapSnapshotter.Options()
        options.camera = camera
        options.size = size
        options.preferredConfiguration = EarthZoom.imagery
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: scale)
        snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: .main) { [weak self] snapshot, _ in
            self?.snapshot = snapshot
            self?.finished = true
        }
    }

    func cancel() {
        snapshotter.cancel()
        finished = true
    }
}

struct CityMapView: UIViewRepresentable {
    let controller: CityMapController

    func makeUIView(context: Context) -> MKMapView { controller.mapView }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
}

// MARK: - The zoom's imagery

/// Satellite snapshots of the city at widening spans, fetched behind the loading cover before the
/// live map loads its views.
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
            request(span: span, side: index == 0 ? 1_100 : 800, scale: index == 0 ? 3 : 2,
                    realistic: span < EarthZoom.realisticSpan)
        }
    }

    /// One snapshot; a 3D one that fails is asked for again flat, and a flat one once more, so
    /// a slow network costs a little time rather than a hole in the zoom.
    private func request(span: Double, side: CGFloat, scale: CGFloat, realistic: Bool, retried: Bool = false) {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: EarthZoom.city, latitudinalMeters: span, longitudinalMeters: span)
        options.size = CGSize(width: side, height: side)
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: realistic ? .realistic : .flat)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(displayScale: scale)
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotters.append(snapshotter)
        snapshotter.start(with: .main) { [weak self] snapshot, _ in
            guard let self else { return }
            guard let snapshot, let level = Self.measure(snapshot, span: span) else {
                if realistic || !retried {
                    self.request(span: span, side: side, scale: scale, realistic: false, retried: !realistic)
                } else {
                    self.pending -= 1
                }
                return
            }
            self.pending -= 1
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
