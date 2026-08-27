import XCTest
@testable import OnTrack

/// Covers the pure logic behind the paged onboarding flow: step ordering, the
/// height/weight validation gates, draft persistence across a simulated force-quit,
/// and that the targets reveal's arithmetic matches what Settings computes later.
final class OnboardingFlowTests: XCTestCase {

    override func tearDown() {
        OnboardingDraft.clearPersisted()
        super.tearDown()
    }

    // MARK: Step array shape

    func testFirstRunStepOrderAndCount() {
        let ids = OnboardingSteps.firstRun().map(\.id)
        XCTAssertEqual(ids, [
            "welcome", "sex", "age", "height", "weight", "activity", "goal",
            "targets", "demo-meal", "demo-workout", "demo-weight", "done",
        ])
    }

    func testOnlyWelcomeAndDoneHideProgressBar() {
        let steps = OnboardingSteps.firstRun()
        let progressFlags = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0.showsProgress) })
        XCTAssertEqual(progressFlags["welcome"], false)
        XCTAssertEqual(progressFlags["done"], false)
        for id in ["sex", "age", "height", "weight", "activity", "goal", "targets",
                   "demo-meal", "demo-workout", "demo-weight"] {
            XCTAssertEqual(progressFlags[id], true, "\(id) should show the progress bar")
        }
    }

    func testOnlyTheThreeCoreLoopDemosAreSkippable() {
        let steps = OnboardingSteps.firstRun()
        let skippable = Set(steps.filter(\.isSkippable).map(\.id))
        XCTAssertEqual(skippable, ["demo-meal", "demo-workout", "demo-weight"])
    }

    // MARK: Gating — height/weight are the only hard gates in the flow

    func testHeightStepBlocksEmptyAndNonNumericInput() {
        let step = OnboardingSteps.firstRun().first { $0.id == "height" }!
        let draft = OnboardingDraft()
        draft.heightText = ""
        XCTAssertFalse(step.isValid(draft))
        draft.heightText = "tall"
        XCTAssertFalse(step.isValid(draft))
        draft.heightText = "70"
        XCTAssertTrue(step.isValid(draft))
    }

    func testWeightStepBlocksEmptyAndNonNumericInput() {
        let step = OnboardingSteps.firstRun().first { $0.id == "weight" }!
        let draft = OnboardingDraft()
        draft.weightText = ""
        XCTAssertFalse(step.isValid(draft))
        draft.weightText = "heavy"
        XCTAssertFalse(step.isValid(draft))
        draft.weightText = "180"
        XCTAssertTrue(step.isValid(draft))
    }

    func testProfileStepsWithDefaultsAreAlwaysValid() {
        let draft = OnboardingDraft()
        let steps = OnboardingSteps.firstRun()
        for id in ["welcome", "sex", "age", "activity", "goal", "targets",
                   "demo-meal", "demo-workout", "demo-weight", "done"] {
            let step = steps.first { $0.id == id }!
            XCTAssertTrue(step.isValid(draft), "\(id) should be valid with default draft values")
        }
    }

    // MARK: Draft persistence — resume after a simulated force-quit

    func testDraftRoundTripsThroughUserDefaults() {
        let draft = OnboardingDraft()
        draft.sex = "female"
        draft.age = 42
        draft.heightText = "165"
        draft.weightText = "60"
        draft.activityLevel = "active"
        draft.weeklyRateLbs = -0.5
        draft.stepIndex = 4

        // A fresh instance simulates relaunching after the process was killed mid-flow.
        let resumed = OnboardingDraft()
        XCTAssertEqual(resumed.sex, "female")
        XCTAssertEqual(resumed.age, 42)
        XCTAssertEqual(resumed.heightText, "165")
        XCTAssertEqual(resumed.weightText, "60")
        XCTAssertEqual(resumed.activityLevel, "active")
        XCTAssertEqual(resumed.weeklyRateLbs, -0.5)
        XCTAssertEqual(resumed.stepIndex, 4)
    }

    func testClearPersistedResetsToDefaults() {
        let draft = OnboardingDraft()
        draft.sex = "female"
        draft.stepIndex = 6
        OnboardingDraft.clearPersisted()

        let fresh = OnboardingDraft()
        XCTAssertEqual(fresh.sex, "male")
        XCTAssertEqual(fresh.age, 25)
        XCTAssertEqual(fresh.activityLevel, "moderate")
        XCTAssertEqual(fresh.weeklyRateLbs, 0)
        XCTAssertEqual(fresh.stepIndex, 0)
    }

    // MARK: Unit conversion feeding the targets reveal

    func testHeightCmConvertsImperialAndPassesThroughMetric() {
        let draft = OnboardingDraft()
        draft.heightText = "70" // inches
        XCTAssertEqual(draft.heightCm(metric: false)!, 70 * 2.54, accuracy: 0.001)
        XCTAssertEqual(draft.heightCm(metric: true)!, 70, accuracy: 0.001)
    }

    func testWeightKgMatchesUnitsConversion() {
        let draft = OnboardingDraft()
        draft.weightText = "180" // lb
        XCTAssertEqual(draft.weightKg(metric: false)!, Units.displayToKg(180, metric: false), accuracy: 0.001)
    }

    func testHeightAndWeightReturnNilOnUnparsableText() {
        let draft = OnboardingDraft()
        draft.heightText = ""
        draft.weightText = "abc"
        XCTAssertNil(draft.heightCm(metric: false))
        XCTAssertNil(draft.weightKg(metric: false))
    }

    // MARK: Targets parity — the reveal's numbers must match what Settings computes later

    func testCalorieAndMacroTargetsAreDeterministicForADefaultedProfile() {
        let draft = OnboardingDraft()
        draft.heightText = "70"
        draft.weightText = "180"
        let profile = UserProfile()
        profile.age = draft.age
        profile.sex = draft.sex
        profile.heightCm = draft.heightCm(metric: false)!
        profile.activityLevel = draft.activityLevel
        profile.weeklyRateLbs = draft.weeklyRateLbs
        let weightKg = draft.weightKg(metric: false)!

        let cals = Calculations.calorieTarget(profile: profile, weightKg: weightKg)
        let macros = Calculations.macroTargets(profile: profile, weightKg: weightKg)

        XCTAssertGreaterThan(cals, 0)
        XCTAssertEqual(macros.protein, 1.8 * weightKg, accuracy: 0.01)
        XCTAssertEqual(cals, Calculations.tdee(profile: profile, weightKg: weightKg), accuracy: 0.01,
                       "Maintain (rate 0) should equal TDEE exactly")
    }

    func testPreviewTargetsMatchesCalculationsDirectly() {
        // Both TargetsStep and the "log a meal" demo read draft.previewTargets — it
        // must agree with calling Calculations directly on the same profile.
        let draft = OnboardingDraft()
        draft.heightText = "70"
        draft.weightText = "180"
        draft.activityLevel = "active"
        draft.weeklyRateLbs = -0.5

        let profile = UserProfile()
        profile.age = draft.age
        profile.sex = draft.sex
        profile.heightCm = draft.heightCm(metric: false)!
        profile.activityLevel = draft.activityLevel
        profile.weeklyRateLbs = draft.weeklyRateLbs
        let weightKg = draft.weightKg(metric: false)!
        let expectedCals = Calculations.calorieTarget(profile: profile, weightKg: weightKg)
        let expectedMacros = Calculations.macroTargets(profile: profile, weightKg: weightKg)

        let preview = draft.previewTargets(metric: false)
        XCTAssertEqual(preview.cals, expectedCals, accuracy: 0.01)
        XCTAssertEqual(preview.protein, expectedMacros.protein, accuracy: 0.01)
        XCTAssertEqual(preview.carbs, expectedMacros.carbs, accuracy: 0.01)
        XCTAssertEqual(preview.fat, expectedMacros.fat, accuracy: 0.01)
    }
}
