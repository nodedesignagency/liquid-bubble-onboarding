import SwiftUI

/// Placeholder for the real app: it keeps the last scene of the onboarding that just played
/// running, and lets you replay either onboarding.
struct HomeView: View {
    var version: OnboardingVersion = .v2
    var onReplay: (OnboardingVersion) -> Void

    var body: some View {
        switch version {
        case .v1:
            VStack(spacing: 0) {
                title
                    .frame(height: 52)
                BubbleStage(scene: version.homeScene, look: version.look)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                replay
            }
            .background(Theme.background)
        case .v2:
            // The revealed cluster over Earth, full screen, as the onboarding left it.
            ZStack {
                Theme.glassCanvas.ignoresSafeArea()
                BubbleStage(scene: version.homeScene, look: version.look)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    title
                    Spacer()
                    replay
                }
                .padding(.top, 220)
            }
        }
    }

    private var title: some View {
        Text("You're in orbit")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
    }

    private var replay: some View {
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
}

#Preview {
    HomeView { _ in }
}
