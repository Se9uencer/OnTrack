import SwiftUI

struct ActivityStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        StepScaffold(title: "How active are you?", subtitle: "Be honest — this drives your calorie target.") {
            VStack(spacing: 10) {
                ForEach(Calculations.activityOptions, id: \.key) { option in
                    SelectableOptionRow(label: option.label, selected: draft.activityLevel == option.key) {
                        draft.activityLevel = option.key
                    }
                }
            }
        }
    }
}
