import SwiftUI
import UIKit

/// How photos sit in the liquid. Triple-tap the onboarding screen in a debug build to switch.
enum PhotoStyle: String {
    /// Each photo is a glass orb (the `glassOrb` shader in `Liquid.metal`).
    case glass
    /// The sharp photo under a feathered circular mask (`SoftPhoto`).
    case mask

    static let storageKey = "photoStyle"
}

/// A friend's photo at `diameter`, as a glass orb or masked. Falls back to initials if the photo is missing.
struct AvatarFace: View {
    let person: Person
    let diameter: CGFloat
    let style: PhotoStyle

    var body: some View {
        switch style {
        case .glass:
            if let photo = person.photo {
                GlassOrb(image: photo, diameter: diameter)
            } else {
                initials
            }
        case .mask:
            if let photo = person.softPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: diameter, height: diameter)
            } else {
                initials
            }
        }
    }

    private var initials: some View {
        Text(person.initials)
            .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Theme.inkSecondary, in: Circle())
    }
}

/// The globe everyone buds out of.
struct EarthFace: View {
    static let photo = UIImage(named: "earth")
    static let softPhoto = photo.map { SoftPhoto.render($0, diameter: 260) }

    let diameter: CGFloat
    let style: PhotoStyle

    var body: some View {
        switch style {
        case .glass:
            if let photo = Self.photo {
                GlassOrb(image: photo, diameter: diameter)
            }
        case .mask:
            if let photo = Self.softPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: diameter, height: diameter)
            }
        }
    }
}

/// A square photo seen through a glass sphere. The shader does the circle, the lens and the light.
struct GlassOrb: View {
    let image: UIImage
    let diameter: CGFloat

    /// How far behind the glass the photo sits: more is a stronger lens. Matches `orb` in the preview tool.
    static let depth: Float = 0.16

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: diameter, height: diameter)
            .clipped()
            .layerEffect(
                ShaderLibrary.glassOrb(.boundingRect, .float(Self.depth)),
                // The lens looks inward from each pixel by at most 30% of the radius (near the rim).
                maxSampleOffset: CGSize(width: diameter * 0.16 + 2, height: diameter * 0.16 + 2),
                isEnabled: diameter > 2
            )
    }
}

/// The plain photo edge: a sharp photo under a feathered circular mask, translucent over the outer
/// 12% of the radius so the liquid shows through it. A mask, not a blur: nothing is blurred and
/// nothing is drawn outside the circle. Rendered once per photo.
enum SoftPhoto {
    /// Where the feather starts, as a fraction of the radius. It reaches zero at the edge.
    static let feather: CGFloat = 0.88

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
