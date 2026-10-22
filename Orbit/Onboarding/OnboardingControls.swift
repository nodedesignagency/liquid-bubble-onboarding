import SwiftUI

/// Round arrow button. A thin ring around it fills as you move through the pages.
struct NextButton: View {
    var progress: Double
    var isLast: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Theme.ink)
                    .padding(7)
                Image(systemName: isLast ? "checkmark" : "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 68, height: 68)
            .contentShape(Circle())
        }
        .buttonStyle(SquishyButtonStyle())
        .accessibilityLabel(isLast ? "Get started" : "Next")
    }
}

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
