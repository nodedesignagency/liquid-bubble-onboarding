/// One onboarding page: a short title, one line under it, and the scene the bubbles play.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let scene: OrbitScene
}

/// Which onboarding plays. v1 is the first story on lilac liquid; v2 opens on Earth and its
/// glass orbs are the liquid themselves.
enum OnboardingVersion: String, CaseIterable {
    case v1, v2

    static let storageKey = "onboardingVersion"

    var steps: [OnboardingStep] {
        switch self {
        case .v1: OnboardingStep.all
        case .v2: OnboardingStep.v2
        }
    }

    /// What the bubbles do after "Get started". v2 melts back into Earth, its first frame, so a
    /// screen recording loops.
    var finishScene: OrbitScene {
        switch self {
        case .v1: .collapse
        case .v2: .planet
        }
    }

    /// The scene the placeholder home screen keeps playing.
    var homeScene: OrbitScene {
        switch self {
        case .v1: .world
        case .v2: .orbit
        }
    }

    var look: StageLook {
        switch self {
        case .v1: .v1
        case .v2: .v2
        }
    }
}

extension OnboardingStep {
    /// v2: born from the world. Keep in sync with `tools/preview/render.py` (`STEPS_V2`).
    static let v2: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Your world",
            subtitle: "Everyone you love is somewhere in it.",
            scene: .planet
        ),
        OnboardingStep(
            id: 1,
            title: "It starts with you",
            subtitle: "Your own bubble, rising out of it.",
            scene: .rise
        ),
        OnboardingStep(
            id: 2,
            title: "Your people find you",
            subtitle: "Friends rise up and join your bubble.",
            scene: .gather
        ),
        OnboardingStep(
            id: 3,
            title: "Your world, in orbit",
            subtitle: "Now it all moves around you.",
            scene: .orbit
        ),
    ]

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
