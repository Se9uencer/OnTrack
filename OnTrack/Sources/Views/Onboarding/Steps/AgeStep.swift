import SwiftUI

struct AgeStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        StepScaffold(title: "How old are you?", subtitle: "Age affects your metabolic rate.") {
            VStack(spacing: 24) {
                Text("\(draft.age)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                Slider(
                    value: Binding(
                        get: { Double(draft.age) },
                        set: { draft.age = Int($0.rounded()) }
                    ),
                    in: 13...100,
                    step: 1
                )
            }
            .padding()
            .card()
        }
    }
}
