import SwiftUI

struct GoalStep: View {
    @Bindable var draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        StepScaffold(title: "What's your goal?") {
            VStack(spacing: 10) {
                ForEach(Calculations.goalOptions, id: \.self) { rate in
                    SelectableOptionRow(
                        label: Calculations.goalLabel(rate, metric: useMetric),
                        selected: draft.weeklyRateLbs == rate
                    ) {
                        draft.weeklyRateLbs = rate
                    }
                }
            }
        }
    }
}
