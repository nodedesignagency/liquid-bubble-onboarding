import SwiftUI

/// Solid ink pill.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
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

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.ink : Theme.hairline)
                    .frame(width: i == index ? 18 : 6, height: 6)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
