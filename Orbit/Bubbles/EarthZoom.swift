import SwiftUI
import MapKit

/// v3's opening, after Bump's Earth zoom: Apple's own satellite map (MapKit), pulled back from a
/// city at rooftop height to the whole Earth hanging in space. It is real map data, so no video:
/// Flyover cities are photoreal 3D up close, and far enough out MapKit draws the globe.
enum EarthZoom {
    /// Where it starts: the Eiffel Tower, seen across the Champ de Mars from a few rooftops up.
    /// Other Flyover cities that look good up close (latitude, longitude): New York's Lower
    /// Manhattan (40.7061, -74.0087), San Francisco's Golden Gate (37.8078, -122.4750), Tokyo
    /// Tower (35.6586, 139.7454). The real app would start where the user is.
    static let city = CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)
    static let street = MapCamera(centerCoordinate: city, distance: 1_500, heading: 330, pitch: 62)

    /// Where it ends: the whole Earth, Europe and Africa facing us, north up.
    static let globeCenter = CLLocationCoordinate2D(latitude: 28, longitude: 8)
    static let globeDistance: Double = 30_000_000

    static func space(heading: Double = 0) -> MapCamera {
        MapCamera(centerCoordinate: globeCenter, distance: globeDistance, heading: heading, pitch: 0)
    }

    /// Lets the camera go far enough out to see the whole globe.
    static let bounds = MapCameraBounds(minimumDistance: 200, maximumDistance: 60_000_000)

    /// Seconds from the city to space (and back).
    static let duration: Double = 4.2

    /// The globe is cut a hair inside its edge, where the atmosphere and the dark limb are, so
    /// what shrinks into the orb is a clean disc of Earth.
    static let limbCut: CGFloat = 0.985

    enum Direction { case out, back }

    /// Where the globe sits in the map view, in its points.
    struct Globe: Equatable {
        var center: CGPoint
        var radius: CGFloat
    }

    /// The keyframes for one zoom, out to space or back to the city, from wherever the camera is.
    struct Plan {
        /// Twelve evenly timed steps, even in log space and eased at both ends, so the zoom keeps
        /// one steady sense of speed from rooftops to orbit.
        var distances: [Double]
        var pitch: [(value: Double, duration: Double, curve: UnitCurve)]
        var heading: Double
        var centers: [(value: CLLocationCoordinate2D, duration: Double, curve: UnitCurve)]
        var step: Double { EarthZoom.duration / Double(distances.count) }
    }

    static func plan(_ direction: Direction, from camera: MapCamera) -> Plan {
        let d = duration
        let start = camera.distance
        let end = direction == .out ? globeDistance : street.distance
        let distances = (1...12).map { i -> Double in
            let u = Double(i) / 12
            let eased = u * u * (3 - 2 * u)
            return start * pow(end / start, eased)
        }
        switch direction {
        case .out:
            // Tilt up to looking straight down while still low, turn north up, and drift the
            // centre from the city to the middle of the globe once it is a long way off.
            return Plan(
                distances: distances,
                pitch: [(0, 0.62 * d, .easeInOut), (0, 0.38 * d, .linear)],
                heading: nearest(360, to: camera.heading),
                centers: [(city, 0.25 * d, .linear), (globeCenter, 0.7 * d, .easeInOut), (globeCenter, 0.05 * d, .linear)]
            )
        case .back:
            return Plan(
                distances: distances,
                pitch: [(0, 0.38 * d, .linear), (street.pitch, 0.62 * d, .easeInOut)],
                heading: nearest(street.heading, to: camera.heading),
                centers: [(globeCenter, 0.05 * d, .linear), (city, 0.7 * d, .easeInOut), (city, 0.25 * d, .linear)]
            )
        }
    }

    /// `heading` plus or minus whole turns, whichever is closest to `current`, so the map never
    /// spins the long way round.
    private static func nearest(_ heading: Double, to current: Double) -> Double {
        heading + 360 * ((current - heading) / 360).rounded()
    }

    /// Finds the globe in the map view: where its centre is, and its edge, worked out from where
    /// two points 25 and 55 degrees east of the centre land on screen (a perspective camera makes
    /// both depend on its focal length and distance, so two points pin both down).
    static func measure(_ proxy: MapProxy, size: CGSize) -> Globe {
        let guess = Globe(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: min(size.width, size.height) * 0.36)
        guard let c = proxy.convert(globeCenter, to: .local) else { return guess }
        let b1 = 25.0 * .pi / 180, b2 = 55.0 * .pi / 180
        guard let p1 = proxy.convert(destination(from: globeCenter, east: b1), to: .local),
              let p2 = proxy.convert(destination(from: globeCenter, east: b2), to: .local)
        else { return Globe(center: c, radius: guess.radius) }
        let r1 = Double(hypot(p1.x - c.x, p1.y - c.y)), r2 = Double(hypot(p2.x - c.x, p2.y - c.y))
        let s1 = sin(b1), c1 = cos(b1), s2 = sin(b2), c2 = cos(b2)
        // r = f sin(b) / (k - cos(b)), with k the camera's distance from Earth's centre in Earth
        // radii; the edge of the globe is then at f / sqrt(k^2 - 1).
        var edge = r2 / s2   // what an orthographic view would give
        let denominator = r1 * s2 - r2 * s1
        if abs(denominator) > 1e-6 * max(r1, 1) {
            let k = (r1 * s2 * c1 - r2 * s1 * c2) / denominator
            if k > 1.01 {
                let f = r1 * (k - c1) / s1
                edge = f / (k * k - 1).squareRoot()
            }
        }
        let radius = CGFloat(edge)
        guard radius.isFinite, radius > 20, radius < max(size.width, size.height) else { return Globe(center: c, radius: guess.radius) }
        return Globe(center: c, radius: radius)
    }

    /// The point `angle` radians of arc east of `start` along a great circle.
    private static func destination(from start: CLLocationCoordinate2D, east angle: Double) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * .pi / 180, lon1 = start.longitude * .pi / 180
        let bearing = Double.pi / 2
        let lat2 = asin(sin(lat1) * cos(angle) + cos(lat1) * sin(angle) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angle) * cos(lat1), cos(angle) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

