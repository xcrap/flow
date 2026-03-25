import SwiftUI
import AppKit
import AFCore
import AFAgent
import AFCanvas

struct ConversationView: View {
    @Bindable var conversationState: ConversationState
    let node: WorkflowNode
    var onSend: (String, [Attachment]) -> Void

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    let statusColor = conversationState.runtimePhase.statusColor

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

                        ForEach(groupedMessages) { group in
                            switch group {
                            case .single(let message):
                                MessageBubble(message: message)
                                    .id(message.id)
                            case .toolCalls(let messages):
                                ToolCallGroupView(messages: messages)
                                    .id(group.id)
                            }
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
                        if let lastGroup = groupedMessages.last {
                            proxy.scrollTo(lastGroup.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: conversationState.runtimeActivities.count) {
                    withAnimation {
                        if let lastGroup = groupedMessages.last {
                            proxy.scrollTo(lastGroup.id, anchor: .bottom)
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
        onSend(text, [])
    }

    // MARK: - Message Grouping

    private var groupedMessages: [MessageGroup] {
        MessageGroup.group(conversationState.messages)
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

        case .image(let data, _):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
            } else {
                Label("Image", systemImage: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Message Grouping

enum MessageGroup: Identifiable {
    case single(ConversationMessage)
    case toolCalls([ConversationMessage])

    var id: UUID {
        switch self {
        case .single(let msg): msg.id
        case .toolCalls(let msgs): msgs.first?.id ?? UUID()
        }
    }

    /// Groups messages by collapsing consecutive tool-related messages into batches.
    static func group(_ messages: [ConversationMessage]) -> [MessageGroup] {
        var groups: [MessageGroup] = []
        var toolBatch: [ConversationMessage] = []
        for message in messages {
            if isToolMessage(message) {
                toolBatch.append(message)
            } else {
                if !toolBatch.isEmpty {
                    groups.append(.toolCalls(toolBatch))
                    toolBatch = []
                }
                groups.append(.single(message))
            }
        }
        if !toolBatch.isEmpty {
            groups.append(.toolCalls(toolBatch))
        }
        return groups
    }

    static func isToolMessage(_ message: ConversationMessage) -> Bool {
        if message.role == .tool { return true }
        guard !message.content.isEmpty else { return false }
        return message.content.allSatisfy { content in
            if case .toolUse = content { return true }
            return false
        }
    }
}

// MARK: - Shared Status Color

extension ProviderSessionPhase {
    var statusColor: Color {
        switch self {
        case .responding:
            Color(red: 0.25, green: 0.83, blue: 0.43)
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
    }
}

// MARK: - Tool Call Group

struct ToolCallGroupView: View {
    let messages: [ConversationMessage]
    @State private var isExpanded = false

    private var toolCalls: [(name: String, summary: String)] {
        messages.compactMap { message in
            for content in message.content {
                if case .toolUse(_, let name, let input) = content {
                    return (name: name, summary: Self.toolSummary(name: name, input: input))
                }
            }
            return nil
        }
    }

    private var uniqueToolNames: [String] {
        var seen = Set<String>()
        return toolCalls.compactMap { call in
            seen.insert(call.name).inserted ? call.name : nil
        }
    }

    private var errorResults: [String] {
        messages.compactMap { message in
            for content in message.content {
                if case .toolResult(_, let resultContent, let isError) = content, isError {
                    return resultContent
                }
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.7))

                    Text(toolCalls.count == 1
                         ? "1 tool call"
                         : "\(toolCalls.count) tool calls")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(uniqueToolNames.prefix(5), id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.08), in: Capsule())
                    }

                    if uniqueToolNames.count > 5 {
                        Text("+\(uniqueToolNames.count - 5)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .opacity(0.5)
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, call in
                        HStack(spacing: 6) {
                            Text(call.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.orange)
                                .frame(minWidth: 36, alignment: .leading)

                            if !call.summary.isEmpty {
                                Text(call.summary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    }

                    ForEach(Array(errorResults.enumerated()), id: \.offset) { _, error in
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.8))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Tool Summary Parsing

    private static func toolSummary(name: String, input: String) -> String {
        guard !input.isEmpty, input != "{}" else { return "" }

        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(input.prefix(80))
        }

        switch name {
        case "Read":
            guard let path = json["file_path"] as? String else { return "" }
            var result = shortenPath(path)
            if let offset = json["offset"] as? Int { result += ":\(offset)" }
            if let limit = json["limit"] as? Int { result += " (\(limit) lines)" }
            return result

        case "Edit":
            guard let path = json["file_path"] as? String else { return "" }
            return shortenPath(path)

        case "Write":
            guard let path = json["file_path"] as? String else { return "" }
            return shortenPath(path)

        case "Grep":
            var parts: [String] = []
            if let pattern = json["pattern"] as? String { parts.append("\"\(pattern)\"") }
            if let type = json["type"] as? String { parts.append("in *.\(type)") }
            else if let glob = json["glob"] as? String { parts.append("in \(glob)") }
            return parts.joined(separator: " ")

        case "Glob":
            if let pattern = json["pattern"] as? String { return pattern }
            return ""

        case "Bash":
            if let command = json["command"] as? String {
                return String((command.components(separatedBy: .newlines).first ?? command).prefix(80))
            }
            return ""

        case "Agent":
            if let desc = json["description"] as? String { return desc }
            if let prompt = json["prompt"] as? String { return String(prompt.prefix(60)) }
            return ""

        default:
            if let path = json["file_path"] as? String { return shortenPath(path) }
            if let pattern = json["pattern"] as? String { return pattern }
            if let command = json["command"] as? String { return String(command.prefix(60)) }
            return ""
        }
    }

    private static func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count <= 2 { return path }
        return components.suffix(2).joined(separator: "/")
    }
}
