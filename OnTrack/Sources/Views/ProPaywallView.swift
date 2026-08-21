import SwiftUI

/// Placeholder paywall shown when an AI feature is gated by `Pro.isActive`.
/// Everyone is Pro at launch (see Pro.swift), so this only appears once the
/// flag is flipped off. Flesh out with real StoreKit purchase UI later.
struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    /// Runs after unlock, so the AI action that triggered the sheet can proceed.
    var onUnlock: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 84, height: 84)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    Text("OnTrack Pro")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text("The AI Coach, daily insights, and Photo Meal are part of OnTrack Pro.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Coming soon.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .card()

                Spacer()

                #if DEBUG
                Button("Unlock (test)") {
                    UserDefaults.standard.set(true, forKey: Pro.key)
                    dismiss()
                    onUnlock()
                }
                .buttonStyle(PillButtonStyle())
                #endif
                Button("Maybe later") { dismiss() }
                    .font(.headline)
                    .padding(.vertical, 8)
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OnTrack Pro")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
