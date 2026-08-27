import SwiftUI

struct WeightStep: View {
    @Bindable var draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        StepScaffold(title: "What do you weigh?", subtitle: "This becomes your first weigh-in.") {
            HStack {
                TextField(Units.weightLabel(metric: useMetric), text: $draft.weightText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(Units.weightLabel(metric: useMetric))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .card()
        }
    }
}
