import SwiftUI
import UIKit

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

/// The reference's photo edge: a sharp photo under a feathered circular mask. It is a mask, not a
/// blur: the photo stays sharp to the edge and the edge turns translucent over the outer quarter
/// of the radius, so the liquid behind shows through it. Nothing is drawn outside the circle and
/// nothing is blurred, so no ring of any kind can form around it. Rendered once per photo, so the
/// animation only ever moves a flat image.
enum SoftPhoto {
    /// Where the feather starts, as a fraction of the radius. It reaches zero at the edge.
    /// On a 49pt photo it fades from 41pt to 49pt: a short, clean fade. The reference's measured
    /// 11pt fade looked like haze around sharp photos on device.
    static let feather: CGFloat = 0.84

    /// `diameter` is in points; the image is rendered at 3x.
    static func render(_ source: UIImage, diameter: CGFloat) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            source.draw(in: aspectFill(source.size, in: rect))
            fade(cg, in: rect, from: feather, to: 1)
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

    private static func aspectFill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
