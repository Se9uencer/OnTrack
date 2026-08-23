import SwiftUI
import SwiftData

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" | "assistant"
    var content: String
}

struct CoachView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var streaming = false
    @State private var errorText: String?
    @State private var showConsent = false
    @State private var pendingPrompt: String?
    @State private var showPaywall = false

    var body: some View {
        Group {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { quickActions }
                            ForEach(messages) { msg in
                                bubble(msg)
                            }
                            if let errorText {
                                Text(errorText)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages) {
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                Divider()
                HStack {
                    TextField("Ask your coach…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        send(input)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || streaming)
                }
                .padding([.horizontal, .top])
                Text("AI-generated guidance and estimates — not medical or nutritional advice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !messages.isEmpty {
                    Button("Clear") { messages = []; errorText = nil }
                }
            }

            .sheet(isPresented: $showConsent) {
                AIConsentSheet { if let p = pendingPrompt { pendingPrompt = nil; send(p) } }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView { if let p = pendingPrompt { pendingPrompt = nil; send(p) } }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What can I help with?")
                .font(.headline)
            actionButton("Today's insight", icon: "lightbulb.fill",
                         prompt: "Give me an insight on how I'm doing today and this week. What should I focus on for the rest of today?")
            actionButton("Weekly recap", icon: "calendar",
                         prompt: "Give me a full recap of my week: weight trend, diet quality vs my targets, and training. What went well, what needs work?")
            actionButton("Suggest next workout", icon: "dumbbell.fill",
                         prompt: "Based on my recent training, what should my next workout be? Suggest exercises, sets, and target weights based on my history.")
            actionButton("Meal ideas for my remaining macros", icon: "fork.knife",
                         prompt: "Based on what I've eaten today and my remaining calories and macros, suggest 2-3 specific meal or snack ideas that would fit.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ title: String, icon: String, prompt: String) -> some View {
        Button {
            send(prompt)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == "user" { Spacer(minLength: 40) }
            Text(LocalizedStringKey(msg.content.isEmpty ? "…" : msg.content))
                .padding(12)
                .background(
                    msg.role == "user" ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
            if msg.role == "assistant" { Spacer(minLength: 40) }
        }
        .id(msg.id)
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !streaming else { return }
        guard Pro.isActive else { pendingPrompt = text; showPaywall = true; return }
        guard aiConsentGiven else { pendingPrompt = text; showConsent = true; return }
        input = ""
        errorText = nil
        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        streaming = true

        Task {
            let dataContext = await CoachContext.build(context: context)
            var nimMessages: [AIClient.Message] = []
            if let dataContext {
                nimMessages.append(.init(role: "system",
                    content: CoachContext.systemPrompt + "\n\nUser's recent data:\n" + dataContext))
            } else {
                nimMessages.append(.init(role: "system",
                    content: CoachContext.systemPrompt + "\n\nThe user has little or no logged data yet. Encourage them to log their weight, meals, and workouts for a few days so you can give data-driven advice. You can still answer general fitness questions."))
            }
            // Conversation history (skip the empty assistant placeholder).
            for msg in messages where !msg.content.isEmpty {
                nimMessages.append(.init(role: msg.role, content: msg.content))
            }
            do {
                for try await delta in AIClient.stream(messages: nimMessages) {
                    await MainActor.run { messages[messages.count - 1].content += delta }
                }
            } catch {
                await MainActor.run {
                    if messages.last?.content.isEmpty == true { messages.removeLast(2) }
                    errorText = error.localizedDescription
                }
            }
            await MainActor.run { streaming = false }
        }
    }
}
