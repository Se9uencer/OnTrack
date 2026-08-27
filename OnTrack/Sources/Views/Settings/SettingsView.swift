import SwiftUI
import SwiftData

struct SettingsView: View {
    static let privacyPolicyURL = URL(string: "https://se9uencer.github.io/ontrack-privacy/")!

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @AppStorage("isPro") private var isProDebug = true
    @AppStorage("tourVersionSeen") private var tourVersionSeen = 0

    var body: some View {
        NavigationStack {
            Form {
                if let profile = profiles.first {
                    profileSection(profile)
                    targetsSection(profile)
                }
                Section("Units") {
                    Picker("Weight units", selection: $useMetric) {
                        Text("Pounds (lb)").tag(false)
                        Text("Kilograms (kg)").tag(true)
                    }
                }
                Section("Health") {
                    Button("Re-request HealthKit access") {
                        Task { try? await HealthKitService.shared.requestAuthorization() }
                    }
                }
                Section {
                    Button {
                        // The tour is always presented from Today, never from here —
                        // otherwise a slide's "Try it" would only dismiss the tour and
                        // leave this sheet covering the destination underneath it.
                        tourVersionSeen = TourSlides.currentVersion
                        TabRouter.shared.pendingTourOpen = true
                        dismiss()
                    } label: {
                        Label("Take the tour", systemImage: "sparkles")
                    }
                }
                Section {
                    Toggle("Share data with AI (Google Gemini)", isOn: $aiConsentGiven)
                } header: {
                    Text("AI")
                } footer: {
                    Text("Powers the Coach and Photo Meal features by sending meal photos and summaries of your workouts, diet, weight, and profile to Google Gemini via the developer's proxy. Apple Health data is never sent. Turn off to stop all AI data sharing.")
                }
                Section {
                    Link("Privacy Policy", destination: Self.privacyPolicyURL)
                } header: {
                    Text("About")
                } footer: {
                    Text("Nutrition data from Open Food Facts (ODbL) and USDA FoodData Central. Exercise data from the free-exercise-db.")
                }
                #if DEBUG
                Section("Developer") {
                    Toggle("Pro (debug)", isOn: $isProDebug)
                }
                #endif
            }
            .navigationTitle("Settings")
            .keyboardDoneButton()
        }
    }

    private var latestWeightKg: Double { weights.first?.weightKg ?? 70 }

    @ViewBuilder
    private func profileSection(_ profile: UserProfile) -> some View {
        Section("Profile") {
            Stepper("Age: \(profile.age)", value: Binding(
                get: { profile.age }, set: { profile.age = $0 }), in: 13...100)
            Picker("Sex", selection: Binding(get: { profile.sex }, set: { profile.sex = $0 })) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            Picker("Activity", selection: Binding(get: { profile.activityLevel }, set: { profile.activityLevel = $0 })) {
                ForEach(Calculations.activityOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            Picker("Goal", selection: Binding(get: { profile.weeklyRateLbs }, set: { profile.weeklyRateLbs = $0 })) {
                ForEach(Calculations.goalOptions, id: \.self) { rate in
                    Text(Calculations.goalLabel(rate, metric: useMetric)).tag(rate)
                }
            }
        }
    }

    @ViewBuilder
    private func targetsSection(_ profile: UserProfile) -> some View {
        let computedCals = Calculations.calorieTarget(profile: profile, weightKg: latestWeightKg)
        let macros = Calculations.macroTargets(profile: profile, weightKg: latestWeightKg)
        Section {
            overrideRow("Calories", unit: "kcal", computed: computedCals,
                        value: Binding(get: { profile.calorieOverride }, set: { profile.calorieOverride = $0 }))
            overrideRow("Protein", unit: "g", computed: macros.protein,
                        value: Binding(get: { profile.proteinOverride }, set: { profile.proteinOverride = $0 }))
            overrideRow("Carbs", unit: "g", computed: macros.carbs,
                        value: Binding(get: { profile.carbsOverride }, set: { profile.carbsOverride = $0 }))
            overrideRow("Fat", unit: "g", computed: macros.fat,
                        value: Binding(get: { profile.fatOverride }, set: { profile.fatOverride = $0 }))
            NavigationLink("How targets are calculated") {
                SourcesView()
            }
        } header: {
            Text("Daily targets")
        } footer: {
            Text("Computed from your profile (Mifflin-St Jeor). Enter a value to override; clear it to go back to computed.")
        }
    }

    private func overrideRow(_ label: String, unit: String, computed: Double, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("\(Int(computed))", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
