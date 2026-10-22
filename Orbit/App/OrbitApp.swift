import SwiftUI

@main
struct OrbitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // SF Pro Rounded everywhere.
                .fontDesign(.rounded)
                .tint(Theme.ink)
                // Designed light-only, like the reference.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    // Not persisted on purpose, so onboarding plays on every launch while we iterate on it.
    // Swap for `@AppStorage("hasFinishedOnboarding")` when the real app lands.
    @State private var hasFinishedOnboarding = false
    /// Which onboarding plays at launch: the last one replayed from the home screen.
    @AppStorage(OnboardingVersion.storageKey) private var versionName = OnboardingVersion.v2.rawValue

    private var version: OnboardingVersion { OnboardingVersion(rawValue: versionName) ?? .v2 }

    var body: some View {
        ZStack {
            if hasFinishedOnboarding {
                HomeView(version: version) { chosen in
                    versionName = chosen.rawValue
                    withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = false }
                }
                .transition(.opacity)
            } else {
                OnboardingView(version: version) {
                    withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = true }
                }
                // A fresh onboarding, from its first page, whenever the version changes.
                .id(version)
                .transition(.opacity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
