import SwiftUI

/// One onboarding page: the heading copy plus the bubble arrangement shown under it.
struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    /// The part of `title` drawn in the accent color.
    let accent: String
    let subtitle: String
    let scene: OrbitScene

    var styledTitle: AttributedString {
        var text = AttributedString(title)
        if let range = text.range(of: accent) {
            text[range].foregroundColor = Theme.accent
        }
        return text
    }
}

extension OnboardingStep {
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Your whole world,\nin orbit",
            accent: "in orbit",
            subtitle: "Everyone you love, one tap away. Wherever they are.",
            scene: .world
        ),
        OnboardingStep(
            id: 1,
            title: "Friends bring\nfriends",
            accent: "friends",
            subtitle: "Meet the people your people already love. No cold intros.",
            scene: .friendsOfFriends
        ),
        OnboardingStep(
            id: 2,
            title: "A bubble for\nevery crew",
            accent: "every crew",
            subtitle: "Roomies, run club, the family chat. Each gets its own space.",
            scene: .crews
        ),
        OnboardingStep(
            id: 3,
            title: "Bump phones,\nbe friends",
            accent: "Bump",
            subtitle: "Hold two phones together and you're in each other's orbit.",
            scene: .orbit
        ),
    ]
}
