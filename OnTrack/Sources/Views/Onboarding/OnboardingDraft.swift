import Foundation
import Observation
import SwiftData

/// In-progress onboarding answers, persisted to UserDefaults as the user goes so a
/// force-quit mid-flow resumes at the same step instead of restarting from Welcome.
/// Cleared entirely once the profile is committed to SwiftData in finish().
@Observable
final class OnboardingDraft {
    private enum Key {
        static let sex = "onboardingDraft.sex"
        static let age = "onboardingDraft.age"
        static let heightText = "onboardingDraft.heightText"
        static let weightText = "onboardingDraft.weightText"
        static let activityLevel = "onboardingDraft.activityLevel"
        static let weeklyRateLbs = "onboardingDraft.weeklyRateLbs"
        static let stepIndex = "onboardingDraft.stepIndex"
    }

    /// False for a throwaway instance — the replayable tour reuses this type purely to
    /// satisfy OnboardingStep's content-closure signature (tour slides ignore it) and
    /// must never read or write the real onboarding draft's UserDefaults keys.
    private let persists: Bool

    var sex: String { didSet { if persists { UserDefaults.standard.set(sex, forKey: Key.sex) } } }
    var age: Int { didSet { if persists { UserDefaults.standard.set(age, forKey: Key.age) } } }
    var heightText: String { didSet { if persists { UserDefaults.standard.set(heightText, forKey: Key.heightText) } } }
    var weightText: String { didSet { if persists { UserDefaults.standard.set(weightText, forKey: Key.weightText) } } }
    var activityLevel: String { didSet { if persists { UserDefaults.standard.set(activityLevel, forKey: Key.activityLevel) } } }
    var weeklyRateLbs: Double { didSet { if persists { UserDefaults.standard.set(weeklyRateLbs, forKey: Key.weeklyRateLbs) } } }
    var stepIndex: Int { didSet { if persists { UserDefaults.standard.set(stepIndex, forKey: Key.stepIndex) } } }

    init(persists: Bool = true) {
        self.persists = persists
        guard persists else {
            sex = "male"
            age = 25
            heightText = ""
            weightText = ""
            activityLevel = "moderate"
            weeklyRateLbs = 0
            stepIndex = 0
            return
        }
        let d = UserDefaults.standard
        sex = d.string(forKey: Key.sex) ?? "male"
        age = d.object(forKey: Key.age) != nil ? d.integer(forKey: Key.age) : 25
        heightText = d.string(forKey: Key.heightText) ?? ""
        weightText = d.string(forKey: Key.weightText) ?? ""
        activityLevel = d.string(forKey: Key.activityLevel) ?? "moderate"
        weeklyRateLbs = d.double(forKey: Key.weeklyRateLbs) // absent -> 0, which is the "Maintain" default
        stepIndex = d.integer(forKey: Key.stepIndex) // absent -> 0, the Welcome step
    }

    /// Wipes every draft key. Call once the profile has been written to SwiftData.
    static func clearPersisted() {
        let d = UserDefaults.standard
        for key in [Key.sex, Key.age, Key.heightText, Key.weightText, Key.activityLevel, Key.weeklyRateLbs, Key.stepIndex] {
            d.removeObject(forKey: key)
        }
    }

    func heightCm(metric: Bool) -> Double? {
        guard let h = Double(heightText) else { return nil }
        return metric ? h : h * 2.54 // inches -> cm
    }

    func weightKg(metric: Bool) -> Double? {
        guard let w = Double(weightText) else { return nil }
        return Units.displayToKg(w, metric: metric)
    }

    /// The calorie/macro targets these answers would produce — shared by the targets
    /// reveal and the "log a meal" demo so both show numbers computed the same way.
    func previewTargets(metric: Bool) -> (cals: Double, protein: Double, carbs: Double, fat: Double) {
        let p = UserProfile()
        p.age = age
        p.sex = sex
        p.heightCm = heightCm(metric: metric) ?? 175
        p.activityLevel = activityLevel
        p.weeklyRateLbs = weeklyRateLbs
        let weightKg = weightKg(metric: metric) ?? 70
        let cals = Calculations.calorieTarget(profile: p, weightKg: weightKg)
        let m = Calculations.macroTargets(profile: p, weightKg: weightKg)
        return (cals, m.protein, m.carbs, m.fat)
    }
}
