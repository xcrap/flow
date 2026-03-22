import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct AgentNodePanel: View {
    let node: WorkflowNode
    let isSelected: Bool
    let isTitleHovered: Bool
    @Bindable var conversation: ConversationState
    var onSend: (String) -> Void
    var onModelChange: (String) -> Void
    var onEffortChange: (String) -> Void
    var onCancel: () -> Void
    var onSystemPromptChange: (String) -> Void
    var onPermissionModeChange: (String) -> Void
    var onDelete: () -> Void

    @State private var inputText = ""
    @State private var selectedModel: String
    @State private var selectedEffort: String
    @State private var showSettings = false
    @State private var systemPromptText: String
    @State private var permissionMode: String
    @FocusState private var inputFocused: Bool

    private let models = [
        ("sonnet", "Sonnet 4"),
        ("opus", "Opus 4"),
        ("haiku", "Haiku 4.5"),
        ("claude-sonnet-4-6", "Sonnet 4.6"),
        ("claude-opus-4-6", "Opus 4.6"),
    ]

    private let efforts = [
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
        ("max", "Max"),
    ]

    init(node: WorkflowNode, isSelected: Bool, isTitleHovered: Bool = false, conversation: ConversationState,
         onSend: @escaping (String) -> Void, onModelChange: @escaping (String) -> Void,
         onEffortChange: @escaping (String) -> Void, onCancel: @escaping () -> Void,
         onSystemPromptChange: @escaping (String) -> Void, onPermissionModeChange: @escaping (String) -> Void,
         onDelete: @escaping () -> Void) {
        self.node = node
        self.isSelected = isSelected
        self.isTitleHovered = isTitleHovered
        self.conversation = conversation
        self.onSend = onSend
        self.onModelChange = onModelChange
        self.onEffortChange = onEffortChange
        self.onCancel = onCancel
        self.onSystemPromptChange = onSystemPromptChange
        self.onPermissionModeChange = onPermissionModeChange
        self.onDelete = onDelete
        _selectedModel = State(initialValue: node.configuration.modelID ?? "sonnet")
        _selectedEffort = State(initialValue: node.configuration.effort ?? "high")
        _systemPromptText = State(initialValue: node.configuration.systemPrompt ?? "")
        _permissionMode = State(initialValue: node.configuration.triggerType ?? "default")
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            messagesArea
            if conversation.totalInputTokens > 0 || conversation.totalOutputTokens > 0 {
                tokenBar
            }
            Divider()
            inputBar
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 12 : 6, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.purple : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(conversation.isStreaming ? Color.blue : .gray.opacity(0.4))
                .frame(width: 9, height: 9)

            Image(systemName: "brain")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()

            Picker("", selection: $selectedModel) {
                ForEach(models, id: \.0) { id, name in
                    Text(name).tag(id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 105)
            .controlSize(.small)
            .onChange(of: selectedModel) { _, val in onModelChange(val) }

            Picker("", selection: $selectedEffort) {
                ForEach(efforts, id: \.0) { id, name in
                    Text(name).tag(id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 75)
            .controlSize(.small)
            .onChange(of: selectedEffort) { _, val in onEffortChange(val) }

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(systemPromptText.isEmpty ? .secondary : .purple)
            }
            .buttonStyle(.plain)
            .help("Agent settings")
            .popover(isPresented: $showSettings) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Agent Settings")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permission Mode")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $permissionMode) {
                            Text("Default").tag("default")
                            Text("Plan").tag("plan")
                            Text("Auto").tag("auto")
                            Text("Accept Edits").tag("acceptEdits")
                            Text("Bypass All").tag("bypassPermissions")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: permissionMode) { _, val in
                            onPermissionModeChange(val)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $systemPromptText)
                            .font(.system(size: 13))
                            .frame(width: 380, height: 120)
                            .onChange(of: systemPromptText) { _, val in
                                onSystemPromptChange(val)
                            }
                    }
                }
                .padding(16)
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete node")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isTitleHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if conversation.messages.isEmpty && !conversation.isStreaming {
                        emptyState
                    }

                    ForEach(conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    if conversation.isStreaming && !conversation.streamingText.isEmpty {
                        streamingRow
                            .id("streaming")
                    }

                    if let error = conversation.error {
                        errorRow(error)
                    }
                }
                .padding(16)
            }
            .onChange(of: conversation.messages.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: conversation.streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("Start a conversation")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 50)
    }

    private var streamingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundStyle(.purple)
                .frame(width: 20, height: 20)

            Text(try! AttributedString(markdown: conversation.streamingText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorRow(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .frame(width: 20, height: 20)

            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Token Bar

    private var tokenBar: some View {
        HStack(spacing: 14) {
            Label("\(formatTokens(conversation.totalInputTokens)) in", systemImage: "arrow.down.circle")
            Label("\(formatTokens(conversation.totalOutputTokens)) out", systemImage: "arrow.up.circle")
            Spacer()
            Text("\(conversation.messages.count) msgs")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineSpacing(2)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit {
                    send()
                }

            if conversation.isStreaming {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(canSend ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !conversation.isStreaming
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        // Handle slash commands
        if text.hasPrefix("/") {
            handleSlashCommand(text)
            return
        }

        onSend(text)
    }

    private func handleSlashCommand(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).lowercased()
        let arg = parts.count > 1 ? String(parts[1]) : nil

        switch cmd {
        case "/clear":
            conversation.messages.removeAll()
            conversation.error = nil
            conversation.sessionID = nil
        case "/model":
            if let model = arg {
                selectedModel = model
                onModelChange(model)
            }
        case "/system":
            if let prompt = arg {
                systemPromptText = prompt
                onSystemPromptChange(prompt)
            }
        case "/effort":
            if let effort = arg {
                selectedEffort = effort
                onEffortChange(effort)
            }
        case "/mode":
            if let mode = arg {
                permissionMode = mode
                onPermissionModeChange(mode)
            }
        default:
            // Unknown command — send as regular message
            onSend(command)
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                    contentView(content)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var icon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundStyle(.purple)
        case .tool:
            Image(systemName: "wrench.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .system:
            Image(systemName: "gear")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.06)
        case .assistant: Color(nsColor: .controlBackgroundColor).opacity(0.3)
        case .tool: .orange.opacity(0.04)
        case .system: .gray.opacity(0.04)
        }
    }

    @ViewBuilder
    private func contentView(_ content: MessageContent) -> some View {
        switch content {
        case .text(let text):
            let segments = Self.parseTextSegments(text)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .markdown(let md):
                        if let attributed = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attributed)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        } else {
                            Text(md)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                    case .codeBlock(let lang, let code):
                        VStack(alignment: .leading, spacing: 0) {
                            if !lang.isEmpty {
                                HStack {
                                    Text(lang)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(code, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(code)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                        }
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                        }
                    }
                }
            }

        case .code(let lang, let code):
            VStack(alignment: .leading, spacing: 0) {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
            }

        case .toolUse(_, let name, let input):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.orange)

                if !input.isEmpty && input != "{}" {
                    Text(input)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }

        case .toolResult(_, let resultContent, let isError):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isError ? .red : .green)
                    Text(isError ? "Error" : "Result")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isError ? .red : .green)
                }
                Text(resultContent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }

        case .image:
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Code Fence Parser

    enum TextSegment {
        case markdown(String)
        case codeBlock(language: String, code: String)
    }

    static func parseTextSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        let lines = text.components(separatedBy: "\n")
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeLines: [String] = []

        for line in lines {
            if !inCodeBlock && line.hasPrefix("```") {
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.markdown(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
            } else if inCodeBlock && line.hasPrefix("```") {
                segments.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLanguage = ""
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
        }

        if inCodeBlock {
            segments.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        } else if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.markdown(currentText.trimmingCharacters(in: .newlines)))
        }

        return segments
    }
}
