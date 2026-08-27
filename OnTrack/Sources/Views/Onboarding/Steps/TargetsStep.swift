import SwiftUI

/// The payoff screen: animates the computed targets in from empty rings. Read-only —
/// this is where the seven profile screens earn their keep before the "Get Started" CTA
/// (owned by OnboardingFlow) commits the profile.
struct TargetsStep: View {
    let draft: OnboardingDraft
    @AppStorage("useMetric") private var useMetric = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var weightKg: Double { draft.weightKg(metric: useMetric) ?? 70 }

    private var preview: (cals: Double, protein: Double, carbs: Double, fat: Double) {
        let p = UserProfile()
        p.age = draft.age
        p.sex = draft.sex
        p.heightCm = draft.heightCm(metric: useMetric) ?? 175
        p.activityLevel = draft.activityLevel
        p.weeklyRateLbs = draft.weeklyRateLbs
        let cals = Calculations.calorieTarget(profile: p, weightKg: weightKg)
        let m = Calculations.macroTargets(profile: p, weightKg: weightKg)
        return (cals, m.protein, m.carbs, m.fat)
    }

    var body: some View {
        let t = preview
        StepScaffold(title: "Your daily targets", subtitle: "Based on published research — fine-tune these anytime in Settings.") {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(t.cals))")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("Calories a day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(fraction: revealed ? 1 : 0, color: .accentColor, lineWidth: 10) {
                        Image(systemName: "flame.fill").font(.title2).foregroundStyle(.secondary)
                    }
                    .frame(width: 92, height: 92)
                }
                .padding()
                .card()

                HStack(spacing: 12) {
                    MacroRingCard(title: "Protein", left: t.protein, fraction: revealed ? 1 : 0, icon: "bolt.fill", color: .red)
                    MacroRingCard(title: "Carbs", left: t.carbs, fraction: revealed ? 1 : 0, icon: "leaf.fill", color: .orange)
                    MacroRingCard(title: "Fat", left: t.fat, fraction: revealed ? 1 : 0, icon: "drop.fill", color: .blue)
                }
            }
        }
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.15)) {
                    revealed = true
                }
            }
        }
    }
}
