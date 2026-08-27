import SwiftUI

/// The full, replayable feature tour — reachable from Settings and from a
/// dismissible card on Today. Reuses the same OnboardingFlow engine that renders
/// first-run onboarding; the draft parameter each step closure receives is unused
/// here since there's nothing to edit, only features to demonstrate.
enum TourSlides {
    /// Bump this whenever a new feature is worth re-surfacing the "Take the tour"
    /// card to everyone, including users who already finished onboarding.
    static let currentVersion = 1

    /// Where a "Try it" tap left off — the next slide to resume at, or -1 if there's
    /// nothing paused. Read by Today's "Continue the tour" card and by Settings.
    static let resumeIndexKey = "tourResumeIndex"

    private struct Spec {
        let id: String
        let icon: String
        let title: String
        let message: String
        let tryIt: String
        var ctaTitle: String = "Continue"
        let action: () -> Void
    }

    private static let specs: [Spec] = [
        Spec(id: "tour-dashboard", icon: "sun.max.fill", title: "Your dashboard",
             message: "Calories, macros, your last workout, and today's weigh-in — all on one screen. Tap any card to jump straight into that tab.",
             tryIt: "Go to Today") {
            TabRouter.shared.navigate(to: .today)
        },
        Spec(id: "tour-search", icon: "magnifyingglass", title: "Search 12,000+ foods",
             message: "The bundled food database works fully offline — search, tap, log. No signal required.",
             tryIt: "Search foods") {
            TabRouter.shared.navigate(to: .diet, deepLink: .dietSearch)
        },
        Spec(id: "tour-scanner", icon: "barcode.viewfinder", title: "Scan a barcode",
             message: "Point your camera at any packaged food for an instant nutrition lookup.",
             tryIt: "Scan a barcode") {
            TabRouter.shared.navigate(to: .diet, deepLink: .dietScanner)
        },
        Spec(id: "tour-photo", icon: "camera.fill", title: "Photograph a meal",
             message: "No barcode, no match? Snap a photo and AI estimates the nutrition for you.",
             tryIt: "Try Photo Meal") {
            TabRouter.shared.navigate(to: .diet, deepLink: .dietPhotoMeal)
        },
        Spec(id: "tour-split", icon: "list.bullet.rectangle", title: "Build your split",
             message: "Create workout templates from a 616-exercise library, or add your own exercises.",
             tryIt: "See your workouts") {
            TabRouter.shared.navigate(to: .workout, deepLink: .workoutsList)
        },
        Spec(id: "tour-session", icon: "dumbbell.fill", title: "Run a session",
             message: "Log sets as you go, with a built-in rest timer between them.",
             tryIt: "Go to Workout") {
            TabRouter.shared.navigate(to: .workout)
        },
        Spec(id: "tour-trend", icon: "chart.line.uptrend.xyaxis", title: "Track the trend",
             message: "Weigh in and watch the trend over time, with two-way Apple Health sync.",
             tryIt: "Go to Weight") {
            TabRouter.shared.navigate(to: .weight)
        },
        Spec(id: "tour-photos", icon: "photo.stack", title: "Progress photos",
             message: "Attach a photo to any weigh-in, then scrub through them chronologically.",
             tryIt: "See progress photos") {
            TabRouter.shared.navigate(to: .weight, deepLink: .weightGallery)
        },
        Spec(id: "tour-coach", icon: "brain.head.profile", title: "Your AI coach",
             message: "Ask anything — the Coach knows your real logs, workouts, and weight, and gives you a daily insight.",
             tryIt: "Open Coach") {
            TabRouter.shared.selected = .today
            TabRouter.shared.presentCoach = true
        },
        Spec(id: "tour-targets", icon: "slider.horizontal.3", title: "Tune your targets",
             message: "Calories and macros are computed from your profile — override any of them anytime.",
             tryIt: "Open Settings", ctaTitle: "Done") {
            TabRouter.shared.navigate(to: .today, deepLink: .settings)
        },
    ]

    /// The resume marker to store after a "Try it" tap on slide `index` of `total` —
    /// the next slide, or -1 when there's nothing left to resume (the last slide).
    static func resumeIndex(afterTryItOn index: Int, of total: Int) -> Int {
        let next = index + 1
        return next < total ? next : -1
    }

    static func all() -> [OnboardingStep] {
        specs.enumerated().map { index, spec in
            OnboardingStep(id: spec.id, ctaTitle: { _ in spec.ctaTitle }) { _ in
                TourSlideView(icon: spec.icon, title: spec.title, message: spec.message, tryItLabel: spec.tryIt) {
                    UserDefaults.standard.set(resumeIndex(afterTryItOn: index, of: specs.count), forKey: resumeIndexKey)
                    spec.action()
                }
            }
        }
    }
}
