import SwiftUI

/// One-time disclosure + opt-in before any data is sent to the AI provider,
/// required by the App Store AI-data-sharing disclosure rule (Nov 2025).
/// State lives in @AppStorage("aiConsentGiven"); Settings lets users revoke it.
struct AIConsentSheet: View {
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @Environment(\.dismiss) private var dismiss
    /// Runs after consent is recorded, so the AI action that triggered the sheet can proceed.
    var onAllow: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 84, height: 84)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                        Text("AI features use Google Gemini")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                        Text("To power the Coach and Photo Meal estimates, OnTrack sends some of your data to Google Gemini. Your choice — you can turn this off anytime in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        row("photo.fill", "What's shared",
                            "Meal photos you analyze, and summaries of your workouts, diet, weight entries, and profile.")
                        row("heart.slash.fill", "What's never shared",
                            "Data from Apple Health is never sent.")
                        row("server.rack", "How it's sent",
                            "Through the developer's own proxy server to Google Gemini, over an encrypted connection.")
                    }
                    .padding()
                    .card()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        aiConsentGiven = true
                        dismiss()
                        onAllow()
                    } label: {
                        Text("Allow")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button("Not Now") { dismiss() }
                        .font(.headline)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .navigationTitle("AI Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
