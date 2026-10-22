/// One onboarding page: a short title, one line under it, and the scene the bubbles play.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let scene: OrbitScene
}

extension OnboardingStep {
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
