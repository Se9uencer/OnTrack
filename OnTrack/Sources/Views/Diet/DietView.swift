import SwiftUI
import SwiftData

struct DietView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @Query(sort: \DiaryEntry.date) private var allEntries: [DiaryEntry]
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addingToMeal: String?
    @State private var pendingDeletion: [DiaryEntry] = []
    @State private var foodSearchInitialAction: FoodSearchView.InitialAction?
    @StateObject private var router = TabRouter.shared

    private let meals = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    daySwitcher
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                totalsSection
                ForEach(meals, id: \.self) { meal in
                    mealSection(meal)
                }
            }
            .navigationTitle("Diet")
            // day is @State (set once at init); without this it stays pinned to the
            // day the view was created and drifts from the live "today" the dashboard
            // shows once the clock crosses midnight.
            .onAppear { snapToToday(); handleDeepLink(router.pendingDeepLink) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { snapToToday() } }
            .onChange(of: router.pendingDeepLink) { _, link in handleDeepLink(link) }
            .confirmationDialog(
                "Delete this food?",
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deletePending() }
                Button("Cancel", role: .cancel) { pendingDeletion = [] }
            }
            .sheet(item: Binding(
                get: { addingToMeal.map { MealTarget(meal: $0) } },
                set: { addingToMeal = $0?.meal; if $0 == nil { foodSearchInitialAction = nil } })
            ) { target in
                FoodSearchView(meal: target.meal, day: day, initialAction: foodSearchInitialAction) {}
            }
        }
    }

    private struct MealTarget: Identifiable {
        let meal: String
        var id: String { meal }
    }

    private var dayEntries: [DiaryEntry] {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private var dayLabel: String {
        Calendar.current.isDateInToday(day) ? "Today" : day.formatted(date: .abbreviated, time: .omitted)
    }

    private var daySwitcher: some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(dayLabel)
                .font(.title3.bold())
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(Calendar.current.isDateInToday(day))
            .opacity(Calendar.current.isDateInToday(day) ? 0.3 : 1)
        }
        .padding(.horizontal, 4)
    }

    private func shiftDay(_ delta: Int) {
        day = Calendar.current.date(byAdding: .day, value: delta, to: day)!
    }

    private func snapToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        if day != today { day = today }
    }

    /// Consumes a diet-related tour deep link — opens the food search sheet, optionally
    /// straight into the scanner or photo capture. Clears the intent immediately so it
    /// never re-fires on a later, unrelated visit to this tab.
    private func handleDeepLink(_ link: TourDeepLink?) {
        switch link {
        case .dietSearch, .dietScanner, .dietPhotoMeal:
            break
        case .workoutsList, .weightGallery, .settings, nil:
            return
        }
        router.pendingDeepLink = nil
        switch link {
        case .dietScanner: foodSearchInitialAction = .scanner
        case .dietPhotoMeal: foodSearchInitialAction = .photoMeal
        default: foodSearchInitialAction = nil
        }
        addingToMeal = defaultMealForNow()
    }

    private func defaultMealForNow() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "breakfast"
        case 11..<16: return "lunch"
        case 16..<21: return "dinner"
        default: return "snack"
        }
    }

    private var totalsSection: some View {
        let cals = dayEntries.reduce(0) { $0 + $1.calories }
        let protein = dayEntries.reduce(0) { $0 + $1.protein }
        let carbs = dayEntries.reduce(0) { $0 + $1.carbs }
        let fat = dayEntries.reduce(0) { $0 + $1.fat }
        let profile = profiles.first
        let weightKg = weights.first?.weightKg ?? 70
        let target = profile.map { Calculations.calorieTarget(profile: $0, weightKg: weightKg) }
        let macros = profile.map { Calculations.macroTargets(profile: $0, weightKg: weightKg) }

        return Section {
            VStack(spacing: 10) {
                HStack {
                    Text("\(Int(cals))").font(.system(size: 34, weight: .bold))
                    if let target {
                        Text("/ \(Int(target)) kcal").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let target {
                        Text("\(Int(max(0, target - cals))) left")
                            .font(.subheadline).bold()
                            .foregroundStyle(cals > target ? .red : .green)
                    }
                }
                if let target { ProgressView(value: min(cals / max(target, 1), 1)) }
                HStack(spacing: 16) {
                    macroLabel("P", protein, macros?.protein)
                    macroLabel("C", carbs, macros?.carbs)
                    macroLabel("F", fat, macros?.fat)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    private func macroLabel(_ name: String, _ value: Double, _ target: Double?) -> some View {
        HStack(spacing: 3) {
            Text(name).bold()
            Text("\(Int(value))\(target.map { "/\(Int($0))" } ?? "")g")
                .foregroundStyle(.secondary)
        }
    }

    private func defaultServingLabel(_ entry: DiaryEntry) -> String {
        let servings = entry.numberOfServings.formatted(.number.precision(.fractionLength(0...1)))
        let size = (entry.food?.servingSize ?? 0).formatted(.number.precision(.fractionLength(0...1)))
        return "\(servings) × \(size)\(entry.food?.servingUnit ?? "")"
    }

    private func mealSection(_ meal: String) -> some View {
        let entries = dayEntries.filter { $0.meal == meal }
        return Section {
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    FoodThumbnail(imageFilename: entry.food?.imageFilename, source: entry.food?.source, size: 40)
                    VStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text(entry.food?.name ?? "Unknown")
                            if entry.food?.source == "ai" {
                                Text("Estimated").font(.caption2.bold()).foregroundStyle(.orange)
                            }
                        }
                        Text(entry.portionLabel.isEmpty ? defaultServingLabel(entry) : entry.portionLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(entry.calories)) kcal").foregroundStyle(.secondary)
                }
            }
            .onDelete { indexSet in
                pendingDeletion = indexSet.map { entries[$0] }
            }
            Button {
                addingToMeal = meal
            } label: {
                Label("Add food", systemImage: "plus")
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text(meal.capitalized)
                Spacer()
                if !entries.isEmpty {
                    Text("\(Int(entries.reduce(0) { $0 + $1.calories })) kcal")
                }
            }
        }
    }

    private func deletePending() {
        for e in pendingDeletion {
            // ponytail: photo FoodItems are created 1:1 per capture (never
            // reused), so deleting the entry's image can't strand another row.
            if let file = e.food?.imageFilename { ImageStore.delete(file) }
            context.delete(e)
        }
        pendingDeletion = []
    }
}
