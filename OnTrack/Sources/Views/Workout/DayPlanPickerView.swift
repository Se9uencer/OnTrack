import SwiftUI
import SwiftData

struct DayPlanPickerView: View {
    let day: Date
    let isToday: Bool
    /// Called with the chosen selection when the user confirms.
    let onConfirm: (Selection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    @State private var selection: Selection?
    @State private var showingBuilder = false

    enum Selection: Equatable {
        case rest
        case activities
        case template(PersistentIdentifier)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("Presets") {
                        row(title: "Rest", icon: "moon.fill", value: .rest)
                        row(title: "Activities", icon: "figure.walk", value: .activities)
                    }
                    section("Your Workouts") {
                        if templates.isEmpty {
                            Text("No workouts yet — tap + to create one.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                        ForEach(templates) { template in
                            row(title: template.name, icon: nil, value: .template(template.persistentModelID))
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                Button(isToday ? "Start Selection" : "Set for This Day") {
                    if let selection { onConfirm(selection); dismiss() }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(selection == nil)
                .opacity(selection == nil ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(day.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.title3.bold())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingBuilder = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                TemplateBuilderView()
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            content()
        }
    }

    private func row(title: String, icon: String?, value: Selection) -> some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(width: 26)
                }
                Text(title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selection == value ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(selection == value ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .card()
        }
        .buttonStyle(.plain)
    }
}
