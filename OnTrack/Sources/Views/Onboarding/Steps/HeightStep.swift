import SwiftUI

struct HeightStep: View {
    @Bindable var draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        StepScaffold(title: "How tall are you?") {
            VStack(spacing: 20) {
                Picker("Units", selection: $useMetric) {
                    Text("in").tag(false)
                    Text("cm").tag(true)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField(useMetric ? "cm" : "in", text: $draft.heightText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(useMetric ? "cm" : "in")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .card()
            }
        }
    }
}
