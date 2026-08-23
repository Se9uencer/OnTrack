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
                    OnboardingView()
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

final class TabRouter: ObservableObject {
    static let shared = TabRouter()
    @Published var selected: AppTab = .today
    /// Set to true to push the Coach screen onto the Today tab's stack.
    @Published var presentCoach = false
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