/// The map: satellite imagery with real elevation (3D cities, terrain, the globe), no controls,
/// not touchable. Zooms when `zoomTrigger` changes, in `direction`; reports where the globe is
/// when `measureTrigger` changes.
struct EarthMapView: View {
    @Binding var camera: MapCameraPosition
    var zoomTrigger: Int
    var direction: EarthZoom.Direction
    var measureTrigger: Int
    var size: CGSize
    var onMeasure: (EarthZoom.Globe) -> Void

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, bounds: EarthZoom.bounds, interactionModes: [])
                .mapStyle(.imagery(elevation: .realistic))
                .mapControlVisibility(.hidden)
                .mapCameraKeyframeAnimator(trigger: zoomTrigger) { initial in
                    let plan = EarthZoom.plan(direction, from: initial)
                    KeyframeTrack(\MapCamera.distance) {
                        CubicKeyframe(plan.distances[0], duration: plan.step)
                        CubicKeyframe(plan.distances[1], duration: plan.step)
                        CubicKeyframe(plan.distances[2], duration: plan.step)
                        CubicKeyframe(plan.distances[3], duration: plan.step)
                        CubicKeyframe(plan.distances[4], duration: plan.step)
                        CubicKeyframe(plan.distances[5], duration: plan.step)
                        CubicKeyframe(plan.distances[6], duration: plan.step)
                        CubicKeyframe(plan.distances[7], duration: plan.step)
                        CubicKeyframe(plan.distances[8], duration: plan.step)
                        CubicKeyframe(plan.distances[9], duration: plan.step)
                        CubicKeyframe(plan.distances[10], duration: plan.step)
                        CubicKeyframe(plan.distances[11], duration: plan.step, endVelocity: 0)
                    }
                    KeyframeTrack(\MapCamera.pitch) {
                        LinearKeyframe(plan.pitch[0].value, duration: plan.pitch[0].duration, timingCurve: plan.pitch[0].curve)
                        LinearKeyframe(plan.pitch[1].value, duration: plan.pitch[1].duration, timingCurve: plan.pitch[1].curve)
                    }
                    KeyframeTrack(\MapCamera.heading) {
                        LinearKeyframe(plan.heading, duration: EarthZoom.duration, timingCurve: .easeInOut)
                    }
                    KeyframeTrack(\MapCamera.centerCoordinate) {
                        LinearKeyframe(plan.centers[0].value, duration: plan.centers[0].duration, timingCurve: plan.centers[0].curve)
                        LinearKeyframe(plan.centers[1].value, duration: plan.centers[1].duration, timingCurve: plan.centers[1].curve)
                        LinearKeyframe(plan.centers[2].value, duration: plan.centers[2].duration, timingCurve: plan.centers[2].curve)
                    }
                }
                .onChange(of: measureTrigger) { _, _ in
                    onMeasure(EarthZoom.measure(proxy, size: size))
                }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The glass Earth sits in: real Liquid Glass on iOS 26 and later (it bends the globe at its
/// rim and lights it), and a soft highlight with a bright rim before that.
struct EarthGlass: View {
    let diameter: CGFloat

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: diameter, height: diameter)
                    .glassEffect(.clear, in: Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                                             center: UnitPoint(x: 0.32, y: 0.24),
                                             startRadius: 0, endRadius: diameter * 0.42))
                    Circle()
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.08), .white.opacity(0.4)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1.2)
                }
                .frame(width: diameter, height: diameter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
