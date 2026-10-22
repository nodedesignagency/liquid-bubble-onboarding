/// One onboarding page: a short heading, one calm sentence, and the bubble arrangement between them.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let body: String
    let scene: OrbitScene
}

extension OnboardingStep {
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Your world",
            body: "Everyone you love, one tap away. Wherever they are.",
            scene: .world
        ),
        OnboardingStep(
            id: 1,
            title: "Friends of friends",
            body: "Meet the people your people already love, without the awkward intro.",
            scene: .friendsOfFriends
        ),
        OnboardingStep(
            id: 2,
            title: "Crews",
            body: "Roomies, run club, the family chat. Every crew gets its own little bubble.",
            scene: .crews
        ),
        OnboardingStep(
            id: 3,
            title: "Bump to connect",
            body: "Hold two phones together and you're in each other's orbit. That's it.",
            scene: .orbit
        ),
    ]
}
