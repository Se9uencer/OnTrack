import SwiftUI

/// Shared title + subtitle + content layout used by every profile step, so each
/// step file only has to define what's unique about that one screen.
struct StepScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(20)
            .padding(.top, 12)
        }
    }
}

/// A selectable option row shared by Sex/Activity/Goal — a card that highlights
/// with a checkmark and an accent border when selected.
struct SelectableOptionRow: View {
    let label: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Image(systemName: icon).font(.title3).frame(width: 28)
                }
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
