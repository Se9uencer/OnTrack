import SwiftUI
import SwiftData

struct ActiveSessionView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("restSeconds") private var restSeconds = 120
    @AppStorage("hasPrimedNotifications") private var hasPrimedNotifications = false
    @State private var restEndsAt: Date?
    @State private var showingPicker = false
    @State private var confirmingDiscard = false
    @State private var showingNotificationPrime = false
    @State private var now = Date()
    @State private var currentPage = 0

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)

            TabView(selection: $currentPage) {
                ForEach(Array(groupedExercises.enumerated()), id: \.element.0) { index, group in
                    ExercisePage(
                        exerciseID: group.0,
                        exerciseName: group.1,
                        sets: group.2,
                        useMetric: useMetric,
                        lastSets: lastSets(exerciseID: group.0),
                        onAddSet: { addSet(exerciseID: group.0, exerciseName: group.1) },
                        onRemoveSet: { removeLastSet(exerciseID: group.0) })
                    .tag(index)
                }
                addExercisePage
                    .tag(groupedExercises.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            restBar
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
        .tint(.blue)
        .keyboardDoneButton()
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { id, name in
                addSet(exerciseID: id, exerciseName: name)
                currentPage = max(0, groupedExercises.count - 1)
            }
        }
        .sheet(isPresented: $showingNotificationPrime) {
            PermissionPrimeSheet(
                icon: "bell.badge.fill",
                navTitle: "Notifications",
                title: "Get notified when rest is over?",
                message: "OnTrack can send a notification when your rest timer finishes, so you don't have to watch the clock."
            ) {
                Task { _ = await NotificationService.shared.requestPermission() }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) {
                context.delete(session)
                NotificationService.shared.cancelRestTimer()
                dismiss()
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.templateName ?? "Freeform")
                    .font(.system(size: 26, weight: .bold))
                Text(elapsedString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { confirmingDiscard = true } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.15), in: Circle())
            }
            Button { finish() } label: {
                Text("End Workout")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
        }
    }

    private var elapsedString: String {
        let s = max(0, Int(now.timeIntervalSince(session.date)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Add-exercise page

    private var addExercisePage: some View {
        VStack(spacing: 20) {
            Button { showingPicker = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 64)
                    .background(Color(.tertiarySystemBackground), in: Circle())
            }
            Text("Add an exercise")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .card()
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40)
    }

    // MARK: Rest timer bar

    private var restBar: some View {
        HStack(spacing: 14) {
            Button("Reset") { stopRest() }
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach([60, 90, 120, 180, 240], id: \.self) { secs in
                    Button("\(secs / 60):\(String(format: "%02d", secs % 60))") { restSeconds = secs }
                }
            } label: {
                Text(restDisplay)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Button {
                startRest()
            } label: {
                Text("Start")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .card(cornerRadius: 30)
    }

    private var restDisplay: String {
        if let endsAt = restEndsAt, endsAt > now {
            let s = Int(endsAt.timeIntervalSince(now))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return String(format: "%d:%02d", restSeconds / 60, restSeconds % 60)
    }

    // MARK: Data helpers

    private var groupedExercises: [(String, String, [LoggedSet])] {
        var result: [(String, String, [LoggedSet])] = []
        for set in session.orderedSets {
            if let idx = result.firstIndex(where: { $0.0 == set.exerciseID }) {
                result[idx].2.append(set)
            } else {
                result.append((set.exerciseID, set.exerciseName, [set]))
            }
        }
        return result
    }

    /// The ordered sets from the most recent PREVIOUS session that logged this exercise.
    /// Ghost hints index into this by set number (set 3 shows last time's set 3).
    /// All sets in a session share the same `date`, so that groups a session.
    private func lastSets(exerciseID: String) -> [LoggedSet] {
        let sessionDate = session.date
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate { $0.exerciseID == exerciseID && $0.weightKg > 0 && $0.date < sessionDate },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.order)])
        guard let all = try? context.fetch(descriptor), let lastDate = all.first?.date else { return [] }
        return all.filter { $0.date == lastDate }.sorted { $0.order < $1.order }
    }

    private func addSet(exerciseID: String, exerciseName: String) {
        let order = (session.orderedSets.last?.order ?? -1) + 1
        let set = LoggedSet(exerciseID: exerciseID, exerciseName: exerciseName,
                            weightKg: 0, reps: 0, order: order, date: session.date)
        session.sets = (session.sets ?? []) + [set]
    }

    private func removeLastSet(exerciseID: String) {
        guard let last = session.orderedSets.last(where: { $0.exerciseID == exerciseID }) else { return }
        session.sets = (session.sets ?? []).filter { $0 !== last }
        context.delete(last)
    }

    private func startRest() {
        restEndsAt = Date().addingTimeInterval(TimeInterval(restSeconds))
        NotificationService.shared.scheduleRestDone(seconds: TimeInterval(restSeconds))
        if !hasPrimedNotifications {
            hasPrimedNotifications = true
            showingNotificationPrime = true
        }
    }

    private func stopRest() {
        restEndsAt = nil
        NotificationService.shared.cancelRestTimer()
    }

    private func finish() {
        for set in (session.sets ?? []) where set.reps == 0 && set.weightKg == 0 {
            context.delete(set)
        }
        if (session.sets ?? []).isEmpty { context.delete(session) }
        NotificationService.shared.cancelRestTimer()
        dismiss()
    }
}

// MARK: - One exercise per page

struct ExercisePage: View {
    let exerciseID: String
    let exerciseName: String
    let sets: [LoggedSet]
    let useMetric: Bool
    let lastSets: [LoggedSet]
    let onAddSet: () -> Void
    let onRemoveSet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exerciseName)
                .font(.title3.bold())
                .lineLimit(2)

            if !muscles.isEmpty {
                HStack(spacing: 8) {
                    ForEach(muscles, id: \.self) { muscle in
                        Text(muscle.capitalized)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                        // Ghost = last time's SAME set number; no ghost past what was done last time.
                        SetPillRow(loggedSet: set, setNumber: index + 1,
                                   useMetric: useMetric,
                                   lastPerformance: index < lastSets.count ? lastSets[index] : nil)
                    }
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    onRemoveSet()
                } label: {
                    Text("Remove Set")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
                Button {
                    onAddSet()
                } label: {
                    Text("Add Set")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .card()
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40) // keep the card clear of the page dots
    }

    private var muscles: [String] {
        guard let ex = ExerciseDatabase.find(exerciseID) else { return [] }
        return Array(([ex.primaryMuscle] + (ex.primaryMuscles.dropFirst())).prefix(3))
    }
}

// MARK: - Set row: "1  [100 lbs] × [6 reps]"

struct SetPillRow: View {
    @Bindable var loggedSet: LoggedSet
    let setNumber: Int
    let useMetric: Bool
    let lastPerformance: LoggedSet?

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(spacing: 14) {
            Text("\(setNumber)")
                .font(.headline)
                .frame(width: 24)
            HStack(spacing: 6) {
                TextField(weightPlaceholder, text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .onChange(of: weightText) { commitWeight() }
                Text(Units.weightLabel(metric: useMetric))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground), in: Capsule())
            .frame(maxWidth: .infinity)
            Text("×").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(repsPlaceholder, text: $repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .onChange(of: repsText) { commitReps() }
                Text("reps")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.tertiarySystemBackground), in: Capsule())
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if loggedSet.weightKg > 0 {
                weightText = trimmed(Units.kgToDisplay(loggedSet.weightKg, metric: useMetric))
            }
            if loggedSet.reps > 0 { repsText = "\(loggedSet.reps)" }
        }
    }

    private var weightPlaceholder: String {
        guard let last = lastPerformance else { return "" }
        return trimmed(Units.kgToDisplay(last.weightKg, metric: useMetric))
    }
    private var repsPlaceholder: String {
        guard let last = lastPerformance else { return "" }
        return "\(last.reps)"
    }

    private func commitWeight() {
        if let w = Double(weightText) {
            loggedSet.weightKg = Units.displayToKg(w, metric: useMetric)
        } else if weightText.isEmpty {
            loggedSet.weightKg = 0
        }
    }

    private func commitReps() {
        loggedSet.reps = Int(repsText) ?? 0
    }

    private func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
