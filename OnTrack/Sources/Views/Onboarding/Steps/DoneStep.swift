import SwiftUI

/// The closing screen. Purely a confirmation — the "Let's go" CTA (owned by
/// OnboardingFlow) is what actually commits the profile and finishes onboarding.
struct DoneStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.green)
                .frame(width: 108, height: 108)
                .background(Color.green.opacity(0.15), in: Circle())
            VStack(spacing: 8) {
                Text("You're all set")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Your targets are ready. Fine-tune anything, anytime, in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
