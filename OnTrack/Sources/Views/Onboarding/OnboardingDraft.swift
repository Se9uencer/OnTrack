import Foundation
import Observation

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

    var sex: String { didSet { UserDefaults.standard.set(sex, forKey: Key.sex) } }
    var age: Int { didSet { UserDefaults.standard.set(age, forKey: Key.age) } }
    var heightText: String { didSet { UserDefaults.standard.set(heightText, forKey: Key.heightText) } }
    var weightText: String { didSet { UserDefaults.standard.set(weightText, forKey: Key.weightText) } }
    var activityLevel: String { didSet { UserDefaults.standard.set(activityLevel, forKey: Key.activityLevel) } }
    var weeklyRateLbs: Double { didSet { UserDefaults.standard.set(weeklyRateLbs, forKey: Key.weeklyRateLbs) } }
    var stepIndex: Int { didSet { UserDefaults.standard.set(stepIndex, forKey: Key.stepIndex) } }

    init() {
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
}
