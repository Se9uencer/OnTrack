import SwiftUI
import SwiftData

/// Renders one `[OnboardingStep]` array as a paged flow with a progress bar and a
/// Back/Continue bar. Owns navigation and validation gating; every step just declares
/// its content and whether it's currently valid to advance past.
struct OnboardingFlow: View {
    let steps: [OnboardingStep]
    var draft: OnboardingDraft
    var onFinish: () -> Void

    @State private var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(steps: [OnboardingStep], draft: OnboardingDraft, onFinish: @escaping () -> Void) {
        self.steps = steps
        self.draft = draft
        self.onFinish = onFinish
        _index = State(initialValue: min(max(draft.stepIndex, 0), steps.count - 1))
    }

    private var step: OnboardingStep { steps[index] }
    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            if step.showsProgress {
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            ZStack {
                step.content(draft)
                    .id(step.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color(.systemGroupedBackground))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: index)
        .keyboardDoneButton()
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color(.systemGray5))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(steps.count))
                }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if !isFirst {
                Button("Back") { goBack() }
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Button(step.ctaTitle(draft)) { advance() }
                .buttonStyle(PillButtonStyle())
                .disabled(!step.isValid(draft))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func advance() {
        guard step.isValid(draft) else { return }
        if isLast {
            onFinish()
        } else {
            index += 1
            draft.stepIndex = index
        }
    }

    private func goBack() {
        guard !isFirst else { return }
        index -= 1
        draft.stepIndex = index
    }
}

/// Owns the draft and the SwiftData commit; hosted directly by the app root when
/// `hasOnboarded` is false.
struct OnboardingRootView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("useMetric") private var useMetric = false
    @State private var draft = OnboardingDraft()

    var body: some View {
        OnboardingFlow(steps: OnboardingSteps.firstRun(), draft: draft, onFinish: finish)
    }

    private func finish() {
        guard let h = draft.heightCm(metric: useMetric), let w = draft.weightKg(metric: useMetric) else { return }
        let profile = UserProfile()
        profile.age = draft.age
        profile.sex = draft.sex
        profile.heightCm = h
        profile.activityLevel = draft.activityLevel
        profile.weeklyRateLbs = draft.weeklyRateLbs
        context.insert(profile)
        context.insert(BodyWeightEntry(weightKg: w))
        Task {
            try? await HealthKitService.shared.requestAuthorization()
            try? await HealthKitService.shared.saveWeight(w, date: Date())
            _ = await NotificationService.shared.requestPermission()
        }
        OnboardingDraft.clearPersisted()
        hasOnboarded = true
    }
}
