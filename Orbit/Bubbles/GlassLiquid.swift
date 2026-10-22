import SwiftUI
import UIKit

/// v2's look: no background liquid. The glass orbs are the liquid themselves.
///
/// Every photo is drawn flat where its orb is, with the screen's headline (`backdrop`) over them,
/// and the `glassLiquid` shader (`Liquid.metal`) turns the whole layer into glass: orbs that come
/// close melt into one shape, each photo bulges like a marble, text bends as glass passes over it,
/// and the light sits on top.
struct GlassLiquidLayer: View {
    var bubbles: [RenderedBubble]
    /// Each bubble's velocity in screen points per second, by id.
    var velocities: [CGVector] = []
    var metrics: StageMetrics
    var size: CGSize
    var backdrop: AnyView?

    /// How close two orbs must come before they melt together, in reference points: they join
    /// when the gap between them is under about 0.7 x this.
    static let blend: CGFloat = 12
    /// Fisheye strength: how much the middle of each orb is magnified.
    static let lens: Float = 0.5
    /// The soft glow around the glass, in its own colours: its width in reference points, and its
    /// strength at the edge.
    static let glowWidth: CGFloat = 5
    static let glowStrength: Float = 0.4

    /// How a moving orb stretches along its motion, like a drop: by up to `maxStretch` (keeping its
    /// area), half of that at `halfStretchSpeed` points per second. Still orbs stay round.
    static let maxStretch: CGFloat = 0.42
    static let halfStretchSpeed: CGFloat = 800

    /// The stretch along the motion as a vector: its direction, and the stretch minus one as its length.
    func stretch(for id: Int) -> CGVector {
        guard velocities.indices.contains(id) else { return .zero }
        let v = velocities[id]
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard speed > 1 else { return .zero }
        let amount = Self.maxStretch * speed / (speed + Self.halfStretchSpeed)
        return CGVector(dx: v.dx / speed * amount, dy: v.dy / speed * amount)
    }

    var body: some View {
        // Smaller on top: a bud starts as a droplet on its parent's surface and swells out of it,
        // with the glass joining them, instead of sliding out from behind. Bubbles melting away go
        // underneath everything, so they disappear into whoever absorbs them. (v1 is the other way round.)
        let visible = bubbles.filter { $0.radius > 0.5 }.sorted { a, b in
            a.isLeaving != b.isLeaving ? a.isLeaving : a.depth > b.depth
        }
        let largest = visible.map { $0.radius * metrics.scale }.max() ?? 0
        ZStack {
            Color.clear
            ForEach(visible.filter { OrbitChoreography.hasPhoto($0.id) }) { bubble in
                let diameter = bubble.radius * 2 * metrics.scale
                let pull = self.stretch(for: bubble.id)
                let amount = (pull.dx * pull.dx + pull.dy * pull.dy).squareRoot()
                let radians = Double(atan2(pull.dy, pull.dx))
                Image(uiImage: GlassPhoto.image(for: bubble.id))
                    .resizable()
                    .frame(width: diameter, height: diameter)
                    // Stretched with the glass: longer along the motion, narrower across it.
                    .rotationEffect(Angle(radians: -radians))
                    .scaleEffect(x: 1 + amount, y: 1 / (1 + amount).squareRoot())
                    .rotationEffect(Angle(radians: radians))
                    .position(metrics.point(bubble.center))
                    .zIndex(bubble.isLeaving ? -10_000 - bubble.depth : -bubble.depth)
            }
            // The headline sits in the layer too, over the photos, so glass passing over it bends it.
            if let backdrop {
                backdrop.zIndex(1)
            }
        }
        .frame(width: size.width, height: size.height)
        // Flatten everything into one image first. Without this the shader saw each photo on its own,
        // and where one photo's square overlapped another, the one underneath went missing.
        .drawingGroup()
        .layerEffect(
            ShaderLibrary.glassLiquid(
                .float(Float(Self.blend * metrics.scale)),
                .float(Self.lens),
                .float(Float(Self.glowWidth * metrics.scale)),
                .float(Self.glowStrength),
                .float3(Theme.glassCanvasRGB.r, Theme.glassCanvasRGB.g, Theme.glassCanvasRGB.b),
                .floatArray(orbs(visible))
            ),
            // The lens looks inward by at most about a quarter of an orb's (stretched) radius.
            maxSampleOffset: CGSize(width: largest * 0.42 + 4, height: largest * 0.42 + 4)
        )
    }

    /// Eight floats per orb, as `glassLiquid` reads them: x, y, r, the glow colour, then the stretch.
    private func orbs(_ visible: [RenderedBubble]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(visible.count * 8)
        for bubble in visible {
            let c = metrics.point(bubble.center)
            let glow = GlassPhoto.glow(for: bubble.id)
            let pull = self.stretch(for: bubble.id)
            out += [Float(c.x), Float(c.y), Float(bubble.radius * metrics.scale), glow.r, glow.g, glow.b,
                    Float(pull.dx), Float(pull.dy)]
        }
        return out
    }
}

/// v2's swipe: how far the finger has lifted Earth, and how it settles back once let go. The
/// stage adds this to Earth's position every frame, on top of whatever the engine is doing, so
/// letting go never jumps: the lift springs back to zero while Earth flies to its next place.
final class EarthLift {
    /// Points, negative is up.
    private var drag: CGFloat = 0
    private var dragging = false
    private var grabbedFrom: CGFloat = 0
    private var releasedFrom: CGFloat = 0
    private var releasedAt: Double?

