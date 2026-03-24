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
                HStack(spacing: 8) {
                    let statusColor: Color = switch conversationState.runtimePhase {
                    case .responding:
                        .green
                    case .preparing:
                        Color(red: 0.88, green: 0.67, blue: 0.22)
                    case .compacting:
                        Color(red: 0.93, green: 0.58, blue: 0.18)
                    case .compacted:
                        Color(red: 0.48, green: 0.72, blue: 0.58)
                    case .cancelling:
                        .orange
                    case .failed:
                        .red
                    case .idle:
                        Color.white.opacity(0.38)
                    }

                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(conversationState.runtimePhase.isWorking ? 0.22 : 0.12))
                            .frame(width: 18, height: 18)

                        Circle()
                            .fill(statusColor)
                            .frame(width: 9, height: 9)
                    }

                    Text(conversationState.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(conversationState.runtimePhase.isWorking ? statusColor : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        }
                )

                Image(systemName: node.iconName)
                    .foregroundStyle(.purple)
                Text(node.title)
                    .font(.headline)
                Spacer()

                if conversationState.queuedPromptCount > 0 {
                    Text(conversationState.queuedPromptCount == 1 ? "1 queued" : "\(conversationState.queuedPromptCount) queued")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
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
                        if !conversationState.recentRuntimeActivities.isEmpty {
                            RuntimeActivityList(activities: conversationState.recentRuntimeActivities)
                        }

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
                .onChange(of: conversationState.runtimeActivities.count) {
                    withAnimation {
                        if let lastMessageID = conversationState.messages.last?.id {
                            proxy.scrollTo(lastMessageID, anchor: .bottom)
                        } else if conversationState.isStreaming {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: conversationState.streamingText) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }

            if conversationState.queuedPromptCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            conversationState.queuedPromptCount == 1 ? "1 prompt waiting" : "\(conversationState.queuedPromptCount) prompts waiting",
                            systemImage: "hourglass.bottomhalf.filled"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))

                        Spacer()
                    }

                    ForEach(Array(conversationState.visibleQueuedPromptPreviews.enumerated()), id: \.offset) { index, preview in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.white.opacity(index == 0 ? 0.42 : 0.2))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(preview)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            Divider()

            // Input
            HStack(alignment: .bottom, spacing: 8) {
                TextField(conversationState.isStreaming ? "Add to queue..." : "Message...", text: $inputText, axis: .vertical)
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
                            inputText.isEmpty
                                ? .secondary : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help(conversationState.isStreaming ? "Queue prompt" : "Send")
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
