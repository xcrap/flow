import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AFCore
import AFAgent
import AFCanvas

struct AgentNodePanel: View {
    @Environment(ProviderRegistry.self) private var providerRegistry
    let node: WorkflowNode
    let nodeNumber: Int?
    let isSelected: Bool
    let isTitleHovered: Bool
    @Bindable var conversation: ConversationState
    var onProviderChange: (String) -> Void
    var onSend: (String, [Attachment]) -> Void
    var onModelChange: (String) -> Void
    var onEffortChange: (String) -> Void
    var onCancel: () -> Void
    var onClearConversation: () -> Void
    var onSystemPromptChange: (String) -> Void
    var onPermissionModeChange: (String) -> Void
    var onRemoveQueuedPrompt: (Int) -> Void
    var onDelete: () -> Void

    @State private var inputText = ""
    @State private var selectedProvider: String
    @State private var selectedModel: String
    @State private var selectedEffort: String
    @State private var showSettings = false
    @State private var systemPromptText: String
    @State private var permissionMode: String
    @State private var isDragTargeted = false
    @FocusState private var inputFocused: Bool

    private let efforts = [
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
        ("max", "Max"),
    ]

    init(
        node: WorkflowNode,
        nodeNumber: Int? = nil,
        isSelected: Bool,
        isTitleHovered: Bool = false,
        conversation: ConversationState,
        onProviderChange: @escaping (String) -> Void,
        onSend: @escaping (String, [Attachment]) -> Void,
        onModelChange: @escaping (String) -> Void,
        onEffortChange: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onClearConversation: @escaping () -> Void,
        onSystemPromptChange: @escaping (String) -> Void,
        onPermissionModeChange: @escaping (String) -> Void,
        onRemoveQueuedPrompt: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.node = node
        self.nodeNumber = nodeNumber
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
        self.onRemoveQueuedPrompt = onRemoveQueuedPrompt
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
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.purple.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.purple.opacity(0.5), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.purple.opacity(0.06))
                    )
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
            handleDroppedItems(providers)
            return true
        }
        .onAppear {
            restoreInputFocusIfNeeded()
        }
        .onChange(of: isSelected) {
            restoreInputFocusIfNeeded()
        }
        .onChange(of: node.id) {
            // Sync @State with new node when SwiftUI reuses this view
            let provider = node.configuration.providerID ?? "claude"
            selectedProvider = provider
            let models = availableModels(for: provider)
            selectedModel = node.configuration.modelID ?? models.first?.id ?? "sonnet"
            selectedEffort = node.configuration.effort ?? "high"
            systemPromptText = node.configuration.systemPrompt ?? ""
            permissionMode = node.configuration.triggerType ?? "auto"
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
                AIModel(id: "opus", name: "Opus (latest)", contextWindow: 200_000),
                AIModel(id: "haiku", name: "Haiku (latest)", contextWindow: 200_000),
                AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: 200_000),
                AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", contextWindow: 200_000),
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
        conversation.runtimePhase.statusColor
    }

    private var statusLabel: String {
        conversation.statusLabel
    }

    // MARK: - Title Bar

    private var headerBackground: Color {
        if isTitleHovered { return Color.white.opacity(0.06) }
        guard isWorking else { return Color(red: 0.13, green: 0.13, blue: 0.14) }
        return statusColor.opacity(0.12)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isWorking ? statusColor : .purple)

            if let nodeNumber {
                Text("\(nodeNumber)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.purple.opacity(0.4)))
            }

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            if isWorking {
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

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
        .background(headerBackground)
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if conversation.messages.isEmpty &&
                        conversation.recentRuntimeActivities.isEmpty &&
                        !conversation.isStreaming
                    {
                        emptyState
                    }

                    if !nonToolRuntimeActivities.isEmpty {
                        RuntimeActivityList(activities: nonToolRuntimeActivities)
                    }

                    ForEach(groupedMessages) { group in
                        switch group {
                        case .single(let message):
                            MessageRow(message: message)
                                .id(message.id)
                        case .toolCalls(let messages):
                            ToolCallGroupView(messages: messages)
                                .id(group.id)
                        }
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
                    if let lastGroup = groupedMessages.last {
                        proxy.scrollTo(lastGroup.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: conversation.runtimeActivities.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if let lastGroup = groupedMessages.last {
                        proxy.scrollTo(lastGroup.id, anchor: .bottom)
                    } else if conversation.isStreaming {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: conversation.streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    // MARK: - Message Grouping

    private var nonToolRuntimeActivities: [ConversationRuntimeActivity] {
        conversation.recentRuntimeActivities.filter { $0.kind != .tool }
    }

    private var groupedMessages: [MessageGroup] {
        MessageGroup.group(conversation.messages)
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

                            Button {
                                onRemoveQueuedPrompt(index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove from queue")
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
        contextLimitForDisplay != nil
    }

    private var contextLimitForDisplay: Int? {
        let selectedModelContextWindow = availableModels.first(where: { $0.id == selectedModel })?.contextWindow

        if selectedProvider == "claude" {
            return selectedModelContextWindow ?? conversation.reportedContextWindow
        }

        return conversation.reportedContextWindow ?? selectedModelContextWindow
    }

    private var usagePercent: Double? {
        guard let contextLimit = contextLimitForDisplay,
              contextLimit > 0,
              let currentContextTokens = conversation.currentContextTokens,
              currentContextTokens > 0 else {
            return nil
        }
        return min(100, Double(currentContextTokens) / Double(contextLimit) * 100)
    }

    private var usagePercentLabel: String? {
        guard let usagePercent else { return nil }

        switch usagePercent {
        case ..<1:
            return "<1%"
        case ..<10:
            let formatted = String(format: "%.1f", usagePercent)
                .replacingOccurrences(of: ".0", with: "")
            return "\(formatted)%"
        default:
            return "\(Int(usagePercent.rounded()))%"
        }
    }

    private var usageStatusText: String? {
        guard let contextLimit = contextLimitForDisplay,
              contextLimit > 0,
              let currentContextTokens = conversation.currentContextTokens,
              currentContextTokens > 0,
              let usagePercentLabel
        else {
            return nil
        }

        return "Current turn \(formatTokenCount(currentContextTokens)) of \(formatTokenCount(contextLimit)) (\(usagePercentLabel))"
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

                if let usagePercent, let usageStatusText {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .separatorColor).opacity(0.2))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(usagePercent > 80 ? Color.red : usagePercent > 50 ? Color.orange : Color.green.opacity(0.8))
                                    .frame(width: max(2, geo.size.width * min(1, usagePercent / 100)))
                            }
                        }
                        .frame(height: 3)

                        Text(usageStatusText)
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
        VStack(spacing: 0) {
            // Attachment thumbnails strip
            if !conversation.pendingAttachments.isEmpty {
                attachmentStrip
            }

            TextField(conversation.isStreaming ? "Add to queue..." : "Ask for follow-up changes or attach images", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineSpacing(3)
                .lineLimit(2...8)
                .focused($inputFocused)
                .onSubmit {
                    send()
                }
                .onPasteCommand(of: [.image, .png, .jpeg, .gif, .tiff, .heic]) { providers in
                    handlePastedItems(providers)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                // Paperclip attach button
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 28, height: 24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Attach images")

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
                    HStack(spacing: 4) {
                        Image(systemName: selectedProvider == "codex" ? "circle.hexagongrid" : "brain")
                            .font(.system(size: 10, weight: .semibold))
                        Text(selectedProviderName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selectedProvider == "codex" ? .green : .purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
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
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(!systemPromptText.isEmpty || permissionMode != "auto" || selectedEffort != "high" ? .purple : .white.opacity(0.45))
                        .frame(width: 28, height: 24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings) {
                    settingsPopover
                }

                Spacer()

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
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? Color.accentColor : .white.opacity(0.15))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(conversation.isStreaming ? "Queue prompt" : "Send")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: - Attachment Strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(conversation.pendingAttachments) { attachment in
                    AttachmentThumbnail(attachment: attachment) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            conversation.removeAttachment(attachment.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .tiff, .heic, .webP, .bmp]
        panel.message = "Select images to attach"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            addFileAttachment(url)
        }
    }

    private func addFileAttachment(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension
        let mime = Attachment.mimeType(forExtension: ext)
        let attachment = Attachment(data: data, mimeType: mime, filename: url.lastPathComponent)
        withAnimation(.easeOut(duration: 0.15)) {
            conversation.addAttachment(attachment)
        }
    }

    // MARK: - Drag & Drop

    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Try file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp"]
                    guard imageExtensions.contains(ext) else { return }
                    Task { @MainActor in
                        addFileAttachment(url)
                    }
                }
            }
            // Try image data directly
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in
                        let attachment = Attachment(data: data, mimeType: "image/png", filename: "dropped-image.png")
                        withAnimation(.easeOut(duration: 0.15)) {
                            conversation.addAttachment(attachment)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Paste

    private func handlePastedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            for type in [UTType.png, .jpeg, .gif, .tiff, .heic] {
                if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                        guard let data else { return }
                        let mime = "image/\(type.preferredFilenameExtension ?? "png")"
                        let ext = type.preferredFilenameExtension ?? "png"
                        Task { @MainActor in
                            let attachment = Attachment(data: data, mimeType: mime, filename: "pasted-image.\(ext)")
                            withAnimation(.easeOut(duration: 0.15)) {
                                conversation.addAttachment(attachment)
                            }
                        }
                    }
                    break
                }
            }
        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Effort
            VStack(alignment: .leading, spacing: 6) {
                Text("Effort")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(efforts, id: \.0) { id, name in
                    Button {
                        selectedEffort = id
                        onEffortChange(id)
                    } label: {
                        HStack(spacing: 8) {
                            if id == selectedEffort {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16)
                            }
                            Text(id == "high" ? "\(name) (default)" : name)
                                .font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach([("auto", "Auto (default)"), ("plan", "Plan")], id: \.0) { id, name in
                    Button {
                        permissionMode = id
                        onPermissionModeChange(id)
                    } label: {
                        HStack(spacing: 8) {
                            if id == permissionMode || (id == "auto" && !["auto", "plan"].contains(permissionMode)) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16)
                            }
                            Text(name)
                                .font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Access
            VStack(alignment: .leading, spacing: 6) {
                Text("Access")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                let accessOptions: [(String, String)] = [
                    ("default", "Supervised"),
                    ("acceptEdits", "Accept Edits"),
                    ("bypassPermissions", "Full access"),
                ]
                ForEach(accessOptions, id: \.0) { id, name in
                    let isSelected = (id == "default" && ["default", "auto", "plan"].contains(permissionMode))
                        || (id == "acceptEdits" && permissionMode == "acceptEdits")
                        || (id == "bypassPermissions" && permissionMode == "bypassPermissions")
                    Button {
                        // Map access to permission mode, preserving the current mode choice
                        switch id {
                        case "acceptEdits":
                            permissionMode = "acceptEdits"
                        case "bypassPermissions":
                            permissionMode = "bypassPermissions"
                        default:
                            permissionMode = "auto"
                        }
                        onPermissionModeChange(permissionMode)
                    } label: {
                        HStack(spacing: 8) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16)
                            }
                            Text(name)
                                .font(.system(size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // System prompt (collapsible)
            if !systemPromptText.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(systemPromptText)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !conversation.pendingAttachments.isEmpty
    }

    private func restoreInputFocusIfNeeded() {
        guard isSelected else { return }
        Task { @MainActor in
            inputFocused = true
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        var attachments = conversation.pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        inputText = ""
        conversation.clearAttachments()

        // Detect image file paths in the text and convert to attachments
        var promptLines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let attachment = Self.attachmentFromFilePath(trimmed) {
                attachments.append(attachment)
            } else {
                promptLines.append(line)
            }
        }

        let prompt: String
        let remainingText = promptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if remainingText.isEmpty && !attachments.isEmpty {
            prompt = "Analyze the attached image(s)."
        } else if remainingText.isEmpty {
            return
        } else {
            prompt = remainingText
        }

        // Handle slash commands (only if no attachments)
        if attachments.isEmpty && prompt.hasPrefix("/") {
            handleSlashCommand(prompt)
            return
        }

        onSend(prompt, attachments)
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp"]

    private static func attachmentFromFilePath(_ path: String) -> Attachment? {
        let cleaned = path.replacingOccurrences(of: "file://", with: "")
        guard cleaned.hasPrefix("/") || cleaned.hasPrefix("~") else { return nil }
        let expanded = cleaned.hasPrefix("~")
            ? NSString(string: cleaned).expandingTildeInPath
            : cleaned
        let ext = (expanded as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)) else { return nil }
        let mime = Attachment.mimeType(forExtension: ext)
        let filename = (expanded as NSString).lastPathComponent
        return Attachment(data: data, mimeType: mime, filename: filename)
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
            onSend(command, [])
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
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

// MARK: - Attachment Thumbnail

struct AttachmentThumbnail: View {
    let attachment: Attachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailContent
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 0.2, green: 0.2, blue: 0.22))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
        .help(attachment.filename)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                VStack(spacing: 4) {
                    Image(systemName: attachment.isPDF ? "doc.fill" : "doc")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text(attachment.filename.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
