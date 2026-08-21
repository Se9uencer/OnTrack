import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let meal: String
    let day: Date
    var onLogged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FoodItem> { $0.isSaved }, sort: \FoodItem.name) private var savedFoods: [FoodItem]

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var searching = false
    @State private var searchError = false
    @State private var showingScanner = false
    @State private var showingPhotoMeal = false
    @State private var showingManualEntry = false
    @State private var pendingFood: FoodItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingScanner = true } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { showingPhotoMeal = true } label: {
                        Label("Photo of meal", systemImage: "camera.fill")
                    }
                    Button { showingManualEntry = true } label: {
                        Label("Manual entry", systemImage: "square.and.pencil")
                    }
                }
                if !savedFoods.isEmpty && query.isEmpty {
                    Section("Saved foods") {
                        ForEach(savedFoods) { food in
                            Button { pendingFood = food } label: { savedRow(food) }
                        }
                    }
                }
                if searching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                if searchError {
                    Text("Search failed — check your connection. Manual entry always works.")
                        .foregroundStyle(.secondary)
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { result in
                            Button {
                                let item = result.toFoodItem()
                                context.insert(item)
                                pendingFood = item
                            } label: {
                                resultRow(result)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .onSubmit(of: .search) { runSearch() }
            .navigationTitle("Add to \(meal.capitalized)")
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { barcode in
                    showingScanner = false
                    Task { await lookupBarcode(barcode) }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualFoodEntryView { item in
                    pendingFood = item
                }
            }
            .sheet(isPresented: $showingPhotoMeal) {
                MealPhotoView { item in
                    context.insert(item)
                    pendingFood = item
                }
            }
            .sheet(item: $pendingFood) { food in
                ServingsPickerView(food: food) { servings in
                    logEntry(food: food, servings: servings)
                }
            }
        }
    }

    private func savedRow(_ food: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(food.name).foregroundStyle(.primary)
                Text("\(Int(food.calories)) kcal / \(food.servingSize, format: .number.precision(.fractionLength(0...1)))\(food.servingUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
        }
    }

    private func resultRow(_ r: FoodSearchResult) -> some View {
        VStack(alignment: .leading) {
            Text(r.name).foregroundStyle(.primary)
            Text("\([r.brand, "\(Int(r.calories)) kcal / \(String(format: "%.0f", r.servingSize))\(r.servingUnit)"].compactMap { $0 }.joined(separator: " · "))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runSearch() {
        guard !query.isEmpty else { return }
        searching = true
        searchError = false
        results = []
        Task {
            let hits = await FoodSearchService.search(query)
            await MainActor.run {
                results = hits
                searching = false
                searchError = hits.isEmpty
            }
        }
    }

    private func lookupBarcode(_ barcode: String) async {
        searching = true
        let result = try? await FoodSearchService.lookupBarcode(barcode)
        await MainActor.run {
            searching = false
            if let result {
                let item = result.toFoodItem()
                context.insert(item)
                pendingFood = item
            } else {
                searchError = true
            }
        }
    }

    private func logEntry(food: FoodItem, servings: Double) {
        // Log against the selected day at the current time.
        let cal = Calendar.current
        let timeParts = cal.dateComponents([.hour, .minute], from: Date())
        let date = cal.date(bySettingHour: timeParts.hour ?? 12, minute: timeParts.minute ?? 0, second: 0, of: day) ?? day
        context.insert(DiaryEntry(date: date, meal: meal, food: food, numberOfServings: servings))
        onLogged()
        dismiss()
    }
}

struct ServingsPickerView: View {
    @Bindable var food: FoodItem
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servingsText = "1"

    private var servings: Double { Double(servingsText) ?? 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section(food.name) {
                    HStack {
                        Text("Servings")
                        TextField("1", text: $servingsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Serving size", value: "\(food.servingSize.formatted()) \(food.servingUnit)")
                    LabeledContent("Calories", value: "\(Int(food.calories * servings)) kcal")
                    LabeledContent("Protein", value: "\(Int(food.protein * servings)) g")
                    LabeledContent("Carbs", value: "\(Int(food.carbs * servings)) g")
                    LabeledContent("Fat", value: "\(Int(food.fat * servings)) g")
                }
                Toggle("Save to my foods", isOn: Binding(get: { food.isSaved }, set: { food.isSaved = $0 }))
                Button("Log it") {
                    onConfirm(servings)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .bold()
            }
            .navigationTitle("Log Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ManualFoodEntryView: View {
    let onCreated: (FoodItem) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var servingSize = "1"
    @State private var servingUnit = "serving"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Food name", text: $name)
                Section("Serving") {
                    HStack {
                        TextField("Size", text: $servingSize).keyboardType(.decimalPad)
                        TextField("Unit (g, slice, cup…)", text: $servingUnit)
                    }
                }
                Section("Nutrition per serving") {
                    row("Calories", "kcal", $calories)
                    row("Protein", "g", $protein)
                    row("Carbs", "g", $carbs)
                    row("Fat", "g", $fat)
                }
            }
            .navigationTitle("Manual Entry")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = FoodItem(
                            name: name, source: "manual",
                            servingSize: Double(servingSize) ?? 1, servingUnit: servingUnit,
                            calories: Double(calories) ?? 0, protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0, fat: Double(fat) ?? 0)
                        context.insert(item)
                        onCreated(item)
                        dismiss()
                    }
                    .disabled(name.isEmpty || Double(calories) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ unit: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
