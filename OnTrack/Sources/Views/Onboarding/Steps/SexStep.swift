import SwiftUI

struct SexStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        StepScaffold(title: "What's your sex?", subtitle: "Used to calculate your calorie and macro targets.") {
            VStack(spacing: 12) {
                SelectableOptionRow(label: "Male", selected: draft.sex == "male") {
                    draft.sex = "male"
                }
                SelectableOptionRow(label: "Female", selected: draft.sex == "female") {
                    draft.sex = "female"
                }
            }
        }
    }
}
