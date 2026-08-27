import SwiftUI

/// Interactive, skippable: tapping a sample split populates a preview day card,
/// mirroring how picking a day on the real Workout tab works. All illustrative —
/// no WorkoutTemplate is created.
struct StartWorkoutDemoStep: View {
    @State private var selected: String?

    private let splits: [(name: String, exercises: [String])] = [
        ("Push Day", ["Bench Press", "Overhead Press", "Tricep Pushdown"]),
        ("Pull Day", ["Deadlift", "Barbell Row", "Bicep Curl"]),
        ("Leg Day", ["Squat", "Romanian Deadlift", "Leg Press"]),
    ]

    var body: some View {
        StepScaffold(
            title: "Start a workout",
            subtitle: "Build a split once, then log sets and rest timers as you train. Tap a day to see it come together."
        ) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(splits, id: \.name) { split in
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selected = split.name
                            }
                        } label: {
                            Text(split.name)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(selected == split.name ? Color.accentColor : Color(.secondarySystemBackground),
                                            in: Capsule())
                                .foregroundStyle(selected == split.name ? .white : .primary)
                        }
                    }
                }
                dayCard
            }
        }
    }

    @ViewBuilder
    private var dayCard: some View {
        if let name = selected, let split = splits.first(where: { $0.name == name }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(split.name).font(.system(size: 22, weight: .bold))
                ForEach(split.exercises, id: \.self) { exercise in
                    HStack {
                        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                        Text(exercise).font(.subheadline)
                        Spacer()
                        Text("3 sets").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "dumbbell.fill").font(.title).foregroundStyle(.secondary)
                Text("Pick a day above to preview it").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .card()
        }
    }
}
