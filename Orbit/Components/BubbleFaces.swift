import SwiftUI

/// A friend's photo. Like the reference, it has no border: the edge is feathered and gently
/// vignetted so the photo melts into the liquid around it.
/// Falls back to initials, the way real contact avatars do, if the photo is missing.
struct AvatarFace: View {
    let person: Person
    let diameter: CGFloat

    var body: some View {
        ZStack {
            if let photo = person.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.accent
                Text(person.initials)
                    .font(.system(size: diameter * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
        .modifier(SoftCircle(diameter: diameter))
    }
}

/// The globe everyone pops out of.
struct EarthFace: View {
    let diameter: CGFloat

    var body: some View {
        Image("earth")
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .modifier(SoftCircle(diameter: diameter))
    }
}

/// Circular crop with a darkened, feathered rim instead of a hard edge.
private struct SoftCircle: ViewModifier {
    let diameter: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RadialGradient(
                    stops: [.init(color: .clear, location: 0.6), .init(color: .black.opacity(0.18), location: 1)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .clipShape(Circle())
            .mask {
                RadialGradient(
                    stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            }
    }
}
