import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct ConversationView: View {
    @Bindable var conversationState: ConversationState
    let node: WorkflowNode
    var onSend: (String) -> Void

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: node.iconName)
                    .foregroundStyle(.purple)
                Text(node.title)
                    .font(.headline)
                Spacer()

                if conversationState.totalCostUSD > 0 {
                    Text("$\(conversationState.totalCostUSD, specifier: "%.4f")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if conversationState.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(conversationState.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming text
                        if conversationState.isStreaming && !conversationState.streamingText.isEmpty {
                            streamingBubble
                                .id("streaming")
                        }

                        // Error
                        if let error = conversationState.error {
                            errorBubble(error)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: conversationState.messages.count) {
                    withAnimation {
                        proxy.scrollTo(conversationState.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: conversationState.streamingText) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            Divider()

            // Input
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(
                            inputText.isEmpty || conversationState.isStreaming
                                ? .secondary : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || conversationState.isStreaming)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            inputFocused = true
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)

            Text(conversationState.streamingText)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorBubble(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)

            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        onSend(text)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                    contentView(content)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var icon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "brain")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
        case .tool:
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case .system:
            Image(systemName: "gear")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: Color.blue.opacity(0.06)
        case .assistant: Color(nsColor: .controlBackgroundColor)
        case .tool: Color.orange.opacity(0.06)
        case .system: Color.gray.opacity(0.06)
        }
    }

    @ViewBuilder
    private func contentView(_ content: MessageContent) -> some View {
        switch content {
        case .text(let text):
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                Text(language)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }

        case .toolUse(_, let name, let input):
            VStack(alignment: .leading, spacing: 2) {
                Label(name, systemImage: "hammer.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)

                if !input.isEmpty && input != "{}" {
                    Text(input)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

        case .toolResult(_, let resultContent, let isError):
            HStack(spacing: 4) {
                Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(isError ? .red : .green)
                    .font(.system(size: 11))
                Text(resultContent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

        case .image:
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
