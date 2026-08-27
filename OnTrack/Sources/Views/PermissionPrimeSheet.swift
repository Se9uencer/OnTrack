import SwiftUI

/// A plain-language explanation shown before a system permission prompt (HealthKit,
/// notifications), so the system dialog never appears cold. "Allow" runs the caller's
/// actual system request; "Not Now" just dismisses. Callers show this at most once per
/// permission, gated by their own @AppStorage flag — a decline is never re-nagged.
struct PermissionPrimeSheet: View {
    let icon: String
    let navTitle: String
    let title: String
    let message: String
    var onAllow: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 84, height: 84)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
                VStack(spacing: 8) {
                    Button("Allow") {
                        dismiss()
                        onAllow()
                    }
                    .buttonStyle(PillButtonStyle())
                    Button("Not Now") { dismiss() }
                        .font(.headline)
                        .padding(.vertical, 8)
                }
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
