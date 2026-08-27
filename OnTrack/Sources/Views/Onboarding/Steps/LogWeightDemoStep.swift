import SwiftUI
import Charts

/// Interactive, skippable: tapping "Log today's weigh-in" drops one more point onto
/// an illustrative trend line. Fires no system prompt — HealthKit is primed on the
/// real Weight tab, not here.
struct LogWeightDemoStep: View {
    @AppStorage("useMetric") private var useMetric = false
    @State private var logged = false

    // Illustrative sample trend, not the user's real data.
    private let historyKg: [(day: Int, kg: Double)] = [
        (0, 82.5), (1, 82.3), (2, 82.4), (3, 82.0), (4, 81.8), (5, 81.9),
    ]
    private let newPointKg = 81.5

    private var points: [(day: Int, kg: Double)] {
        logged ? historyKg + [(day: 6, kg: newPointKg)] : historyKg
    }

    private func displayWeight(_ kg: Double) -> String {
        let value = Units.kgToDisplay(kg, metric: useMetric)
            .formatted(.number.precision(.fractionLength(1)))
        return "\(value) \(Units.weightLabel(metric: useMetric))"
    }

    var body: some View {
        StepScaffold(
            title: "Log your weight",
            subtitle: "Track the trend, sync with Apple Health, and attach a progress photo to any weigh-in. Tap to add today's."
        ) {
            VStack(spacing: 16) {
                Chart(points, id: \.day) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Weight", point.kg))
                        .interpolationMethod(.monotone)
                    if point.day == points.last?.day {
                        PointMark(x: .value("Day", point.day), y: .value("Weight", point.kg))
                            .foregroundStyle(logged ? .green : Color.accentColor)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
                .padding()
                .card()

                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        logged = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: logged ? "checkmark.circle.fill" : "scalemass.fill")
                            .font(.title2)
                            .foregroundStyle(logged ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(logged ? "Logged for today" : "Log today's weigh-in")
                                .font(.subheadline.bold())
                            Text(logged ? displayWeight(newPointKg) : "Tap to add a sample entry")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .card()
                }
                .buttonStyle(.plain)
                .disabled(logged)
            }
        }
    }
}
