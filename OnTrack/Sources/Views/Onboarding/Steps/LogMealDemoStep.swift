import SwiftUI

/// Interactive, skippable: tapping the sample meal fills the real ProgressRing/
/// MacroRingCard components with real numbers computed against the user's own
/// targets — entirely in @State, so nothing touches SwiftData and the diary is
/// still empty on day one.
struct LogMealDemoStep: View {
    let draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false
    @State private var logged = false

    private let sampleName = "Grilled Chicken Bowl"
    private let sampleCalories = 520.0
    private let sampleProtein = 45.0
    private let sampleCarbs = 55.0
    private let sampleFat = 12.0

    private func fraction(_ eaten: Double, _ target: Double) -> Double {
        target > 0 ? min(eaten / target, 1) : 0
    }

    var body: some View {
        let t = draft.previewTargets(metric: useMetric)
        let eatenCals = logged ? sampleCalories : 0
        let eatenProtein = logged ? sampleProtein : 0
        let eatenCarbs = logged ? sampleCarbs : 0
        let eatenFat = logged ? sampleFat : 0

        StepScaffold(
            title: "Log a meal",
            subtitle: "Search thousands of foods, scan a barcode, or snap a photo. Tap the sample meal to see it happen."
        ) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(max(0, t.cals - eatenCals)))")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(logged ? "Calories left" : "Calorie budget")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(fraction: fraction(eatenCals, t.cals), color: .accentColor, lineWidth: 10) {
                        Image(systemName: "flame.fill").font(.title2).foregroundStyle(.secondary)
                    }
                    .frame(width: 92, height: 92)
                }
                .padding()
                .card()

                HStack(spacing: 12) {
                    MacroRingCard(title: "Protein left", left: t.protein - eatenProtein,
                                  fraction: fraction(eatenProtein, t.protein), icon: "bolt.fill", color: .red)
                    MacroRingCard(title: "Carbs left", left: t.carbs - eatenCarbs,
                                  fraction: fraction(eatenCarbs, t.carbs), icon: "leaf.fill", color: .orange)
                    MacroRingCard(title: "Fat left", left: t.fat - eatenFat,
                                  fraction: fraction(eatenFat, t.fat), icon: "drop.fill", color: .blue)
                }

                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        logged.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "fork.knife").foregroundStyle(Color.accentColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sampleName).font(.subheadline.bold())
                            Text("\(Int(sampleCalories)) cal · \(Int(sampleProtein))g protein")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(logged ? .green : Color.accentColor)
                    }
                    .padding()
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
