import SwiftUI

/// Hosts the full feature tour using the same OnboardingFlow engine as first-run
/// onboarding, fed TourSlides.all() instead of the profile steps. Unlike onboarding,
/// the tour can be closed at any point — that's the one thing this wrapper adds.
struct TourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = OnboardingDraft(persists: false)

    var body: some View {
        NavigationStack {
            OnboardingFlow(steps: TourSlides.all(), draft: draft) {
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
