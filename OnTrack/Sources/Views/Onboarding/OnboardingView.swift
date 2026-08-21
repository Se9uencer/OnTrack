import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("useMetric") private var useMetric = false

    @State private var age = 25
    @State private var sex = "male"
    @State private var heightDisplay = ""
    @State private var weightDisplay = ""
    @State private var activityLevel = "moderate"
    @State private var weeklyRateLbs = 0.0

    private var heightCm: Double? {
        guard let h = Double(heightDisplay) else { return nil }
        return useMetric ? h : h * 2.54 // inches → cm
    }
    private var weightKg: Double? {
        guard let w = Double(weightDisplay) else { return nil }
        return Units.displayToKg(w, metric: useMetric)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    Picker("Units", selection: $useMetric) {
                        Text("lb / in").tag(false)
                        Text("kg / cm").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Age: \(age)", value: $age, in: 13...100)
                    Picker("Sex", selection: $sex) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    TextField("Height (\(useMetric ? "cm" : "in"))", text: $heightDisplay)
                        .keyboardType(.decimalPad)
                    TextField("Weight (\(Units.weightLabel(metric: useMetric)))", text: $weightDisplay)
                        .keyboardType(.decimalPad)
                }
                Section("Lifestyle") {
                    Picker("Activity level", selection: $activityLevel) {
                        ForEach(Calculations.activityOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    Picker("Goal", selection: $weeklyRateLbs) {
                        ForEach(Calculations.goalOptions, id: \.self) { rate in
                            Text(Calculations.goalLabel(rate, metric: useMetric)).tag(rate)
                        }
                    }
                }
                if let h = heightCm, let w = weightKg {
                    Section("Your daily targets (editable later in Settings)") {
                        let preview = previewTargets(heightCm: h, weightKg: w)
                        LabeledContent("Calories", value: "\(Int(preview.cals)) kcal")
                        LabeledContent("Protein", value: "\(Int(preview.protein)) g")
                        LabeledContent("Carbs", value: "\(Int(preview.carbs)) g")
                        LabeledContent("Fat", value: "\(Int(preview.fat)) g")
                        Text("Based on published research — sources in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Get Started") { finish() }
                    .disabled(heightCm == nil || weightKg == nil)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Welcome to OnTrack")
            .keyboardDoneButton()
        }
    }

    private func previewTargets(heightCm: Double, weightKg: Double) -> (cals: Double, protein: Double, carbs: Double, fat: Double) {
        let p = UserProfile()
        p.age = age; p.sex = sex; p.heightCm = heightCm
        p.activityLevel = activityLevel; p.weeklyRateLbs = weeklyRateLbs
        let cals = Calculations.calorieTarget(profile: p, weightKg: weightKg)
        let m = Calculations.macroTargets(profile: p, weightKg: weightKg)
        return (cals, m.protein, m.carbs, m.fat)
    }

    private func finish() {
        guard let h = heightCm, let w = weightKg else { return }
        let profile = UserProfile()
        profile.age = age
        profile.sex = sex
        profile.heightCm = h
        profile.activityLevel = activityLevel
        profile.weeklyRateLbs = weeklyRateLbs
        context.insert(profile)
        context.insert(BodyWeightEntry(weightKg: w))
        Task {
            try? await HealthKitService.shared.requestAuthorization()
            try? await HealthKitService.shared.saveWeight(w, date: Date())
            _ = await NotificationService.shared.requestPermission()
        }
        hasOnboarded = true
    }
}
