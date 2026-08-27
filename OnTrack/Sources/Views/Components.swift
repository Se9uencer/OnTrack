import SwiftUI

// Shared dashboard components — used by Today and the onboarding targets reveal.

/// A circular progress ring with centered content.
struct ProgressRing<Content: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemGray4).opacity(0.5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
    }
}

/// One macro card: grams number, label, and a ring with an icon.
struct MacroRingCard: View {
    let title: String
    let left: Double
    let fraction: Double
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(max(0, left)))g").font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
            ProgressRing(fraction: fraction, color: color, lineWidth: 6) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            }
            .frame(width: 52, height: 52)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
