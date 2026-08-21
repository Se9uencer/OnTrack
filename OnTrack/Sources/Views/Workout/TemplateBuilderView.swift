import SwiftUI
import SwiftData

struct TemplateBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new split; non-nil = editing an existing one.
    var template: WorkoutTemplate?

    @State private var name = ""
    @State private var picked: [PickedExercise] = []
    @State private var showingPicker = false
    @State private var swapIndex: Int?   // set when the picker is swapping a row, not adding
    @State private var loaded = false

    struct PickedExercise: Identifiable {
        let id = UUID()
        var exerciseID: String
        var name: String
        var sets: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Split name (e.g. Push Day A)", text: $name)
                Section {
                    ForEach($picked) { $item in
                        HStack {
                            Button {
                                swapIndex = picked.firstIndex { $0.id == item.id }
                                showingPicker = true
                            } label: {
                                Text(item.name).foregroundStyle(.primary)
                            }
                            Spacer()
                            Stepper("\(item.sets) sets", value: $item.sets, in: 1...10)
                                .fixedSize()
                        }
                    }
                    .onDelete { picked.remove(atOffsets: $0) }
                    .onMove { picked.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        swapIndex = nil
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Tap an exercise to swap it. Drag to reorder, swipe to delete.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(template == nil ? "New Split" : "Edit Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || picked.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { id, exerciseName in
                    if let i = swapIndex {
                        picked[i].exerciseID = id      // keep position + set count, swap the movement
                        picked[i].name = exerciseName
                    } else {
                        picked.append(PickedExercise(exerciseID: id, name: exerciseName, sets: 3))
                    }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let template else { loaded = true; return }
        name = template.name
        picked = template.orderedExercises.map {
            PickedExercise(exerciseID: $0.exerciseID, name: $0.exerciseName, sets: $0.targetSets)
        }
        loaded = true
    }

    private func save() {
        let target = template ?? {
            let t = WorkoutTemplate(name: name)
            context.insert(t)
            return t
        }()
        target.name = name
        // Replace the exercise list wholesale (cascade-deletes the old rows).
        for old in target.exercises ?? [] { context.delete(old) }
        target.exercises = picked.enumerated().map { i, p in
            TemplateExercise(exerciseID: p.exerciseID, exerciseName: p.name, targetSets: p.sets, order: i)
        }
        dismiss()
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var customExercises: [CustomExercise]
    @State private var query = ""
    @State private var showingNewCustom = false
    @State private var customName = ""
    @State private var customMuscle = ""
    let onPick: (String, String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showingNewCustom = true
                } label: {
                    Label("Create custom exercise", systemImage: "plus")
                }
                if !filteredCustom.isEmpty {
                    Section("My exercises") {
                        ForEach(filteredCustom) { ex in
                            Button {
                                onPick(ex.id, ex.name)
                                dismiss()
                            } label: {
                                exerciseRow(name: ex.name, detail: ex.primaryMuscle)
                            }
                        }
                    }
                }
                Section("Exercises") {
                    ForEach(filteredBundled) { ex in
                        Button {
                            onPick(ex.id, ex.name)
                            dismiss()
                        } label: {
                            exerciseRow(name: ex.name, detail: "\(ex.primaryMuscle) · \(ex.equipment ?? "")")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Pick Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Custom exercise", isPresented: $showingNewCustom) {
                TextField("Name", text: $customName)
                TextField("Muscle group", text: $customMuscle)
                Button("Add") {
                    let ex = CustomExercise(name: customName, primaryMuscle: customMuscle, equipment: "")
                    context.insert(ex)
                    onPick(ex.id, ex.name)
                    customName = ""; customMuscle = ""
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func exerciseRow(name: String, detail: String) -> some View {
        VStack(alignment: .leading) {
            Text(name).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filteredBundled: [BundledExercise] {
        Array(ExerciseDatabase.search(query).prefix(50))
    }
    private var filteredCustom: [CustomExercise] {
        query.isEmpty ? customExercises
            : customExercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
