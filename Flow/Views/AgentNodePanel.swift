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
    var onModeChange: (AgentMode) -> Void
    var onAccessChange: (AgentAccess) -> Void
    var onContextWindowChange: (Int?) -> Void
    var onRemoveQueuedPrompt: (Int) -> Void
    var onDelete: () -> Void

    @State private var inputText = ""
    @State private var selectedProvider: String
    @State private var selectedModel: String
    @State private var selectedEffort: String
    @State private var showSettings = false
    @State private var systemPromptText: String
    @State private var agentMode: AgentMode
    @State private var agentAccess: AgentAccess
    @State private var selectedContextWindow: Int?
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
        onModeChange: @escaping (AgentMode) -> Void,
        onAccessChange: @escaping (AgentAccess) -> Void,
        onContextWindowChange: @escaping (Int?) -> Void,
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
        self.onModeChange = onModeChange
        self.onAccessChange = onAccessChange
        self.onContextWindowChange = onContextWindowChange
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
        _agentMode = State(initialValue: node.configuration.resolvedMode)
        _agentAccess = State(initialValue: node.configuration.resolvedAccess)
        _selectedContextWindow = State(initialValue: node.configuration.contextWindowSize)
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
        .geometryGroup()
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
            agentMode = node.configuration.resolvedMode
            agentAccess = node.configuration.resolvedAccess
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
        VerticalOnlyScrollView(
            scrollToBottomTrigger: conversation.messages.count
                + conversation.runtimeActivities.count
                + (conversation.isStreaming ? 1 : 0)
        ) {
            VStack(alignment: .leading, spacing: 16) {
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

    private var isRecoverableError: Bool {
        guard let error = conversation.error else { return false }
        let nonRecoverable = ["not found", "Install with", "Configure it in Settings", "Failed to start"]
        return !nonRecoverable.contains(where: { error.contains($0) })
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 8) {
                if isRecoverableError, conversation.sessionID != nil {
                    Button {
                        conversation.dismissError()
                        onSend("continue", [])
                    } label: {
                        Label("Resume session", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
                } else if isRecoverableError, let lastPrompt = conversation.latestUserPrompt {
                    Button {
                        conversation.dismissError()
                        onSend(lastPrompt, [])
                    } label: {
                        Label("Retry", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
                }

                Button {
                    conversation.dismissError()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.secondary)
            }
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
        // User-configured context window takes precedence
        if let configured = selectedContextWindow {
            return configured
        }

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
        InputBarView(
            inputText: $inputText,
            inputFocused: $inputFocused,
            isStreaming: conversation.isStreaming,
            hasAttachments: !conversation.pendingAttachments.isEmpty,
            hasPendingInput: !conversation.pendingAttachments.isEmpty,
            selectedProvider: selectedProvider,
            selectedProviderName: selectedProviderName,
            selectedModel: selectedModel,
            selectedModelName: selectedModelName,
            showSettings: $showSettings,
            systemPromptText: systemPromptText,
            agentMode: agentMode,
            agentAccess: agentAccess,
            selectedEffort: selectedEffort,
            providerOptions: providerOptions,
            availableModels: availableModels,
            attachmentStrip: !conversation.pendingAttachments.isEmpty ? AnyView(attachmentStrip) : nil,
            settingsPopover: AnyView(settingsPopover),
            onSend: { send() },
            onCancel: onCancel,
            onSelectProvider: { selectProvider($0) },
            onModelChange: { id in
                selectedModel = id
                onModelChange(id)
            },
            onOpenFilePicker: { openFilePicker() },
            onPaste: { handlePastedItems($0) }
        )
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
                let modeOptions: [(AgentMode, String)] = [
                    (.auto, "Auto (default)"),
                    (.plan, "Plan"),
                ]
                ForEach(modeOptions, id: \.0) { mode, name in
                    Button {
                        agentMode = mode
                        onModeChange(mode)
                    } label: {
                        HStack(spacing: 8) {
                            if mode == agentMode {
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
                let accessOptions: [(AgentAccess, String)] = [
                    (.supervised, "Supervised"),
                    (.acceptEdits, "Accept Edits"),
                    (.fullAccess, "Full access"),
                ]
                ForEach(accessOptions, id: \.0) { access, name in
                    Button {
                        agentAccess = access
                        onAccessChange(access)
                    } label: {
                        HStack(spacing: 8) {
                            if access == agentAccess {
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

            // Context Window
            VStack(alignment: .leading, spacing: 6) {
                Text("Context Window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                let model = availableModels.first(where: { $0.id == selectedModel })
                let options = model?.availableContextWindows ?? [200_000]
                let defaultWindow = model?.contextWindow ?? 200_000

                ForEach(options, id: \.self) { size in
                    let isSelected = (selectedContextWindow ?? defaultWindow) == size
                    Button {
                        selectedContextWindow = size
                        onContextWindowChange(size)
                    } label: {
                        HStack(spacing: 8) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16)
                            }
                            Text(Self.formatContextWindow(size) + (size == defaultWindow ? " (default)" : ""))
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

    private static func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000
            return m.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(m))M"
                : String(format: "%.1fM", m)
        } else {
            return "\(tokens / 1_000)K"
        }
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
            if let mode = arg, let parsed = AgentMode(rawValue: mode) {
                agentMode = parsed
                onModeChange(parsed)
            }
        case "/access":
            if let access = arg, let parsed = AgentAccess(rawValue: access) {
                agentAccess = parsed
                onAccessChange(parsed)
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
                            Text(code)
                                .font(.system(size: 12, design: .monospaced))
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .clipped()
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
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .clipped()
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

// MARK: - Isolated Input Bar (Performance)

/// Extracted input bar view that isolates the TextField from the parent's @Observable
/// conversation state. This prevents every keystroke from triggering a full
/// AgentNodePanel re-render caused by the @Bindable conversation dependency chain.
private struct InputBarView: View {
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    let isStreaming: Bool
    let hasAttachments: Bool
    let hasPendingInput: Bool
    let selectedProvider: String
    let selectedProviderName: String
    let selectedModel: String
    let selectedModelName: String
    @Binding var showSettings: Bool
    let systemPromptText: String
    let agentMode: AgentMode
    let agentAccess: AgentAccess
    let selectedEffort: String
    let providerOptions: [(id: String, name: String)]
    let availableModels: [AIModel]
    let attachmentStrip: AnyView?
    let settingsPopover: AnyView
    let onSend: () -> Void
    let onCancel: () -> Void
    let onSelectProvider: (String) -> Void
    let onModelChange: (String) -> Void
    let onOpenFilePicker: () -> Void
    let onPaste: ([NSItemProvider]) -> Void

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasPendingInput
    }

    private var placeholder: String {
        isStreaming ? "Add to queue..." : "Ask for follow-up changes or attach images"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let attachmentStrip {
                attachmentStrip
            }

            PromptTextField(text: $inputText, placeholder: placeholder, inputFocused: inputFocused, onSend: onSend, onPaste: onPaste)

            HStack(spacing: 6) {
                Button {
                    onOpenFilePicker()
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
                            onSelectProvider(provider.id)
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
                        .foregroundStyle(!systemPromptText.isEmpty || agentMode != .auto || agentAccess != .fullAccess || selectedEffort != "high" ? .purple : .white.opacity(0.45))
                        .frame(width: 28, height: 24)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings) {
                    settingsPopover
                }

                Spacer()

                if isStreaming {
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
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? Color.accentColor : .white.opacity(0.15))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(isStreaming ? "Queue prompt" : "Send")
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
}

/// Minimal TextField wrapper — only re-renders when text or placeholder changes.
/// Fully isolated from conversation @Observable state.
private struct PromptTextField: View {
    @Binding var text: String
    let placeholder: String
    var inputFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onPaste: ([NSItemProvider]) -> Void

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineSpacing(3)
            .lineLimit(2...8)
            .focused(inputFocused)
            .onKeyPress(.return, phases: .down) { keyPress in
                if keyPress.modifiers.isEmpty {
                    onSend()
                    return .handled
                }
                return .ignored
            }
            .onPasteCommand(of: [.image, .png, .jpeg, .gif, .tiff, .heic]) { providers in
                onPaste(providers)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }
}

// MARK: - Vertical-Only Scroll View (AppKit-backed)

/// Replaces SwiftUI's ScrollView(.vertical) with a fully controlled NSScrollView.
/// SwiftUI's ScrollView on macOS allows horizontal bounce/elasticity from:
/// 1) Default NSScrollView horizontal elasticity
/// 2) Nested NSScrollViews created by .textSelection(.enabled) on Text views
/// This custom view creates its own NSScrollView with horizontal scrolling completely
/// disabled, and pins the document view width to the clip view to prevent overflow.
/// Also implements "stick to bottom" auto-scrolling for chat-style content.
private struct VerticalOnlyScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let scrollToBottomTrigger: Int

    init(scrollToBottomTrigger: Int, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.scrollToBottomTrigger = scrollToBottomTrigger
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = _VerticalOnlyNSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        // Replace default clip view with one that blocks horizontal movement
        let clipView = _VerticalOnlyClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let documentView = _FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        context.coordinator.setupObservers()

        // Initial scroll to bottom (deferred so layout completes first)
        DispatchQueue.main.async {
            context.coordinator.scrollToBottom(animated: false)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content

        // Re-enforce horizontal bounce disable on the outer scroll view
        // and recursively patch any nested NSScrollViews from .textSelection(.enabled)
        DispatchQueue.main.async {
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasHorizontalScroller = false
            Self.patchNestedScrollViews(in: scrollView)
        }

        // Scroll to bottom when trigger changes (new messages, streaming start).
        if scrollToBottomTrigger != context.coordinator.lastScrollTrigger {
            context.coordinator.lastScrollTrigger = scrollToBottomTrigger
            context.coordinator.isAtBottom = true
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom(animated: true)
            }
        } else if context.coordinator.isAtBottom {
            // During streaming, content grows but the trigger stays constant.
            // Scroll after the hosting view lays out the new content.
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom(animated: false)
            }
        }
    }

    private static func patchNestedScrollViews(in view: NSView) {
        for child in view.subviews {
            if let sv = child as? NSScrollView {
                sv.hasHorizontalScroller = false
                sv.horizontalScrollElasticity = .none
            }
            patchNestedScrollViews(in: child)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        var lastScrollTrigger = 0
        var isAtBottom = true
        private var isAnimatingScroll = false
        nonisolated(unsafe) private var eventMonitor: Any?

        func setupObservers() {
            guard let scrollView else { return }

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            scrollView.documentView?.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(documentFrameDidChange),
                name: NSView.frameDidChangeNotification,
                object: scrollView.documentView
            )

            // Install local event monitor to intercept scroll wheel events and
            // zero out ALL horizontal deltas before they reach any NSScrollView
            // (outer or nested from .textSelection(.enabled)).
            // Uses AppKit hit testing instead of coordinate conversion to
            // correctly handle .scaleEffect() canvas zoom transforms.
            weak var weakSV = scrollView
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard let sv = weakSV else { return event }
                guard let window = event.window, window === sv.window else { return event }

                // Hit test to check if the event targets our scroll view or any descendant
                guard let hitView = window.contentView?.hitTest(event.locationInWindow),
                      hitView === sv || hitView.isDescendant(of: sv) else { return event }

                // Zero out ALL horizontal scroll deltas unconditionally via CGEvent
                guard let cgEvent = event.cgEvent?.copy() else { return event }
                cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
                cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)

                return NSEvent(cgEvent: cgEvent) ?? event
            }
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            // Skip during programmatic scroll animations — the intermediate
            // positions would incorrectly set isAtBottom = false
            guard !isAnimatingScroll else { return }
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let maxY = documentView.frame.height - scrollView.contentView.bounds.height
            let currentY = scrollView.contentView.bounds.origin.y
            isAtBottom = currentY >= maxY - 20
        }

        @objc private func documentFrameDidChange(_ notification: Notification) {
            if isAtBottom {
                scrollToBottom(animated: false)
            }
        }

        func scrollToBottom(animated: Bool) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let maxY = documentView.frame.height - scrollView.contentView.bounds.height
            guard maxY > 0 else { return }
            let point = NSPoint(x: 0, y: maxY)
            isAnimatingScroll = true
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(point)
                } completionHandler: { [weak self] in
                    self?.isAnimatingScroll = false
                    self?.isAtBottom = true
                }
            } else {
                scrollView.contentView.scroll(to: point)
                isAnimatingScroll = false
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isAtBottom = true
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class _FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// NSScrollView subclass that strips horizontal deltas from all scroll wheel events.
private final class _VerticalOnlyNSScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let cgEvent = event.cgEvent?.copy() else {
            super.scrollWheel(with: event)
            return
        }
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        if let modified = NSEvent(cgEvent: cgEvent) {
            super.scrollWheel(with: modified)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// NSClipView subclass that physically prevents horizontal scroll position changes.
/// Even if a nested scroll view or SwiftUI's internal gesture handling tries to
/// move content horizontally, the clip view's origin.x stays at 0.
private final class _VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }
}
