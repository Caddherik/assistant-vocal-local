import SwiftUI

struct AssistantView: View {
    @Environment(AssistantController.self) private var controller
    @State private var pressing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                Divider()
                footer
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Nouvelle conversation", systemImage: "square.and.pencil") {
                        controller.newConversation()
                    }
                }
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if controller.messages.isEmpty, controller.state == .idle {
                        ContentUnavailableView(
                            "Maintiens le bouton et parle",
                            systemImage: "waveform",
                            description: Text("Relâche quand tu as fini. Tout se passe sur l'iPhone.")
                        )
                        .padding(.top, 60)
                    }
                    ForEach(controller.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if controller.state == .listening || controller.state == .finalizing {
                        Text(controller.liveTranscript.isEmpty ? "…" : controller.liveTranscript)
                            .italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .id("live")
                    }
                }
                .padding()
            }
            .onChange(of: controller.messages.last?.text) {
                if let id = controller.messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: controller.liveTranscript) {
                proxy.scrollTo("live", anchor: .bottom)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(controller.state.label)
                .font(.callout)
                .foregroundStyle(isError ? .red : .secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 40)

            Circle()
                .fill(buttonColor.gradient)
                .frame(width: 92, height: 92)
                .overlay {
                    Image(systemName: buttonSymbol)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pressing ? 1.12 : 1)
                .animation(.spring(duration: 0.25), value: pressing)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !pressing else { return }
                            pressing = true
                            controller.pressBegan()
                        }
                        .onEnded { _ in
                            pressing = false
                            controller.pressEnded()
                        }
                )
                .sensoryFeedback(.impact, trigger: pressing)
                .accessibilityLabel("Maintenir pour parler")

            Text("Pas une source médicale · tout reste sur l'iPhone")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var buttonColor: Color {
        switch controller.state {
        case .listening: .red
        case .finalizing, .thinking: .orange
        case .speaking: .green
        case .idle, .error: .accentColor
        }
    }

    private var buttonSymbol: String {
        switch controller.state {
        case .listening: "waveform"
        case .finalizing, .thinking: "ellipsis"
        case .speaking: "speaker.wave.2.fill"
        case .idle, .error: "mic.fill"
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? Color.accentColor : Color(.secondarySystemBackground),
                    in: .rect(cornerRadius: 18)
                )
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
