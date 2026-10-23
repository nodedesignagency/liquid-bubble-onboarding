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
    @AppStorage(OnboardingVersion.storageKey) private var versionName = OnboardingVersion.v3.rawValue

    private var version: OnboardingVersion { OnboardingVersion(rawValue: versionName) ?? .v3 }

    var body: some View {
        ZStack {
            if hasFinishedOnboarding {
                HomeView(version: version) { chosen in
                    versionName = chosen.rawValue
                    withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = false }
                }
                .transition(.opacity)
            } else {
                Group {
                    switch version {
                    case .v1:
                        OnboardingView(version: .v1) { finishOnboarding() }
                    case .v2:
                        GlassOnboardingView { finishOnboarding() }
                    case .v3:
                        WorldOnboardingView { finishOnboarding() }
                    }
                }
                // A fresh onboarding, from its start, whenever the version changes.
                .id(version)
                .transition(.opacity)
            }
        }
        .background(canvas.ignoresSafeArea())
    }

    private var canvas: Color {
        switch version {
        case .v1: Theme.background
        case .v2: Theme.glassCanvas
        case .v3: Theme.worldCanvas
        }
    }

    private func finishOnboarding() {
        withAnimation(.smooth(duration: 0.5)) { hasFinishedOnboarding = true }
    }
}
