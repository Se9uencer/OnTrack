import SwiftUI

/// One screen in the full replayable feature tour. Explains a feature, then offers
/// a "Try it" that dismisses the tour and lands the user on the real thing.
struct TourSlideView: View {
    let icon: String
    let title: String
    let message: String
    let tryItLabel: String
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StepScaffold(title: title, subtitle: message) {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 88, height: 88)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                    .frame(maxWidth: .infinity)
                Button(tryItLabel) {
                    dismiss()
                    action()
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }
}
