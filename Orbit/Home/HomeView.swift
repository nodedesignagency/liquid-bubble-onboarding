import SwiftUI

/// Placeholder for the real app. Onboarding ends by collapsing into Earth, and this
/// screen picks up from there by bursting the orbit ring back out.
struct HomeView: View {
    var onReplayOnboarding: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("You're in orbit")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                Text("This is where the main app starts.")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 68)

            BubbleStage(scene: .orbit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onReplayOnboarding) {
                Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .glassBackground(in: Capsule())
            }
            .buttonStyle(SquishyButtonStyle())
            .padding(.bottom, 12)
        }
        .background(Theme.background)
    }
}

#Preview {
    HomeView {}
}
