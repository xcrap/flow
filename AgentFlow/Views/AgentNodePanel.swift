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
    @State private var selectedProvider: String
    @State private var selectedModel: String
    @State private var selectedEffort: String
    @State private var showSettings = false
    @State private var systemPromptText: String
    @State private var permissionMode: String
    @FocusState private var inputFocused: Bool

    private let claudeModels = [
        ("sonnet", "Sonnet 4"),
        ("opus", "Opus 4"),
        ("haiku", "Haiku 4.5"),
        ("claude-sonnet-4-6", "Sonnet 4.6"),
        ("claude-opus-4-6", "Opus 4.6"),
    ]

    private let codexModels = [
        ("gpt-5.4", "GPT-5.4"),
        ("o3", "o3"),
        ("o4-mini", "o4-mini"),
    ]

    private var currentModels: [(String, String)] {
        selectedProvider == "codex" ? codexModels : claudeModels
    }

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
        let provider = node.configuration.providerID ?? "claude"
        let modelID = node.configuration.modelID ?? (provider == "codex" ? "gpt-5.4" : "sonnet")
        // Validate model belongs to provider
        let validModels = provider == "codex"
            ? [("gpt-5.4", ""), ("o3", ""), ("o4-mini", "")]
            : [("sonnet", ""), ("opus", ""), ("haiku", ""), ("claude-sonnet-4-6", ""), ("claude-opus-4-6", "")]
        let finalModel = validModels.contains(where: { $0.0 == modelID }) ? modelID : (provider == "codex" ? "gpt-5.4" : "sonnet")

        _selectedProvider = State(initialValue: provider)
        _selectedModel = State(initialValue: finalModel)
        _selectedEffort = State(initialValue: node.configuration.effort ?? "high")
        _systemPromptText = State(initialValue: node.configuration.systemPrompt ?? "")
        _permissionMode = State(initialValue: node.configuration.triggerType ?? "default")
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            messagesArea
            contextBar
            Divider()
            inputBar
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.35))
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.15), radius: isSelected ? 14 : 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.purple : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onChange(of: isSelected) {
            if isSelected { inputFocused = true }
        }
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

            // Provider toggle
            Menu {
                Button {
                    selectedProvider = "claude"
                    selectedModel = "sonnet"
                    onModelChange("sonnet")
                    onEffortChange(selectedEffort)
                } label: {
                    if selectedProvider == "claude" { Label("Claude", systemImage: "checkmark") }
                    else { Text("Claude") }
                }
                Button {
                    selectedProvider = "codex"
                    selectedModel = "gpt-5.4"
                    onModelChange("gpt-5.4")
                } label: {
                    if selectedProvider == "codex" { Label("Codex", systemImage: "checkmark") }
                    else { Text("Codex") }
                }
            } label: {
                Text(selectedProvider == "codex" ? "Codex" : "Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selectedProvider == "codex" ? .green : .purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)

            // Model picker
            Menu {
                ForEach(currentModels, id: \.0) { id, name in
                    Button {
                        selectedModel = id
                        onModelChange(id)
                    } label: {
                        if id == selectedModel {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                Text(currentModels.first(where: { $0.0 == selectedModel })?.1 ?? selectedModel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)

            Menu {
                ForEach(efforts, id: \.0) { id, name in
                    Button {
                        selectedEffort = id
                        onEffortChange(id)
                    } label: {
                        if id == selectedEffort {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                Text(efforts.first(where: { $0.0 == selectedEffort })?.1 ?? selectedEffort)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)

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
                        Text("Provider")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $selectedProvider) {
                            Text("Claude Code").tag("claude")
                            Text("Codex (OpenAI)").tag("codex")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProvider) { _, val in
                            // Update provider and reset model
                            if val == "codex" {
                                selectedModel = "gpt-4o"
                                onModelChange("gpt-4o")
                            } else {
                                selectedModel = "sonnet"
                                onModelChange("sonnet")
                            }
                        }
                    }

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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete node")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isTitleHovered ? Color.purple.opacity(0.15) : Color.white.opacity(0.06))
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

    private var contextLimit: Int {
        let modelLimits: [String: Int] = [
            "sonnet": 200_000,
            "opus": 1_000_000,
            "haiku": 200_000,
            "claude-sonnet-4-6": 200_000,
            "claude-opus-4-6": 1_000_000,
            "claude-sonnet-4-20250514": 200_000,
            "claude-haiku-4-5-20251001": 200_000,
            "gpt-5.4": 200_000,
            "o3": 200_000,
            "o4-mini": 200_000,
        ]
        return modelLimits[selectedModel] ?? 200_000
    }

    private var totalTokens: Int {
        conversation.totalInputTokens + conversation.totalOutputTokens
    }

    private var usagePercent: Double {
        guard contextLimit > 0 else { return 0 }
        return Double(totalTokens) / Double(contextLimit) * 100
    }

    private var contextBar: some View {
        HStack(spacing: 8) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor).opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(usagePercent > 80 ? Color.red : usagePercent > 50 ? Color.orange : Color.purple.opacity(0.6))
                        .frame(width: max(0, geo.size.width * min(1, usagePercent / 100)))
                }
            }
            .frame(height: 3)

            Text("\(Int(usagePercent))% of \(formatContextLimit(contextLimit))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func formatContextLimit(_ limit: Int) -> String {
        if limit >= 1_000_000 {
            return "\(limit / 1_000_000)M"
        }
        return "\(limit / 1000)K"
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
