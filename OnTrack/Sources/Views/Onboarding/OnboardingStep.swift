import SwiftUI

/// One screen in a paged onboarding flow. Type-erases its content so a single
/// `[OnboardingStep]` array can mix different screens — the engine (OnboardingFlow)
/// stays identical whether it's rendering the first-run flow or, later, the full tour.
struct OnboardingStep: Identifiable {
    let id: String
    var showsProgress: Bool = true
    var isValid: (OnboardingDraft) -> Bool = { _ in true }
    var ctaTitle: (OnboardingDraft) -> String = { _ in "Continue" }
    let content: (OnboardingDraft) -> AnyView

    init<V: View>(
        id: String,
        showsProgress: Bool = true,
        isValid: @escaping (OnboardingDraft) -> Bool = { _ in true },
        ctaTitle: @escaping (OnboardingDraft) -> String = { _ in "Continue" },
        @ViewBuilder content: @escaping (OnboardingDraft) -> V
    ) {
        self.id = id
        self.showsProgress = showsProgress
        self.isValid = isValid
        self.ctaTitle = ctaTitle
        self.content = { AnyView(content($0)) }
    }
}

enum OnboardingSteps {
    /// The short, mandatory-profile first-run flow: one question per screen, ending
    /// with the targets reveal. The three interactive core-loop demos land after this.
    static func firstRun() -> [OnboardingStep] {
        [
            OnboardingStep(id: "welcome", showsProgress: false, ctaTitle: { _ in "Get Started" }) { _ in
                WelcomeStep()
            },
            OnboardingStep(id: "sex") { draft in
                SexStep(draft: draft)
            },
            OnboardingStep(id: "age") { draft in
                AgeStep(draft: draft)
            },
            OnboardingStep(id: "height", isValid: { Double($0.heightText) != nil }) { draft in
                HeightStep(draft: draft)
            },
            OnboardingStep(id: "weight", isValid: { Double($0.weightText) != nil }) { draft in
                WeightStep(draft: draft)
            },
            OnboardingStep(id: "activity") { draft in
                ActivityStep(draft: draft)
            },
            OnboardingStep(id: "goal") { draft in
                GoalStep(draft: draft)
            },
            OnboardingStep(id: "targets", showsProgress: false, ctaTitle: { _ in "Get Started" }) { draft in
                TargetsStep(draft: draft)
            },
        ]
    }
}
