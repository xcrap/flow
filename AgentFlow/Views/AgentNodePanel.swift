import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct AgentNodePanel: View {
    @Environment(ProviderRegistry.self) private var providerRegistry
    let node: WorkflowNode
    let isSelected: Bool
    let isTitleHovered: Bool
    @Bindable var conversation: ConversationState
    var onProviderChange: (String) -> Void
    var onSend: (String) -> Void
    var onModelChange: (String) -> Void
    var onEffortChange: (String) -> Void
    var onCancel: () -> Void
    var onClearConversation: () -> Void
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

    private let efforts = [
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
        ("max", "Max"),
    ]

    init(
        node: WorkflowNode,
        isSelected: Bool,
        isTitleHovered: Bool = false,
        conversation: ConversationState,
        onProviderChange: @escaping (String) -> Void,
        onSend: @escaping (String) -> Void,
        onModelChange: @escaping (String) -> Void,
        onEffortChange: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onClearConversation: @escaping () -> Void,
        onSystemPromptChange: @escaping (String) -> Void,
        onPermissionModeChange: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.node = node
        self.isSelected = isSelected
        self.isTitleHovered = isTitleHovered
        self.conversation = conversation
        self.onProviderChange = onProviderChange
        self.onSend = onSend
        self.onModelChange = onModelChange
        self.onEffortChange = onEffortChange
        self.onCancel = onCancel
        self.onClearConversation = onClearConversation
        self.onSystemPromptChange = onSystemPromptChange
        self.onPermissionModeChange = onPermissionModeChange
        self.onDelete = onDelete

        let provider = node.configuration.providerID ?? "claude"
        let fallbackModels = Self.fallbackModels(for: provider)
        let modelID = node.configuration.modelID ?? fallbackModels.first?.id ?? "sonnet"
        let validModelIDs = Set(fallbackModels.map(\.id))
        let finalModel = validModelIDs.contains(modelID) ? modelID : fallbackModels.first?.id ?? modelID

        _selectedProvider = State(initialValue: provider)
        _selectedModel = State(initialValue: finalModel)
        _selectedEffort = State(initialValue: node.configuration.effort ?? "high")
        _systemPromptText = State(initialValue: node.configuration.systemPrompt ?? "")
        _permissionMode = State(initialValue: node.configuration.triggerType ?? "auto")
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            messagesArea
            queueTray
            contextBar
            Divider()
            inputBar
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.22))
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
        .onAppear {
            restoreInputFocusIfNeeded()
        }
        .onChange(of: isSelected) {
            restoreInputFocusIfNeeded()
        }
    }

    private var providerOptions: [(id: String, name: String)] {
        let options = providerRegistry.allProviders
            .map { provider in
                (
                    id: provider.id,
                    name: provider.displayName
                        .replacingOccurrences(of: " (OpenAI)", with: "")
                        .replacingOccurrences(of: " (via Claude Code)", with: "")
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if options.isEmpty {
            return [
                (id: "claude", name: "Claude"),
                (id: "codex", name: "Codex"),
            ]
        }

        return options
    }

    private var availableModels: [AIModel] {
        availableModels(for: selectedProvider)
    }

    private var selectedProviderName: String {
        providerOptions.first(where: { $0.id == selectedProvider })?.name ?? selectedProvider.capitalized
    }

    private var selectedModelName: String {
        availableModels.first(where: { $0.id == selectedModel })?.name ?? selectedModel
    }

    private func availableModels(for providerID: String) -> [AIModel] {
        let models = providerRegistry.provider(for: providerID)?.availableModels ?? []
        return models.isEmpty ? Self.fallbackModels(for: providerID) : models
    }

    private static func fallbackModels(for providerID: String) -> [AIModel] {
        switch providerID {
        case "codex":
            return [AIModel(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 200_000)]
        default:
            return [
                AIModel(id: "sonnet", name: "Sonnet (latest)", contextWindow: 200_000),
                AIModel(id: "opus", name: "Opus (latest)", contextWindow: 1_000_000),
                AIModel(id: "haiku", name: "Haiku (latest)", contextWindow: 200_000),
                AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: 200_000),
                AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", contextWindow: 1_000_000),
                AIModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", contextWindow: 200_000),
            ]
        }
    }

    private func selectProvider(_ providerID: String) {
        selectedProvider = providerID
        onProviderChange(providerID)

        let models = availableModels(for: providerID)
        let resolvedModel = models.first(where: { $0.id == selectedModel })?.id ?? models.first?.id
        if let resolvedModel, resolvedModel != selectedModel {
            selectedModel = resolvedModel
            onModelChange(resolvedModel)
        }
    }

    private var isWorking: Bool {
        conversation.runtimePhase.isWorking
    }

    private var statusColor: Color {
        switch conversation.runtimePhase {
        case .responding:
            Color(red: 0.25, green: 0.83, blue: 0.43)
        case .preparing:
            Color(red: 0.88, green: 0.67, blue: 0.22)
        case .cancelling:
            .orange
        case .failed:
            .red
        case .idle:
            Color.white.opacity(0.38)
        }
    }

    private var statusLabel: String {
        conversation.statusLabel
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(isWorking ? 0.22 : 0.12))
                        .frame(width: 18, height: 18)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                }

                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isWorking ? statusColor : .secondary)
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

            Image(systemName: "brain")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()

            if conversation.queuedPromptCount > 0 {
                Text(conversation.queuedPromptCount == 1 ? "1 queued" : "\(conversation.queuedPromptCount) queued")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.88))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                    )
            }

            Menu {
                ForEach(providerOptions, id: \.id) { provider in
                    Button {
                        selectProvider(provider.id)
                    } label: {
                        if selectedProvider == provider.id {
                            Label(provider.name, systemImage: "checkmark")
                        } else {
                            Text(provider.name)
                        }
                    }
                }
            } label: {
                Text(selectedProviderName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selectedProvider == "codex" ? .green : .purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)

            Menu {
                ForEach(availableModels) { model in
                    Button {
                        selectedModel = model.id
                        onModelChange(model.id)
                    } label: {
                        if model.id == selectedModel {
                            Label(model.name, systemImage: "checkmark")
                        } else {
                            Text(model.name)
                        }
                    }
                }
            } label: {
                Text(selectedModelName)
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
                            ForEach(providerOptions, id: \.id) { provider in
                                Text(provider.name).tag(provider.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProvider) { _, val in
                            selectProvider(val)
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

                    if conversation.queuedPromptCount > 0 {
                        Text(conversation.queuedPromptCount == 1 ? "1 prompt queued" : "\(conversation.queuedPromptCount) prompts queued")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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
        .background(isTitleHovered ? Color.white.opacity(0.06) : Color.black.opacity(0.25))
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

    @ViewBuilder
    private var queueTray: some View {
        if conversation.queuedPromptCount > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        conversation.queuedPromptCount == 1 ? "1 prompt waiting" : "\(conversation.queuedPromptCount) prompts waiting",
                        systemImage: "hourglass.bottomhalf.filled"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                    Spacer()

                    Text("Queued")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(conversation.visibleQueuedPromptPreviews.enumerated()), id: \.offset) { index, preview in
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

                            if index == 0 {
                                Text("next")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if conversation.queuedPromptCount > conversation.visibleQueuedPromptPreviews.count {
                        Text("+\(conversation.queuedPromptCount - conversation.visibleQueuedPromptPreviews.count) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
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
            .padding(.bottom, 8)
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

            Text(streamingAttributedText)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private var streamingAttributedText: AttributedString {
        if let attributed = try? AttributedString(
            markdown: conversation.streamingText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(conversation.streamingText)
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

    private var hasUsageData: Bool {
        conversation.currentContextTokens != nil ||
        conversation.totalTokens > 0 ||
        conversation.reportedContextWindow != nil
    }

    private var usagePercent: Double? {
        guard let contextLimit = conversation.reportedContextWindow,
              contextLimit > 0,
              let currentContextTokens = conversation.currentContextTokens,
              currentContextTokens > 0 else {
            return nil
        }
        return min(100, Double(currentContextTokens) / Double(contextLimit) * 100)
    }

    @ViewBuilder
    private var contextBar: some View {
        if hasUsageData || conversation.queuedPromptCount > 0 || conversation.isStreaming {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if conversation.queuedPromptCount > 0 {
                        Text(conversation.queuedPromptCount == 1 ? "1 queued" : "\(conversation.queuedPromptCount) queued")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    }

                    Spacer()
                }

                if let usagePercent {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .separatorColor).opacity(0.2))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(usagePercent > 80 ? Color.red : usagePercent > 50 ? Color.orange : Color.green.opacity(0.8))
                                    .frame(width: max(0, geo.size.width * min(1, usagePercent / 100)))
                            }
                        }
                        .frame(height: 3)

                        Text("Current turn \(Int(usagePercent))% of \(formatTokenCount(conversation.reportedContextWindow ?? 0))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                } else if hasUsageData {
                    Text(usageSummaryText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else if conversation.isStreaming {
                    Text("Waiting for provider usage…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var usageSummaryText: String {
        var pieces: [String] = []

        if let currentContextTokens = conversation.currentContextTokens, currentContextTokens > 0 {
            pieces.append("\(formatTokenCount(currentContextTokens)) last turn")
        }
        if conversation.totalTokens > 0 {
            pieces.append("\(formatTokenCount(conversation.totalTokens)) total")
        }
        if conversation.totalReasoningOutputTokens > 0 {
            pieces.append("\(formatTokenCount(conversation.totalReasoningOutputTokens)) reasoning")
        }
        if conversation.totalCachedInputTokens > 0 {
            pieces.append("\(formatTokenCount(conversation.totalCachedInputTokens)) cached")
        }

        return pieces.joined(separator: " • ")
    }

    private func formatTokenCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1fK", Double(count) / 1_000).replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            return "\(count / 1_000)K"
        default:
            return "\(count)"
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(conversation.isStreaming ? "Add to queue..." : "Message...", text: $inputText, axis: .vertical)
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
            }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canSend ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(conversation.isStreaming ? "Queue prompt" : "Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func restoreInputFocusIfNeeded() {
        guard isSelected else { return }
        Task { @MainActor in
            inputFocused = true
        }
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
            onClearConversation()
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
