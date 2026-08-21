import Foundation

enum Calculations {
    // Mifflin-St Jeor
    static func bmr(profile: UserProfile, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        return profile.sex == "male" ? base + 5 : base - 161
    }

    // key, multiplier, and picker label — single source for both pickers.
    // Multipliers match calculator.net's calorie calculator exactly (same labels, same values).
    static let activityOptions: [(key: String, multiplier: Double, label: String)] = [
        ("sedentary", 1.2, "Sedentary: little or no exercise"),
        ("light", 1.375, "Light: exercise 1-3 times/week"),
        ("moderate", 1.465, "Moderate: exercise 4-5 times/week"),
        ("active", 1.55, "Active: daily exercise or intense exercise 3-4 times/week"),
        ("veryActive", 1.725, "Very Active: intense exercise 6-7 times/week"),
        ("extraActive", 1.9, "Extra Active: very intense exercise daily, or physical job"),
    ]

    static let activityMultipliers: [String: Double] =
        Dictionary(uniqueKeysWithValues: activityOptions.map { ($0.key, $0.multiplier) })

    static func tdee(profile: UserProfile, weightKg: Double) -> Double {
        bmr(profile: profile, weightKg: weightKg) * (activityMultipliers[profile.activityLevel] ?? 1.55)
    }

    // 1 lb of fat ≈ 3500 kcal, so 1 lb/week = 500 kcal/day adjustment.
    static func calorieTarget(profile: UserProfile, weightKg: Double) -> Double {
        if let o = profile.calorieOverride { return o }
        return tdee(profile: profile, weightKg: weightKg) + profile.weeklyRateLbs * 500
    }

    // The 5 goal choices, ordered aggressive-cut → aggressive-bulk.
    static let goalOptions: [Double] = [-1, -0.5, 0, 0.5, 1]

    static func goalLabel(_ rate: Double, metric: Bool) -> String {
        if rate == 0 { return "Maintain weight" }
        let verb = rate < 0 ? "Lose" : "Gain"
        let amount = metric
            ? String(format: "%.1f kg", abs(rate) * 0.453592)
            : (abs(rate) == 1 ? "1 lb" : "0.5 lb")
        return "\(verb) \(amount) / week"
    }

    // Compact form for the AI context.
    static func goalDescription(_ rate: Double) -> String {
        if rate == 0 { return "maintain weight" }
        return rate < 0 ? "cut \(abs(rate)) lb/week" : "bulk \(rate) lb/week"
    }

    // Standard split: protein 1.8 g/kg, fat 25% of calories, carbs the remainder.
    static func macroTargets(profile: UserProfile, weightKg: Double) -> (protein: Double, carbs: Double, fat: Double) {
        let cals = calorieTarget(profile: profile, weightKg: weightKg)
        let protein = profile.proteinOverride ?? (1.8 * weightKg)
        let fat = profile.fatOverride ?? (cals * 0.25 / 9)
        let carbs = profile.carbsOverride ?? max(0, (cals - protein * 4 - fat * 9) / 4)
        return (protein, carbs, fat)
    }
}

enum Units {
    static func kgToDisplay(_ kg: Double, metric: Bool) -> Double { metric ? kg : kg * 2.20462 }
    static func displayToKg(_ value: Double, metric: Bool) -> Double { metric ? value : value / 2.20462 }
    static func weightLabel(metric: Bool) -> String { metric ? "kg" : "lb" }
}
