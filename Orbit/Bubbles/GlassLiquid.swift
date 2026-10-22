import SwiftUI
import UIKit

/// v2's look: no background liquid. The glass orbs are the liquid themselves.
///
/// Every photo is drawn flat where its orb is, a little larger than the orb with a feathered rim,
/// and the `glassLiquid` shader (`Liquid.metal`) turns the whole layer into glass: orbs that come
/// close melt into one shape, each photo bulges like a marble, and the light sits on top.
struct GlassLiquidLayer: View {
    var bubbles: [RenderedBubble]
    var metrics: StageMetrics
    var size: CGSize

    /// How close two orbs must come before they melt together, in reference points: they join
    /// when the gap between them is under about 0.7 x this.
    static let blend: CGFloat = 12
    /// Fisheye strength: how much the middle of each photo is magnified.
    static let lens: Float = 0.42
    /// The soft glow around the glass, in its own colours: its width in reference points, and its
    /// strength at the edge.
    static let glowWidth: CGFloat = 5
    static let glowStrength: Float = 0.55

    var body: some View {
        // Smaller on top: a bud starts as a droplet on its parent's surface and swells out of it,
        // with the glass joining them, instead of sliding out from behind. (v1 is the other way round.)
        // Bubbles melting away go underneath everything, so they disappear into whoever absorbs them.
        let visible = bubbles.filter { $0.radius > 0.5 }.sorted { a, b in
            a.isLeaving != b.isLeaving ? a.isLeaving : a.depth > b.depth
        }
        let largest = visible.map { $0.radius * metrics.scale }.max() ?? 0
        ZStack {
            Color.clear
            ForEach(visible) { bubble in
                let diameter = bubble.radius * 2 * metrics.scale * GlassPhoto.reach
                Image(uiImage: GlassPhoto.image(for: bubble.id))
                    .resizable()
                    .frame(width: diameter, height: diameter)
                    .position(metrics.point(bubble.center))
                    .zIndex(bubble.isLeaving ? -10_000 - bubble.depth : -bubble.depth)
            }
        }
        .frame(width: size.width, height: size.height)
        .layerEffect(
            ShaderLibrary.glassLiquid(
                .float(Float(Self.blend * metrics.scale)),
                .float(Self.lens),
                .float(Float(Self.glowWidth * metrics.scale)),
                .float(Self.glowStrength),
                .floatArray(orbs(visible))
            ),
            // The lens looks inward by at most about a quarter of an orb's radius.
            maxSampleOffset: CGSize(width: largest * 0.25 + 4, height: largest * 0.25 + 4),
            isEnabled: !visible.isEmpty
        )
    }

    /// Six floats per orb, as `glassLiquid` reads them: x, y, r, then the glow colour.
    private func orbs(_ visible: [RenderedBubble]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(visible.count * 6)
        for bubble in visible {
            let c = metrics.point(bubble.center)
            let glow = GlassPhoto.glow(for: bubble.id)
            out += [Float(c.x), Float(c.y), Float(bubble.radius * metrics.scale), glow.r, glow.g, glow.b]
        }
        return out
    }
}

/// The flat photos the glass shader looks through, rendered once each, and each one's glow colour.
enum GlassPhoto {
    /// Each photo is drawn this much wider than its orb, solid to the orb's edge and feathering out
    /// beyond it, so where two orbs melt together the neck between them has both photos to show.
    static let reach: CGFloat = 1.15

    struct Glow { let r, g, b: Float }

    static func image(for id: Int) -> UIImage {
        id == OrbitChoreography.earth ? earth.image : people[(id - 1) % people.count].image
    }

    static func glow(for id: Int) -> Glow {
        id == OrbitChoreography.earth ? earth.glow : people[(id - 1) % people.count].glow
    }

    private struct Rendered {
        let image: UIImage
        let glow: Glow
    }

    private static let people: [Rendered] = Person.samples.map { person in
        render(person.photo, fill: UIColor(white: 0.93, alpha: 1), isEarth: false)
    }

    /// Earth's photo has black space around the globe, which would show in the necks as a dark
    /// band, so outside the globe it is filled with a pale sky blue instead.
    private static let earth = render(UIImage(named: "earth"),
                                      fill: UIColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1), isEarth: true)

    private static func render(_ source: UIImage?, fill: UIColor, isEarth: Bool) -> Rendered {
        let side: CGFloat = 240 * reach
        let size = CGSize(width: side, height: side)
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            fill.setFill()
            UIRectFill(rect)
            if let source {
                if isEarth {
                    // The globe fills the orb exactly; trim its dark limb a touch.
                    let globe = rect.insetBy(dx: side * (1 - 1 / reach) / 2, dy: side * (1 - 1 / reach) / 2)
                    cg.saveGState()
                    UIBezierPath(ovalIn: globe.insetBy(dx: globe.width * 0.012, dy: globe.width * 0.012)).addClip()
                    source.draw(in: globe)
                    cg.restoreGState()
                } else {
                    source.draw(in: aspectFill(source.size, in: rect))
                }
            }
            // Solid to the orb's edge, feathering out to nothing at the end of the reach.
            let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [1 / reach, 1]) {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                cg.setBlendMode(.destinationIn)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                      endRadius: side / 2, options: [.drawsAfterEndLocation])
            }
            cg.endTransparencyLayer()
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
                let rho = (dx * dx + dy * dy).squareRoot() * Double(reach)
                guard rho > 0.6, rho < 0.98 else { continue }
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
