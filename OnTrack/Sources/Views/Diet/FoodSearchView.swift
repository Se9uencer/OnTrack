import SwiftUI
import SwiftData

struct FoodSearchView: View {
    /// A screen to jump straight into on appear — how the feature tour's "Try it"
    /// reaches past this view's own sheet into the scanner or photo capture.
    enum InitialAction {
        case scanner
        case photoMeal
    }

    let meal: String
    let day: Date
    var initialAction: InitialAction? = nil
    var onLogged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FoodItem> { $0.isSaved }, sort: \FoodItem.name) private var savedFoods: [FoodItem]
    @Query(sort: \DiaryEntry.date, order: .reverse) private var recentEntriesDesc: [DiaryEntry]

    @State private var query = ""
    @State private var onlineResults: [FoodSearchResult] = []
    @State private var hasSearchedOnline = false
    @State private var searchingOnline = false
    @State private var onlineSearchFailed = false
    @State private var showingScanner = false
    @State private var showingPhotoMeal = false
    @State private var showingManualEntry = false
    @State private var pendingFood: FoodItem?
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @AppStorage("aiFoodEstimateDay") private var aiEstimateDay = ""
    @AppStorage("aiFoodEstimateCount") private var aiEstimateCount = 0
    @State private var showingAIConsent = false
    @State private var estimatingAI = false
    @State private var aiEstimateError: String?
    @State private var aiPrefill: AIClient.MealEstimate?
    @State private var showingAIPrefillEntry = false

    private static let dailyAILimit = 10
    private var aiEstimatesLeftToday: Int {
        let today = Self.todayKey()
        return aiEstimateDay == today ? max(0, Self.dailyAILimit - aiEstimateCount) : Self.dailyAILimit
    }
    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // Bundled search is in-memory and indexed — instant on every keystroke, no debounce needed.
    private var localResults: [BundledFood] {
        FoodDatabase.search(query)
    }

    /// Distinct foods logged in the last 14 days, most-recent first — a daily tracker's
    /// highest-value shortcut, since most people eat the same rotation of ~30 foods.
    private var recents: [DiaryEntry] {
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        var seen = Set<PersistentIdentifier>()
        var out: [DiaryEntry] = []
        for entry in recentEntriesDesc {
            guard entry.date >= cutoff, let food = entry.food else { continue }
            guard seen.insert(food.persistentModelID).inserted else { continue }
            out.append(entry)
            if out.count == 8 { break }
        }
        return out
    }

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

                if query.isEmpty {
                    if !recents.isEmpty {
                        Section("Recents") {
                            ForEach(recents) { entry in
                                Button { relog(entry) } label: { recentRow(entry) }
                            }
                        }
                    }
                    if !savedFoods.isEmpty {
                        Section("Saved foods") {
                            ForEach(savedFoods) { food in
                                Button { pendingFood = food } label: { savedRow(food) }
                            }
                        }
                    }
                    ForEach(FoodDatabase.groupedAlphabetically, id: \.letter) { group in
                        Section(group.letter) {
                            ForEach(group.foods) { bundled in
                                Button {
                                    pendingFood = FoodStore.findOrCreate(bundled.toSearchResult(), in: context)
                                } label: {
                                    localResultRow(bundled)
                                }
                            }
                        }
                    }
                } else {
                    if !localResults.isEmpty {
                        Section("Results") {
                            ForEach(localResults) { bundled in
                                Button {
                                    pendingFood = FoodStore.findOrCreate(bundled.toSearchResult(), in: context)
                                } label: {
                                    localResultRow(bundled)
                                }
                            }
                        }
                    }

                    Section {
                        if !hasSearchedOnline {
                            Button {
                                runOnlineSearch()
                            } label: {
                                Label("Search branded foods online", systemImage: "network")
                            }
                        } else if searchingOnline {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if !onlineResults.isEmpty {
                            ForEach(onlineResults) { result in
                                Button {
                                    pendingFood = FoodStore.findOrCreate(result, in: context)
                                } label: {
                                    onlineResultRow(result)
                                }
                            }
                        }
                    }

                    if hasSearchedOnline, !searchingOnline, localResults.isEmpty, onlineResults.isEmpty {
                        Section {
                            if onlineSearchFailed {
                                Text("Search failed — check your connection.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No matches for \"\(query)\".")
                                    .foregroundStyle(.secondary)
                            }
                            if estimatingAI {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else if aiEstimatesLeftToday > 0 {
                                Button { estimateWithAI() } label: {
                                    Label("Estimate with AI", systemImage: "sparkles")
                                }
                            } else {
                                Text("Daily AI estimate limit reached — you can still create this food manually.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let aiEstimateError {
                                Text(aiEstimateError).font(.caption).foregroundStyle(.red)
                            }
                            Button { showingManualEntry = true } label: {
                                Label("Create food manually", systemImage: "square.and.pencil")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .onChange(of: query) { hasSearchedOnline = false; onlineResults = []; onlineSearchFailed = false }
            .task {
                switch initialAction {
                case .scanner: showingScanner = true
                case .photoMeal: showingPhotoMeal = true
                case nil: break
                }
            }
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
            .sheet(isPresented: $showingAIConsent) {
                AIConsentSheet { estimateWithAI() }
            }
            .sheet(isPresented: $showingAIPrefillEntry) {
                ManualFoodEntryView(prefill: aiPrefill, prefillSource: "ai") { item in
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
                ServingsPickerView(food: food) { grams, portionLabel, servings in
                    logEntry(food: food, servings: servings, grams: grams, portionLabel: portionLabel)
                }
            }
        }
    }

    private func savedRow(_ food: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(food.name).foregroundStyle(.primary)
                    if food.source == "ai" {
                        Text("Estimated").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
                Text("\(Int(food.calories)) kcal / \(food.servingSize.formatted()) \(food.servingUnit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
        }
    }

    private func recentRow(_ entry: DiaryEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.food?.name ?? "").foregroundStyle(.primary)
                Text([entry.portionLabel.isEmpty ? nil : entry.portionLabel,
                      "\(Int(entry.calories)) kcal"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.clockwise").foregroundStyle(.secondary).font(.caption)
        }
    }

    private func localResultRow(_ bundled: BundledFood) -> some View {
        VStack(alignment: .leading) {
            Text(bundled.n).foregroundStyle(.primary)
            Text("\(Int(bundled.kcal)) kcal / 100 g")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func onlineResultRow(_ r: FoodSearchResult) -> some View {
        VStack(alignment: .leading) {
            Text(r.name).foregroundStyle(.primary)
            Text([r.brand, "\(Int(r.calories)) kcal / \(String(format: "%.0f", r.servingSize))\(r.servingUnit)"]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runOnlineSearch() {
        guard !query.isEmpty else { return }
        hasSearchedOnline = true
        searchingOnline = true
        onlineSearchFailed = false
        onlineResults = []
        Task {
            let hits = await FoodSearchService.search(query)
            await MainActor.run {
                onlineResults = hits
                searchingOnline = false
                onlineSearchFailed = hits.isEmpty
            }
        }
    }

    private func estimateWithAI() {
        guard !query.isEmpty else { return }
        guard aiConsentGiven else { showingAIConsent = true; return }
        let today = Self.todayKey()
        if aiEstimateDay != today { aiEstimateDay = today; aiEstimateCount = 0 }
        guard aiEstimateCount < Self.dailyAILimit else { return }
        estimatingAI = true
        aiEstimateError = nil
        Task {
            do {
                let estimate = try await AIClient.estimateFood(name: query)
                await MainActor.run {
                    aiEstimateCount += 1
                    estimatingAI = false
                    aiPrefill = estimate
                    showingAIPrefillEntry = true
                }
            } catch {
                await MainActor.run {
                    estimatingAI = false
                    aiEstimateError = error.localizedDescription
                }
            }
        }
    }

    private func lookupBarcode(_ barcode: String) async {
        searchingOnline = true
        let result = try? await FoodSearchService.lookupBarcode(barcode)
        await MainActor.run {
            searchingOnline = false
            if let result {
                pendingFood = FoodStore.findOrCreate(result, in: context)
            } else {
                onlineSearchFailed = true
            }
        }
    }

    /// One-tap re-log: reuses the exact portion from the last time this food was logged,
    /// no picker round-trip.
    private func relog(_ entry: DiaryEntry) {
        guard let food = entry.food else { return }
        logEntry(food: food, servings: entry.numberOfServings, grams: entry.grams, portionLabel: entry.portionLabel)
    }

    private func logEntry(food: FoodItem, servings: Double, grams: Double, portionLabel: String) {
        // Log against the selected day at the current time.
        let cal = Calendar.current
        let timeParts = cal.dateComponents([.hour, .minute], from: Date())
        let date = cal.date(bySettingHour: timeParts.hour ?? 12, minute: timeParts.minute ?? 0, second: 0, of: day) ?? day
        context.insert(DiaryEntry(date: date, meal: meal, food: food, numberOfServings: servings,
                                   grams: grams, portionLabel: portionLabel))
        onLogged()
        dismiss()
    }
}

private let dailyValues: [String: Double] = [
    "satFat": 20, "chol": 300, "sodium": 2300, "fiber": 28,
    "vitA": 900, "vitC": 90, "calcium": 1300, "iron": 18, "potassium": 4700,
]

/// One selectable measurement unit in the amount picker: how many "servings" (in the
/// FoodItem's own per-serving macro basis) one unit of this represents, plus its gram
/// weight when known (grams-per-unit is nil for units where a real weight isn't defined,
/// e.g. a manual entry's "slice" — the app never invents a conversion it doesn't have).
private struct AmountUnit: Identifiable, Hashable {
    let id: String
    let label: String
    let servingsPerUnit: Double
    let gramsPerUnit: Double?
}

struct ServingsPickerView: View {
    @Bindable var food: FoodItem
    /// (grams actually logged — 0 if unknown, display label for that portion, numberOfServings for DiaryEntry)
    let onConfirm: (Double, String, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUnitID: String
    @State private var amountValue: Double = 1.0
    @State private var amountText = "1"
    @State private var showFDA = false

    private let bundled: BundledFood?
    private let unitOptions: [AmountUnit]

    init(food: FoodItem, onConfirm: @escaping (Double, String, Double) -> Void) {
        self.food = food
        self.onConfirm = onConfirm
        let bundled = food.fdcId.flatMap(FoodDatabase.find)
        self.bundled = bundled

        var options: [AmountUnit] = [AmountUnit(id: "servings", label: "Servings", servingsPerUnit: 1,
                                                  gramsPerUnit: food.servingSize > 0 && food.servingUnit.lowercased() == "g" ? food.servingSize : nil)]
        if let bundled {
            // food.servingSize is always 100 (grams) for bundled foods, so grams-per-unit
            // divided by that base is exactly servings-per-unit.
            options.append(AmountUnit(id: "grams", label: "Grams", servingsPerUnit: 1 / 100, gramsPerUnit: 1))
            for portion in bundled.portions where portion.label != "100 g" {
                options.append(AmountUnit(id: portion.label, label: portion.label,
                                           servingsPerUnit: portion.grams / 100, gramsPerUnit: portion.grams))
            }
        } else if food.servingUnit.lowercased() != "serving" && food.servingUnit.lowercased() != "servings" {
            // e.g. OFF/manual foods logged as "100 g" or "1 slice" — offer that unit directly
            // alongside the generic "Servings" option above.
            options.append(AmountUnit(id: "native", label: food.servingUnit, servingsPerUnit: 1,
                                       gramsPerUnit: food.servingUnit.lowercased() == "g" ? food.servingSize : nil))
        }
        self.unitOptions = options
        // Default to the food's most natural unit: a named portion for bundled foods, else Servings.
        _selectedUnitID = State(initialValue: bundled?.portions.first(where: { $0.label != "100 g" })?.label ?? "servings")
    }

    private var selectedUnit: AmountUnit {
        unitOptions.first { $0.id == selectedUnitID } ?? unitOptions[0]
    }

    private var amount: Double { amountValue }
    private var numberOfServings: Double { amount * selectedUnit.servingsPerUnit }
    private var grams: Double { selectedUnit.gramsPerUnit.map { amount * $0 } ?? 0 }

    /// Grams needs a much wider range/coarser step than a serving-style count (nobody
    /// drags a slider from 0.1 to 500 one-tenth at a time).
    private var sliderRange: ClosedRange<Double> { selectedUnit.id == "grams" ? 1...500 : 0.1...5 }
    private var sliderStep: Double { selectedUnit.id == "grams" ? 1 : 0.1 }
    private var sliderFractionDigits: ClosedRange<Int> { selectedUnit.id == "grams" ? 0...0 : 0...2 }

    private var portionLabel: String {
        let unitLabel = selectedUnit.label
        return amount == 1 ? unitLabel : "\(amountText) \u{d7} \(unitLabel)"
    }

    private var scaledCalories: Double { food.calories * numberOfServings }
    private var scaledProtein: Double { food.protein * numberOfServings }
    private var scaledCarbs: Double { food.carbs * numberOfServings }
    private var scaledFat: Double { food.fat * numberOfServings }

    var body: some View {
        NavigationStack {
            Form {
                Section(food.name) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("1", text: $amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                                .onChange(of: amountText) { _, new in
                                    if let v = Double(new), v > 0 { amountValue = v }
                                }
                            Picker("", selection: $selectedUnitID) {
                                ForEach(unitOptions) { unit in
                                    Text(unit.label).tag(unit.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        Slider(value: $amountValue, in: sliderRange, step: sliderStep)
                            .onChange(of: amountValue) { _, new in
                                amountText = new.formatted(.number.precision(.fractionLength(sliderFractionDigits)))
                            }
                    }
                    .onChange(of: selectedUnitID) {
                        // A raw number means something different in each unit (150 "Grams"
                        // vs 150 "Servings" is nonsense) — reset to a sane default on switch.
                        amountValue = 1
                        amountText = "1"
                    }
                    if grams > 0 {
                        LabeledContent("Weight", value: "\(Int(grams)) g")
                    }
                    LabeledContent("Calories", value: "\(Int(scaledCalories)) kcal")
                    LabeledContent("Protein", value: "\(Int(scaledProtein)) g")
                    LabeledContent("Carbs", value: "\(Int(scaledCarbs)) g")
                    LabeledContent("Fat", value: "\(Int(scaledFat)) g")
                }

                Section {
                    MacroSplitBar(protein: scaledProtein, carbs: scaledCarbs, fat: scaledFat)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                }

                if let bundled {
                    DisclosureGroup("Nutrition facts", isExpanded: $showFDA) {
                        nutritionPanel(bundled)
                    }
                }

                Toggle("Save to my foods", isOn: Binding(get: { food.isSaved }, set: { food.isSaved = $0 }))

                Button("Log it") {
                    onConfirm(grams, portionLabel, numberOfServings)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .bold()
            }
            .navigationTitle("Log Food")
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func nutritionPanel(_ bundled: BundledFood) -> some View {
        // bundled values are per-100g and food.servingSize is always 100 for bundled foods,
        // so numberOfServings is exactly the right scale factor here too.
        nutrientRow("Saturated Fat", bundled.satFat, "g", dvKey: "satFat")
        nutrientRow("Trans Fat", bundled.transFat, "g", dvKey: nil)
        nutrientRow("Cholesterol", bundled.chol, "mg", dvKey: "chol")
        nutrientRow("Sodium", bundled.sodium, "mg", dvKey: "sodium")
        nutrientRow("Dietary Fiber", bundled.fiber, "g", dvKey: "fiber")
        nutrientRow("Total Sugars", bundled.sugar, "g", dvKey: nil)
        nutrientRow("Vitamin A", bundled.vitA, "\u{b5}g", dvKey: "vitA")
        nutrientRow("Vitamin C", bundled.vitC, "mg", dvKey: "vitC")
        nutrientRow("Calcium", bundled.calcium, "mg", dvKey: "calcium")
        nutrientRow("Iron", bundled.iron, "mg", dvKey: "iron")
        nutrientRow("Potassium", bundled.potassium, "mg", dvKey: "potassium")
        Text("* Percent Daily Values are based on a 2,000 calorie diet.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func nutrientRow(_ label: String, _ per100g: Double?, _ unit: String, dvKey: String?) -> some View {
        if let per100g {
            let amount = per100g * numberOfServings
            HStack {
                Text(label)
                Spacer()
                Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                    .foregroundStyle(.secondary)
                if let dvKey, let reference = dailyValues[dvKey], reference > 0 {
                    Text("\(Int((amount / reference) * 100))%")
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Carb/fat/protein kcal split, matching the teal/orange/yellow bar in Samsung Health-style
/// nutrition screens.
struct MacroSplitBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private var proteinKcal: Double { protein * 4 }
    private var carbKcal: Double { carbs * 4 }
    private var fatKcal: Double { fat * 9 }
    private var total: Double { max(proteinKcal + carbKcal + fatKcal, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                legend("Carb", .teal, carbKcal)
                legend("Fat", .orange, fatKcal)
                legend("Protein", .yellow, proteinKcal)
            }
            .font(.caption)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Color.teal.frame(width: geo.size.width * carbKcal / total)
                    Color.orange.frame(width: geo.size.width * fatKcal / total)
                    Color.yellow.frame(width: geo.size.width * proteinKcal / total)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }

    private func legend(_ label: String, _ color: Color, _ kcal: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int((kcal / total) * 100))%").foregroundStyle(.secondary)
        }
    }
}

struct ManualFoodEntryView: View {
    let onCreated: (FoodItem) -> Void
    /// When set, the form opens pre-filled (e.g. from an AI estimate) but stays fully
    /// editable — the user reviews and corrects before it's ever saved.
    var prefillSource: String = "manual"
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var servingSize: String
    @State private var servingUnit: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String

    init(prefill: AIClient.MealEstimate? = nil, prefillSource: String = "manual",
         onCreated: @escaping (FoodItem) -> Void) {
        self.onCreated = onCreated
        self.prefillSource = prefillSource
        _name = State(initialValue: prefill?.name ?? "")
        _servingSize = State(initialValue: "1")
        _servingUnit = State(initialValue: "serving")
        _calories = State(initialValue: prefill.map { String(format: "%.0f", $0.calories) } ?? "")
        _protein = State(initialValue: prefill.map { String(format: "%.1f", $0.protein_g) } ?? "")
        _carbs = State(initialValue: prefill.map { String(format: "%.1f", $0.carbs_g) } ?? "")
        _fat = State(initialValue: prefill.map { String(format: "%.1f", $0.fat_g) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if prefillSource == "ai" {
                    Label("AI estimate — check the numbers before saving.", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                            name: name, source: prefillSource,
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
