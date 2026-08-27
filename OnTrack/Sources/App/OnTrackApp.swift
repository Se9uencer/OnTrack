import SwiftUI
import SwiftData

@main
struct OnTrackApp: App {
    let container: ModelContainer
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    init() {
        let schema = Schema([
            BodyWeightEntry.self, CustomExercise.self, WorkoutTemplate.self,
            TemplateExercise.self, WorkoutSession.self, LoggedSet.self,
            FoodItem.self, DiaryEntry.self, UserProfile.self, FaithLogEntry.self,
        ])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            )
        } catch {
            // ponytail: CloudKit needs signing + iCloud login; fall back to local-only so dev builds still run
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            )
        }
        NotificationService.shared.setupDelegate()
        MigrationService.dedupeFoodItems(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasOnboarded {
                    RootTabView()
                } else {
                    OnboardingRootView()
                }
            }
            .preferredColorScheme(.dark)
            .tint(.blue)
            .scrollDismissesKeyboard(.interactively)
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable {
    case today, diet, workout, weight, faith
}

/// A one-shot intent for the destination tab to act on and clear — how the feature
/// tour's "Try it" buttons reach past a tab switch into a specific sheet or screen.
enum TourDeepLink: Equatable {
    case dietSearch
    case dietScanner
    case dietPhotoMeal
    case workoutsList
    case weightGallery
    case settings
}

final class TabRouter: ObservableObject {
    static let shared = TabRouter()
    @Published var selected: AppTab = .today
    /// Set to true to push the Coach screen onto the Today tab's stack.
    @Published var presentCoach = false
    @Published var pendingDeepLink: TourDeepLink?

    /// Switches to `tab` and queues `deepLink` for that tab's view to consume once
    /// on appear. Used by the feature tour; destination views clear it after acting
    /// on it so it never re-fires on a later, unrelated visit to that tab.
    func navigate(to tab: AppTab, deepLink: TourDeepLink? = nil) {
        selected = tab
        pendingDeepLink = deepLink
    }
}

struct RootTabView: View {
    @StateObject private var router = TabRouter.shared

    var body: some View {
        TabView(selection: $router.selected) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(AppTab.today)
            DietView()
                .tabItem { Label("Diet", systemImage: "fork.knife") }
                .tag(AppTab.diet)
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)
            WeightView()
                .tabItem { Label("Weight", systemImage: "scalemass.fill") }
                .tag(AppTab.weight)
            FaithView()
                .tabItem { Label("Faith", systemImage: "moon.stars.fill") }
                .tag(AppTab.faith)
        }
    }
}
