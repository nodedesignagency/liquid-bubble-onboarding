/// One onboarding page: a short title, one line under it, and the scene the bubbles play.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let scene: OrbitScene
}

/// Which onboarding plays. v1 is the first story on lilac liquid, in pages; v2 is one screen in
/// the style of the Wabi app: swipe Earth up and your friends bubble out of it as liquid glass;
/// v3 pulls back from a city to the whole Earth, then your friends pop out of it in flat liquid.
enum OnboardingVersion: String, CaseIterable {
    case v1, v2, v3

    /// Renamed when v3 arrived, so the new default plays once even where v2 was remembered.
    static let storageKey = "onboardingVersion.3"

    /// v1's pages. v2 and v3 are single screens (`GlassOnboardingView`, `WorldOnboardingView`).
    var steps: [OnboardingStep] {
        switch self {
        case .v1: OnboardingStep.all
        case .v2, .v3: []
        }
    }

    /// What the bubbles do after "Get started" (v1) or "Continue" (v2, v3). v2 melts back into
    /// Earth and sinks to the gate, v3 melts back into Earth and dives back into the city: each
    /// ends on its first frame, so a screen recording loops.
    var finishScene: OrbitScene {
        switch self {
        case .v1: .collapse
        case .v2: .gate
        case .v3: .space
        }
    }

    /// The scene the placeholder home screen keeps playing.
    var homeScene: OrbitScene {
        switch self {
        case .v1: .world
        case .v2: .reveal
        case .v3: .bloom
        }
    }

    var look: StageLook {
        switch self {
        case .v1: .v1
        case .v2: .v2
        case .v3: .v3
        }
    }
}

extension OnboardingStep {
    /// v1. Keep in sync with `tools/preview/render.py` (`STEPS_V1`).
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "It starts with you",
            subtitle: "Your orbit begins with a single bubble.",
            scene: .you
        ),
        OnboardingStep(
            id: 1,
            title: "Bump to connect",
            subtitle: "Tap phones with a friend to join bubbles.",
            scene: .bump
        ),
        OnboardingStep(
            id: 2,
            title: "Your circle grows",
            subtitle: "Friends of friends, one bubble away.",
            scene: .circle
        ),
        OnboardingStep(
            id: 3,
            title: "Your world, in orbit",
            subtitle: "Everyone you love, wherever they are.",
            scene: .world
        ),
    ]
}
