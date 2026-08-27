import SwiftUI

/// Hosts the full feature tour using the same OnboardingFlow engine as first-run
/// onboarding, fed TourSlides.all() instead of the profile steps. Unlike onboarding,
/// the tour can be closed at any point — that's the one thing this wrapper adds.
///
/// Tapping "Try it" on a slide leaves the tour rather than returning to it, so
/// `startAt` lets a caller (Today's "Continue the tour" card, Settings) reopen right
/// after wherever the user last left off instead of always restarting at slide one.
struct TourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnboardingDraft

    init(startAt: Int = 0) {
        let draft = OnboardingDraft(persists: false)
        draft.stepIndex = startAt
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            OnboardingFlow(steps: TourSlides.all(), draft: draft) {
                // Reached the end by tapping through normally (not via a "Try it") —
                // there's nothing left to resume.
                UserDefaults.standard.set(-1, forKey: TourSlides.resumeIndexKey)
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
