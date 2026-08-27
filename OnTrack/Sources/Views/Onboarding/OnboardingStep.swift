import SwiftUI

/// One screen in a paged onboarding flow. Type-erases its content so a single
/// `[OnboardingStep]` array can mix different screens — the engine (OnboardingFlow)
/// stays identical whether it's rendering the first-run flow or, later, the full tour.
struct OnboardingStep: Identifiable {
    let id: String
    var showsProgress: Bool = true
    /// Shows a "Skip" control that jumps straight to the last step in the array,
    /// for optional screens (the core-loop demos) that shouldn't block finishing.
    var isSkippable: Bool = false
    var isValid: (OnboardingDraft) -> Bool = { _ in true }
    var ctaTitle: (OnboardingDraft) -> String = { _ in "Continue" }
    let content: (OnboardingDraft) -> AnyView

    init<V: View>(
        id: String,
        showsProgress: Bool = true,
        isSkippable: Bool = false,
        isValid: @escaping (OnboardingDraft) -> Bool = { _ in true },
        ctaTitle: @escaping (OnboardingDraft) -> String = { _ in "Continue" },
        @ViewBuilder content: @escaping (OnboardingDraft) -> V
    ) {
        self.id = id
        self.showsProgress = showsProgress
        self.isSkippable = isSkippable
        self.isValid = isValid
        self.ctaTitle = ctaTitle
        self.content = { AnyView(content($0)) }
    }
}

enum OnboardingSteps {
    /// The short, mandatory-profile first-run flow: one question per screen, a
    /// targets reveal, three skippable interactive demos of the core loop, and a
    /// closing screen that commits the profile.
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
            OnboardingStep(id: "targets") { draft in
                TargetsStep(draft: draft)
            },
            OnboardingStep(id: "demo-meal", isSkippable: true) { draft in
                LogMealDemoStep(draft: draft)
            },
            OnboardingStep(id: "demo-workout", isSkippable: true) { _ in
                StartWorkoutDemoStep()
            },
            OnboardingStep(id: "demo-weight", isSkippable: true) { _ in
                LogWeightDemoStep()
            },
            OnboardingStep(id: "done", showsProgress: false, ctaTitle: { _ in "Let's go" }) { _ in
                DoneStep()
            },
        ]
    }
}
