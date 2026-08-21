import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var activeSession: WorkoutSession?
    @State private var showingStartChooser = false

    private var cal: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    WeekStrip(selectedDay: $selectedDay, workoutDays: workoutDays)
                    dayCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                if !isPast {
                    Button(isToday ? "Start Workout" : "Plan Workout") { showingStartChooser = true }
                        .buttonStyle(PillButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingStartChooser) {
                DayPlanPickerView(day: selectedDay, isToday: isToday) { selection in
                    applySelection(selection)
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                ActiveSessionView(session: session)
            }
        }
    }

    private func applySelection(_ selection: DayPlanPickerView.Selection) {
        // One assignment per day: clear any existing plan/marker for this day first.
        for s in daySessions where s.isPlanned || s.kind != "workout" {
            context.delete(s)
        }
        switch selection {
        case .rest:
            setMarker(kind: "rest", name: "Rest")
        case .activities:
            setMarker(kind: "activity", name: "Activities")
        case .template(let id):
            guard let template = templates.first(where: { $0.persistentModelID == id }) else { return }
            if isToday { startSession(template: template) } else { planSession(template: template) }
        }
    }

    private func setMarker(kind: String, name: String) {
        let date = isToday ? Date() : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay) ?? selectedDay)
        let session = WorkoutSession(date: date, templateName: name, isPlanned: isFuture, kind: kind)
        context.insert(session)
    }

    // MARK: Day classification

    private var today: Date { cal.startOfDay(for: Date()) }
    private var isToday: Bool { cal.isDate(selectedDay, inSameDayAs: today) }
    private var isPast: Bool { selectedDay < today }
    private var isFuture: Bool { selectedDay > today }

    private func chooseTemplate(_ template: WorkoutTemplate) {
        if isToday {
            startSession(template: template)
        } else if isFuture {
            planSession(template: template)
        }
    }

    // MARK: Header — selected day's workout name + date, "Workouts" pill on the right

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(daySessions.first?.templateName ?? (daySessions.isEmpty ? "Freestyle" : "Freeform"))
                    .font(.system(size: 34, weight: .bold))
                Text(selectedDay.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                WorkoutsListView()
            } label: {
                Text("Workouts")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: Day card — the selected day's sessions, or the empty "+" state

    private var daySessions: [WorkoutSession] {
        sessions.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private var workoutDays: Set<Date> {
        Set(sessions.map { cal.startOfDay(for: $0.date) })
    }

    @ViewBuilder
    private var dayCard: some View {
        if daySessions.isEmpty {
            emptyDayCard
        } else {
            VStack(spacing: 12) {
                ForEach(daySessions) { session in
                    if session.kind != "workout" {
                        markerCard(session)
                    } else if session.isPlanned {
                        plannedCard(session)
                    } else {
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionSummary(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyDayCard: some View {
        if isPast {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("No workout logged this day.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 380)
            .card()
        } else {
            VStack(spacing: 20) {
                Button { showingStartChooser = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 76, height: 76)
                        .background(Color(.tertiarySystemBackground), in: Circle())
                }
                Text(isToday ? "Tap + to start a workout." : "Tap + to plan a workout for this day.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 380)
            .card()
        }
    }

    // Rest / Activities marker for a day.
    private func markerCard(_ session: WorkoutSession) -> some View {
        VStack(spacing: 14) {
            Image(systemName: session.kind == "rest" ? "moon.fill" : "figure.walk")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text(session.templateName ?? (session.kind == "rest" ? "Rest" : "Activities"))
                .font(.title2.bold())
            Button(role: .destructive) {
                context.delete(session)
            } label: {
                Label("Remove", systemImage: "trash").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .card()
    }

    // Planned workout: preview of exercises. Startable only once the day arrives.
    private func plannedCard(_ session: WorkoutSession) -> some View {
        let exerciseNames = session.orderedSets.reduce(into: [String]()) { acc, s in
            if !acc.contains(s.exerciseName) { acc.append(s.exerciseName) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.templateName ?? "Planned").font(.title3.bold())
                Spacer()
                Text("Planned")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            Text(exerciseNames.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isToday {
                Button("Start This Workout") { startPlanned(session) }
                    .buttonStyle(PillButtonStyle())
            }
            HStack {
                Button(role: .destructive) {
                    context.delete(session)
                } label: {
                    Label("Remove plan", systemImage: "trash")
                        .font(.subheadline)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sessionSummary(_ session: WorkoutSession) -> some View {
        let sets = session.orderedSets
        let exerciseNames = sets.reduce(into: [String]()) { acc, s in
            if !acc.contains(s.exerciseName) { acc.append(s.exerciseName) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.templateName ?? "Freeform").font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            Text("\(sets.count) sets · \(exerciseNames.count) exercises")
                .foregroundStyle(.secondary)
            Text(exerciseNames.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func startSession(template: WorkoutTemplate?) {
        let session = WorkoutSession(date: Date(), templateName: template?.name)
        context.insert(session)
        if let template { prefillSets(session, from: template) }
        selectedDay = today
        activeSession = session
    }

    // Future day: create a planned session (not live), no ActiveSessionView.
    private func planSession(template: WorkoutTemplate) {
        // Anchor the date at noon of the planned day so day-grouping is unambiguous.
        let day = cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        let session = WorkoutSession(date: day, templateName: template.name, isPlanned: true)
        context.insert(session)
        prefillSets(session, from: template)
    }

    // Planned day has arrived: begin the planned session live.
    private func startPlanned(_ session: WorkoutSession) {
        session.isPlanned = false
        session.date = Date()
        for set in session.sets ?? [] { set.date = session.date }
        activeSession = session
    }

    private func prefillSets(_ session: WorkoutSession, from template: WorkoutTemplate) {
        var order = 0
        for te in template.orderedExercises {
            for _ in 0..<te.targetSets {
                let set = LoggedSet(exerciseID: te.exerciseID, exerciseName: te.exerciseName,
                                    weightKg: 0, reps: 0, order: order, date: session.date)
                session.sets = (session.sets ?? []) + [set]
                order += 1
            }
        }
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    @Binding var selectedDay: Date
    let workoutDays: Set<Date>

    private var cal: Calendar { Calendar.current }

    // The strip always shows the week containing the selected day.
    private var weekDays: [Date] {
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDay))!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    // Allow planning up to 2 weeks ahead of the current week.
    private var atForwardLimit: Bool {
        guard let twoWeeksOut = cal.date(byAdding: .weekOfYear, value: 2, to: Date()) else { return true }
        return cal.compare(selectedDay, to: twoWeeksOut, toGranularity: .weekOfYear) != .orderedAscending
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { shiftWeek(-1) } label: {
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
            }
            ForEach(weekDays, id: \.self) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
            Button { shiftWeek(1) } label: {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .disabled(atForwardLimit)
            .opacity(atForwardLimit ? 0.3 : 1)
        }
    }

    private func shiftWeek(_ delta: Int) {
        withAnimation {
            selectedDay = cal.date(byAdding: .weekOfYear, value: delta, to: selectedDay)!
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let hasWorkout = workoutDays.contains(cal.startOfDay(for: day))
        return Button {
            selectedDay = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 6) {
                Text(day.formatted(.dateTime.day()))
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: Circle())
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(hasWorkout ? Color.accentColor : .clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workouts (templates) list

struct WorkoutsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var showingBuilder = false
    @State private var editingTemplate: WorkoutTemplate?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if templates.isEmpty {
                    Text("No workouts yet — create your first split.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
                ForEach(templates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).font(.title3.bold())
                                Text(template.orderedExercises.map(\.exerciseName).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(template)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Create Workout") { showingBuilder = true }
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .sheet(isPresented: $showingBuilder) {
            TemplateBuilderView()
        }
        .sheet(item: $editingTemplate) { template in
            TemplateBuilderView(template: template)
        }
    }
}

// MARK: - Session detail (history)

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            ForEach(groupedByExercise, id: \.0) { name, sets in
                Section(name) {
                    ForEach(sets) { set in
                        SetRowDisplay(set: set)
                    }
                }
            }
        }
        .navigationTitle(session.templateName ?? "Freeform")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                context.delete(session) // cascade removes its logged sets
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the workout and all its logged sets.")
        }
    }

    private var groupedByExercise: [(String, [LoggedSet])] {
        var result: [(String, [LoggedSet])] = []
        for set in session.orderedSets {
            if let idx = result.firstIndex(where: { $0.0 == set.exerciseName }) {
                result[idx].1.append(set)
            } else {
                result.append((set.exerciseName, [set]))
            }
        }
        return result
    }
}

struct SetRowDisplay: View {
    let set: LoggedSet
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        HStack {
            Text("\(Units.kgToDisplay(set.weightKg, metric: useMetric), format: .number.precision(.fractionLength(0...1))) \(Units.weightLabel(metric: useMetric))")
            Spacer()
            Text("\(set.reps) reps").foregroundStyle(.secondary)
        }
    }
}