    func offset(at time: Double) -> CGFloat {
        if dragging { return drag }
        guard let start = releasedAt else { return 0 }
        return releasedFrom * CGFloat(1 - SpringCurve.liftSettle.progress(at: time - start))
    }

    /// The finger moved: `translation` is the drag's vertical translation, negative up. Upward it
    /// follows with growing resistance, toward a ceiling; downward it barely gives.
    func move(to translation: CGFloat, at time: Double) {
        if !dragging {
            grabbedFrom = offset(at: time)
            dragging = true
        }
        let up = max(-translation, 0), down = max(translation, 0)
        let ceiling: CGFloat = 280
        drag = grabbedFrom - ceiling * (1 - exp(-up / ceiling)) + 30 * (1 - exp(-down / 120))
    }

    /// The finger let go: springs back to zero from wherever it was.
    func release(at time: Double) {
        releasedFrom = offset(at: time)
        releasedAt = time
        dragging = false
    }
}

/// The flat photos the glass shader looks through, rendered once each, and each one's glow colour.
enum GlassPhoto {
    /// The photo fades out between `feather` and `fill` (fractions of the orb's radius); beyond is
    /// clear glass. The fade keeps the photo's edge soft where the glass melts into a neck.
    static let fill: CGFloat = 0.95
    static let feather: CGFloat = 0.86

    struct Glow { let r, g, b: Float }

    static func image(for id: Int) -> UIImage {
        id == OrbitChoreography.earth ? earth.image : people[(id - 1) % people.count].image
    }

    /// Droplets (no photo) barely glow: a touch of cool white, so they read as clear beads.
    static func glow(for id: Int) -> Glow {
        if id == OrbitChoreography.earth { return earth.glow }
        guard OrbitChoreography.hasPhoto(id) else { return Glow(r: 0.97, g: 0.97, b: 1.0) }
        return people[(id - 1) % people.count].glow
    }

    private struct Rendered {
        let image: UIImage
        let glow: Glow
    }

    private static let people: [Rendered] = Person.samples.map { person in
        render(person.photo, isEarth: false)
    }

    private static let earth = render(UIImage(named: "earth"), isEarth: true)

    private static func render(_ source: UIImage?, isEarth: Bool) -> Rendered {
        let side: CGFloat = 240
        let size = CGSize(width: side, height: side)
        let rect = CGRect(origin: .zero, size: size)
        let disc = rect.insetBy(dx: side * (1 - fill) / 2, dy: side * (1 - fill) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.saveGState()
            UIBezierPath(ovalIn: disc).addClip()
            if let source {
                if isEarth {
                    // The globe fills the disc; its dark limb trimmed a touch.
                    let globe = disc.insetBy(dx: -disc.width * 0.012, dy: -disc.width * 0.012)
                    source.draw(in: globe)
                } else {
                    source.draw(in: aspectFill(source.size, in: disc))
                }
            } else {
                UIColor(white: 0.9, alpha: 1).setFill()
                UIRectFill(disc)
            }
            cg.restoreGState()
            // Soft edge: solid to `feather`, gone at `fill`.
            let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [feather, fill]) {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                cg.saveGState()
                cg.setBlendMode(.destinationIn)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                      endRadius: side / 2, options: [.drawsAfterEndLocation])
                cg.restoreGState()
            }
        }
        return Rendered(image: image, glow: glowColour(of: image))
    }

    /// The orb's colour for its glow: the most colourful tones just inside its rim, made clearly
    /// tinted and pale. A grey glow on white reads as a drop shadow, so it is never grey or dark.
    private static func glowColour(of image: UIImage) -> Glow {
        let n = 32
        let fallback = Glow(r: 0.86, g: 0.84, b: 0.98)
        guard let cgImage = image.cgImage else { return fallback }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                          bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return fallback }
        // The ring's colours, each weighted by how colourful it is.
        var sum = (r: 0.0, g: 0.0, b: 0.0), weight = 0.0
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Double(x) + 0.5) / Double(n) * 2 - 1, dy = (Double(y) + 0.5) / Double(n) * 2 - 1
                let rho = (dx * dx + dy * dy).squareRoot()
                guard rho > 0.6, rho < 0.93 else { continue }
                let i = (y * n + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                let chroma = max(r, g, b) - min(r, g, b)
                let w = chroma * chroma + 1e-4
                sum.r += r * w; sum.g += g * w; sum.b += b * w; weight += w
            }
        }
        guard weight > 0 else { return fallback }
        let hsb = rgbToHSB(sum.r / weight, sum.g / weight, sum.b / weight)
        // A clear, pale tint of that hue: saturation 0.38, brightness full.
        guard hsb.s > 0.06 else { return fallback }
        let rgb = hsbToRGB(hsb.h, 0.38, 1.0)
        return Glow(r: Float(rgb.r), g: Float(rgb.g), b: Float(rgb.b))
    }

    private static func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h = (h / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    private static func hsbToRGB(_ h: Double, _ s: Double, _ v: Double) -> (r: Double, g: Double, b: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    private static func aspectFill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
