import SwiftUI

@main
struct OrbitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // SF Pro Rounded everywhere.
                .fontDesign(.rounded)
                .tint(Theme.accent)
                // Designed light-only, like the reference.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    // Not persisted on purpose, so onboarding plays on every launch while we iterate on it.
    // Swap for `@AppStorage("hasFinishedOnboarding")` when the real app lands.
    @State private var hasFinishedOnboarding = false

    var body: some View {
        ZStack {
            if hasFinishedOnboarding {
                HomeView {
                    withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = false }
                }
                .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
