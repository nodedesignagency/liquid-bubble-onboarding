import SwiftUI

/// Placeholder for the real app. Onboarding ends by collapsing into Earth, and this
/// screen picks up from there by bursting the orbit ring back out.
struct HomeView: View {
    var onReplayOnboarding: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("You're in orbit")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(height: 52)

            BubbleStage(scene: .orbit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("Replay onboarding", action: onReplayOnboarding)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .frame(height: 44)
                .padding(.bottom, 12)
        }
        .background(Theme.background)
    }
}

#Preview {
    HomeView {}
}
