import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 108, height: 108)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(spacing: 8) {
                Text("Welcome to OnTrack")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Diet, training, and weight in one place — with an AI coach that actually knows your data.")
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
