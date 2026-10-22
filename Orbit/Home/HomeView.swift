import SwiftUI

/// Placeholder for the real app: it keeps the last scene of the onboarding that just played
/// running, and lets you replay either onboarding.
struct HomeView: View {
    var version: OnboardingVersion = .v2
    var onReplay: (OnboardingVersion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("You're in orbit")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(height: 52)

            BubbleStage(scene: version.homeScene, look: version.look)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 28) {
                ForEach(OnboardingVersion.allCases, id: \.self) { option in
                    Button("Replay \(option.rawValue)") { onReplay(option) }
                        .font(.system(size: 16, weight: option == version ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(option == version ? Theme.ink : Theme.inkSecondary)
                }
            }
            .frame(height: 44)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
    }
}

#Preview {
    HomeView { _ in }
}
