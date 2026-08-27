import SwiftUI
import SwiftData
import Charts

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @Query(sort: \DiaryEntry.date) private var allEntries: [DiaryEntry]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var faithEntries: [FaithLogEntry]
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("faithTradition") private var faithTradition = ""
    @AppStorage("dailyInsightDate") private var insightDate = ""
    @AppStorage("dailyInsightText") private var insightText = ""
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @State private var loadingInsight = false
    @State private var insightError: String?
    @State private var showConsent = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showSources = false
    @State private var showingTour = false
    @AppStorage("tourVersionSeen") private var tourVersionSeen = 0
    @AppStorage("tourResumeIndex") private var tourResumeIndex = -1
    @StateObject private var router = TabRouter.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    caloriesHero
                    macroRow
                    recentlyEaten
                    weightCard
                    workoutCard
                    if !faithTradition.isEmpty { faithCard }
                    insightCard
                    if tourResumeIndex >= 0 {
                        continueTourCard
                    } else if tourVersionSeen < TourSlides.currentVersion {
                        tourCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showSources) {
                NavigationStack { SourcesView() }
            }
            .navigationDestination(isPresented: $router.presentCoach) {
                CoachView()
            }
            .sheet(isPresented: $showConsent) {
                AIConsentSheet { generateInsight() }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView { generateInsight() }
            }
            .fullScreenCover(isPresented: $showingTour) {
                TourView(startAt: max(tourResumeIndex, 0))
            }
            .onAppear { handleDeepLink(router.pendingDeepLink) }
            .onChange(of: router.pendingDeepLink) { _, link in handleDeepLink(link) }
        }
    }

    /// Consumes the "open Settings" tour deep link. Clears the intent immediately so
    /// it never re-fires on a later, unrelated visit to this tab.
    private func handleDeepLink(_ link: TourDeepLink?) {
        guard link == .settings else { return }
        router.pendingDeepLink = nil
        showSettings = true
    }

    // MARK: Feature tour

    private var tourCard: some View {
        Button {
            tourVersionSeen = TourSlides.currentVersion
            showingTour = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New here?")
                        .font(.subheadline.bold())
                    Text("Take a quick tour of what OnTrack can do.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                tourVersionSeen = TourSlides.currentVersion
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
    }

    private var continueTourCard: some View {
        Button {
            showingTour = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.forward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue the tour")
                        .font(.subheadline.bold())
                    Text("Pick up right where you left off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                tourResumeIndex = -1
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
    }

    // MARK: Nutrition data

    private var todayEntries: [DiaryEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var weightKg: Double { weights.first?.weightKg ?? 70 }

    private var calTarget: Double {
        profiles.first.map { Calculations.calorieTarget(profile: $0, weightKg: weightKg) } ?? 2000
    }

    private var macroTarget: (protein: Double, carbs: Double, fat: Double) {
        profiles.first.map { Calculations.macroTargets(profile: $0, weightKg: weightKg) } ?? (150, 250, 65)
    }

    private func fraction(_ eaten: Double, _ target: Double) -> Double {
        target > 0 ? min(eaten / target, 1) : 0
    }

    // MARK: Calories hero

    private var caloriesHero: some View {
        let consumed = todayEntries.reduce(0) { $0 + $1.calories }
        let left = calTarget - consumed
        let over = left < 0
        return Button { TabRouter.shared.selected = .diet } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(abs(left)))")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(over ? "Calories over" : "Calories left")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                ProgressRing(fraction: fraction(consumed, calTarget),
                             color: over ? .red : .accentColor, lineWidth: 10) {
                    Image(systemName: "flame.fill").font(.title2).foregroundStyle(.secondary)
                }
                .frame(width: 92, height: 92)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { showSources = true } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
    }

    // MARK: Macro rings

    private var macroRow: some View {
        let protein = todayEntries.reduce(0) { $0 + $1.protein }
        let carbs = todayEntries.reduce(0) { $0 + $1.carbs }
        let fat = todayEntries.reduce(0) { $0 + $1.fat }
        let t = macroTarget
        return HStack(spacing: 12) {
            MacroRingCard(title: "Protein left", left: t.protein - protein,
                          fraction: fraction(protein, t.protein), icon: "bolt.fill", color: .red)
            MacroRingCard(title: "Carbs left", left: t.carbs - carbs,
                          fraction: fraction(carbs, t.carbs), icon: "leaf.fill", color: .orange)
            MacroRingCard(title: "Fats left", left: t.fat - fat,
                          fraction: fraction(fat, t.fat), icon: "drop.fill", color: .blue)
        }
    }

    // MARK: Recently eaten

    private var recentlyEaten: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently eaten").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if todayEntries.isEmpty {
                Text("Nothing logged yet today. Tap + on the Diet tab to add a meal.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().card()
            } else {
                ForEach(Array(todayEntries.reversed())) { entry in
                    Button { TabRouter.shared.selected = .diet } label: {
                        RecentlyEatenRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Weight

    private var loggedWeightToday: Bool {
        weights.contains { Calendar.current.isDateInToday($0.date) }
    }

    private var weightCard: some View {
        Button { TabRouter.shared.selected = .weight } label: {
            HStack(spacing: 12) {
                Image(systemName: loggedWeightToday ? "checkmark.circle.fill" : "scalemass.fill")
                    .font(.title2)
                    .foregroundStyle(loggedWeightToday ? .green : .orange)
                if loggedWeightToday, let latest = weights.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weighed in today")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                        Text("\(Units.kgToDisplay(latest.weightKg, metric: useMetric), format: .number.precision(.fractionLength(1))) \(Units.weightLabel(metric: useMetric)) · \(latest.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    sparkline
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weigh yourself today")
                            .font(.subheadline.bold())
                        if let latest = weights.first {
                            Text("Last: \(Units.kgToDisplay(latest.weightKg, metric: useMetric), format: .number.precision(.fractionLength(1))) \(Units.weightLabel(metric: useMetric)) on \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Tap to log your first weigh-in")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var sparkline: some View {
        let recent = Array(weights.prefix(14)).reversed()
        return Chart(recent) { entry in
            LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightKg))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(width: 100, height: 40)
    }

    // MARK: Workout

    private var workoutCard: some View {
        Button { TabRouter.shared.selected = .workout } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let last = sessions.first(where: { !$0.isPlanned && $0.kind == "workout" && $0.date <= Date() }) {
                    let daysAgo = Calendar.current.dateComponents([.day], from: last.date, to: Date()).day ?? 0
                    Text(Calendar.current.isDateInToday(last.date)
                         ? "Trained today: \(last.templateName ?? "Freeform") ✓"
                         : "Last workout: \(last.templateName ?? "Freeform")")
                        .font(.subheadline.bold())
                    Text(daysAgo == 0 ? "Nice work." : "\(daysAgo) day\(daysAgo == 1 ? "" : "s") ago — tap to start one")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No workouts yet — tap to start").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: Faith

    private var fardPrayedToday: Int {
        faithEntries.filter {
            Calendar.current.isDateInToday($0.day) &&
            $0.itemKey.hasPrefix("fard.") &&
            ($0.status == "onTime" || $0.status == "late")
        }.count
    }

    private var faithCard: some View {
        let count = fardPrayedToday
        let complete = count == 5
        return Button { TabRouter.shared.selected = .faith } label: {
            HStack(spacing: 12) {
                Image(systemName: complete ? "checkmark.circle.fill" : "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(complete ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayers")
                        .font(.subheadline.bold())
                        .foregroundStyle(complete ? .green : .primary)
                    Text("\(count)/5 prayed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: AI insight (cached once per day)

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach").font(.headline)
            if loadingInsight {
                HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
            } else if isInsightFresh {
                Text(LocalizedStringKey(insightText))
                Text("AI-generated — not medical or nutritional advice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Ask the coach more") { router.presentCoach = true }
                    .font(.subheadline)
            } else {
                if let insightError {
                    Text(insightError).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    generateInsight()
                } label: {
                    Label("Get today's insight", systemImage: "lightbulb.fill")
                }
            }
            Button {
                router.presentCoach = true
            } label: {
                Label("Open Coach chat", systemImage: "brain.head.profile")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
    }

    private var isInsightFresh: Bool {
        insightDate == todayKey && !insightText.isEmpty
    }

    private var todayKey: String {
        Date().formatted(.iso8601.year().month().day())
    }

    private func generateInsight() {
        guard Pro.isActive else { showPaywall = true; return }
        guard aiConsentGiven else { showConsent = true; return }
        loadingInsight = true
        insightError = nil
        Task {
            guard let dataContext = await CoachContext.build(context: context) else {
                await MainActor.run {
                    loadingInsight = false
                    insightError = "Log a few meals, weigh-ins, or workouts first, then I can give you a real insight."
                }
                return
            }
            do {
                let text = try await AIClient.complete(messages: [
                    .init(role: "system", content: CoachContext.systemPrompt + "\n\nUser's recent data:\n" + dataContext),
                    .init(role: "user", content: "Give me a short daily insight (3-4 sentences max): how am I tracking against my goal, and the single most useful thing to focus on today?"),
                ])
                await MainActor.run {
                    insightText = text
                    insightDate = todayKey
                    loadingInsight = false
                }
            } catch {
                await MainActor.run {
                    insightError = error.localizedDescription
                    loadingInsight = false
                }
            }
        }
    }
}

// MARK: - Dashboard components

/// One logged-food row for the "Recently eaten" list.
private struct RecentlyEatenRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnail(imageFilename: entry.food?.imageFilename, source: entry.food?.source)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.food?.name ?? "Food").font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.secondary)
                    Text("\(Int(entry.calories)) cal").font(.subheadline)
                }
                HStack(spacing: 12) {
                    macroChip("bolt.fill", .red, entry.protein)
                    macroChip("leaf.fill", .orange, entry.carbs)
                    macroChip("drop.fill", .blue, entry.fat)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .card()
    }

    private func macroChip(_ icon: String, _ color: Color, _ grams: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text("\(Int(grams))g").font(.caption).foregroundStyle(.secondary)
        }
    }
}
