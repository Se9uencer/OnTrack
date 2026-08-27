import SwiftUI

/// Imperial height is collected as feet + inches rather than a single "total inches"
/// field — the two local fields here are purely presentational. draft.heightText
/// keeps storing one combined number (cm if metric, else total inches) exactly as
/// every other step, HealthKitService, and Calculations already expect.
struct HeightStep: View {
    @Bindable var draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false
    @State private var feetText = ""
    @State private var inchesText = ""

    var body: some View {
        StepScaffold(title: "How tall are you?") {
            VStack(spacing: 20) {
                Picker("Units", selection: $useMetric) {
                    Text("ft/in").tag(false)
                    Text("cm").tag(true)
                }
                .pickerStyle(.segmented)

                if useMetric {
                    HStack {
                        TextField("cm", text: $draft.heightText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("cm")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .card()
                } else {
                    HStack(spacing: 0) {
                        heightField(text: $feetText, unit: "ft")
                        Divider().frame(height: 44)
                        heightField(text: $inchesText, unit: "in")
                    }
                    .padding()
                    .card()
                }
            }
        }
        .onAppear(perform: syncFieldsFromDraft)
        .onChange(of: useMetric) { _, _ in
            // Can't convert what's already typed when switching units mid-entry —
            // clear rather than silently reinterpret the same digits under the
            // other unit.
            draft.heightText = ""
            feetText = ""
            inchesText = ""
        }
        .onChange(of: feetText) { _, _ in updateDraftFromImperialFields() }
        .onChange(of: inchesText) { _, _ in updateDraftFromImperialFields() }
    }

    private func heightField(text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField(unit, text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(unit)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Splits the draft's stored total inches back into feet/inches for display —
    /// needed when resuming mid-flow, since the draft only stores one combined number.
    private func syncFieldsFromDraft() {
        guard !useMetric, let totalInches = Double(draft.heightText), totalInches > 0 else { return }
        var feet = Int(totalInches / 12)
        var remainder = Int((totalInches - Double(feet * 12)).rounded())
        if remainder == 12 {
            // Rounding a fractional remainder (e.g. a resumed 71.6") can round up to a
            // full extra foot — carry it over rather than displaying "12 in".
            feet += 1
            remainder = 0
        }
        feetText = String(feet)
        inchesText = remainder == 0 ? "" : String(remainder)
    }

    private func updateDraftFromImperialFields() {
        guard let feet = Double(feetText) else { return }
        let inches = Double(inchesText) ?? 0
        draft.heightText = String(feet * 12 + inches)
    }
}
