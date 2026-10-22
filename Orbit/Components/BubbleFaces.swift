import SwiftUI
import UIKit
import CoreImage

/// A friend's photo, already softened (see `SoftPhoto`). Falls back to initials if the photo is missing.
struct AvatarFace: View {
    let person: Person
    let diameter: CGFloat

    var body: some View {
        if let photo = person.softPhoto {
            Image(uiImage: photo)
                .resizable()
                .frame(width: diameter, height: diameter)
        } else {
            Text(person.initials)
                .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(Theme.inkSecondary, in: Circle())
        }
    }
}

/// The globe everyone buds out of.
struct EarthFace: View {
    static let photo = UIImage(named: "earth").map { SoftPhoto.render($0, diameter: 260) }

    let diameter: CGFloat

    var body: some View {
        if let photo = Self.photo {
            Image(uiImage: photo)
                .resizable()
                .frame(width: diameter, height: diameter)
        }
    }
}

/// No border and no shadow: the middle of the photo stays sharp, the outer rim goes soft and
/// blurry and takes on the liquid's color, and the very edge fades out so the photo melts into
/// the liquid around it. Rendered once per photo, so the animation only ever moves a flat image.
enum SoftPhoto {
    private static let ciContext = CIContext()
    /// `Theme.liquid`.
    private static let liquid = UIColor(red: 0xDC / 255, green: 0xD3 / 255, blue: 0xF7 / 255, alpha: 1)

    /// `diameter` is in points; the image is rendered at 3x.
    static func render(_ source: UIImage, diameter: CGFloat) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false

        let square = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: aspectFill(source.size, in: rect))
            // Fill the corners outside the circle with liquid, so the blur can't drag dark corners into the rim.
            let corners = UIBezierPath(rect: rect)
            corners.append(UIBezierPath(ovalIn: rect))
            corners.usesEvenOddFillRule = true
            liquid.setFill()
            corners.fill()
        }
        let blurred = blur(square, sigma: diameter * 0.05 * format.scale)

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            // Blurry rim washed with the liquid's color, fading out at the edge...
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            blurred.draw(in: rect)
            cg.setFillColor(liquid.withAlphaComponent(0.35).cgColor)
            cg.fill(rect)
            fade(cg, in: rect, from: 0.72, to: 1)
            cg.endTransparencyLayer()
            // ...under a sharp middle that dissolves into it.
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            square.draw(in: rect)
            fade(cg, in: rect, from: 0.5, to: 0.82)
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
