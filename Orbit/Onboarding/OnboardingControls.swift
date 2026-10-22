import SwiftUI

/// Solid ink pill: the strongest thing on a light, pastel screen.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.ink, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(SquishyButtonStyle())
    }
}

/// Story-style segments, the progress indicator people already know from social apps.
struct StoryProgress: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Theme.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.ink)
                            .frame(maxWidth: i <= index ? .infinity : 0)
                    }
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a faint ink wash before that.
    func glassBackground(in shape: some Shape) -> some View {
        modifier(GlassBackground(shape: shape))
    }
}

private struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(Theme.track, in: shape)
        }
        #else
        content.background(Theme.track, in: shape)
        #endif
    }
}
