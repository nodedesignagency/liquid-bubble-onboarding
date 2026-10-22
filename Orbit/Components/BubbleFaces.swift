import SwiftUI
import UIKit
import CoreImage

/// A friend's photo, already softened (see `SoftPhoto`). Falls back to initials if the photo is missing.
/// The view is `SoftPhoto.reach` times wider than `diameter`: the photo's blur spills past its circle.
struct AvatarFace: View {
    let person: Person
    let diameter: CGFloat

    var body: some View {
        if let photo = person.softPhoto {
            Image(uiImage: photo)
                .resizable()
                .frame(width: diameter * SoftPhoto.reach, height: diameter * SoftPhoto.reach)
        } else {
            Text(person.initials)
                .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Theme.inkSecondary, in: Circle())
                .frame(width: diameter * SoftPhoto.reach, height: diameter * SoftPhoto.reach)
        }
    }
}

/// The globe everyone buds out of.
struct EarthFace: View {
    static let photo = UIImage(named: "earth").map { SoftPhoto.render($0, diameter: 260, wash: UIColor(Theme.liquid)) }

    let diameter: CGFloat

    var body: some View {
        if let photo = Self.photo {
            Image(uiImage: photo)
                .resizable()
                .frame(width: diameter * SoftPhoto.reach, height: diameter * SoftPhoto.reach)
        }
    }
}

/// No border and no shadow, and the reference's blur: the middle of the photo stays sharp and
/// dissolves into a heavily blurred copy that spills a little past the circle, lightened and
/// washed with the liquid's colour so what spills is pale, never a dark ring. Rendered once per
/// photo, so the animation only ever moves a flat image.
enum SoftPhoto {
    private static let ciContext = CIContext()
    /// The rendered image is this much wider than the photo's circle, to hold the spill.
    static let reach: CGFloat = 1.2

    /// `diameter` is the photo circle's, in points; the image is `reach` times wider, rendered at 3x.
    /// `wash` is the liquid the rim melts into.
    static func render(_ source: UIImage, diameter: CGFloat, wash: UIColor) -> UIImage {
        let size = CGSize(width: diameter * reach, height: diameter * reach)
        let rect = CGRect(origin: .zero, size: size)
        let circle = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false

        // The photo in its circle, liquid everywhere else, so the blur spills liquid-coloured.
        let square = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            wash.setFill()
            UIBezierPath(rect: rect).fill()
            source.draw(in: aspectFill(source.size, in: circle))
            let outside = UIBezierPath(rect: rect)
            outside.append(UIBezierPath(ovalIn: circle))
            outside.usesEvenOddFillRule = true
            wash.setFill()
            outside.fill()
        }
        let soft = blur(square, sigma: diameter * 0.07 * format.scale)

        // Fractions below are of the circle's radius; `fade` measures against the image's.
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            // The blurred copy, lightened and washed, reaching past the circle and fading out...
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            soft.draw(in: rect)
            cg.setFillColor(UIColor.white.withAlphaComponent(0.2).cgColor)
            cg.fill(rect)
            cg.setFillColor(wash.withAlphaComponent(0.45).cgColor)
            cg.fill(rect)
            fade(cg, in: rect, from: 0.9 / reach, to: 1)
            cg.endTransparencyLayer()
            // ...under the sharp middle, which dissolves into it.
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            square.draw(in: rect)
            fade(cg, in: rect, from: 0.45 / reach, to: 0.78 / reach)
            cg.endTransparencyLayer()
        }
    }

    /// Keeps what's already drawn inside `from` (a fraction of the radius) and fades it out to nothing at `to`.
    private static func fade(_ cg: CGContext, in rect: CGRect, from: CGFloat, to: CGFloat) {
        let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [from, to]) else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        cg.saveGState()
        cg.setBlendMode(.destinationIn)
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                              endRadius: rect.width / 2, options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    private static func blur(_ image: UIImage, sigma: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: input.extent)
        guard let result = ciContext.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    private static func aspectFill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
