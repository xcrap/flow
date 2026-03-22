import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct ProjectEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProviderRegistry.self) private var providerRegistry
    @Binding var sidebarVisible: Bool
    @Binding var showCommandPalette: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNodePicker = false
    @State private var conversations: [UUID: ConversationState] = [:]
    @State private var terminalSessions: [UUID: TerminalSession] = [:]
    @State private var conversationService: ConversationService?
    @State private var gitService = GitService()
    @State private var showCommitSheet = false
    @State private var commitMessage = ""

    private var activeProject: ProjectState? {
        appState.activeProject
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            ZStack {
                if let project = activeProject {
                    canvasArea(project: project)
                } else {
                    WelcomeView()
                }

                if showCommandPalette {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    CommandPaletteView(isPresented: $showCommandPalette) { action in
                        handleCommandAction(action)
                    }
                }
            }
        }
        .navigationTitle(activeProject?.project.name ?? "AgentFlow")
        .toolbar {
            toolbarContent
        }
        .onAppear {
            setupProviders()
            if let project = activeProject {
                // Set sidebar selection to match active project
                appState.sidebarSelection = .project(project.project.id)
                loadConversations(for: project)
                ensureSessionsExist(for: project)
                gitService.configure(rootPath: project.project.rootPath)
            }
        }
        .onChange(of: appState.activeProjectID) {
            // Save before switching
            saveConversations()
            appState.scheduleSave()

            if let project = activeProject {
                loadConversations(for: project)
                ensureSessionsExist(for: project)
                gitService.configure(rootPath: project.project.rootPath)
            }
        }
        .onChange(of: activeProject?.nodes.count) {
            Task { @MainActor in
                if let project = activeProject {
                    ensureSessionsExist(for: project)
                }
            }
        }
        .sheet(isPresented: $showCommitSheet) {
            commitSheet
        }
        .onChange(of: sidebarVisible) {
            withAnimation {
                columnVisibility = sidebarVisible ? .all : .detailOnly
            }
        }
        .onChange(of: columnVisibility) {
            sidebarVisible = columnVisibility != .detailOnly
        }
    }

    // MARK: - Provider Setup

    private func setupProviders() {
        if providerRegistry.provider(for: "claude") == nil {
            providerRegistry.register(ClaudeCodeProvider())
        }
        if providerRegistry.provider(for: "codex") == nil {
            providerRegistry.register(CodexProvider())
        }
        conversationService = ConversationService(registry: providerRegistry)
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvasArea(project: ProjectState) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ProjectCanvasView(projectState: project) { node, isSelected, isTitleHovered in
                    nodePanel(node: node, isSelected: isSelected, isTitleHovered: isTitleHovered, project: project)
                }
                .id(project.project.id) // Force full recreation on project switch

                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            tidyUp(project: project, viewportSize: geo.size)
                        } label: {
                            Image(systemName: "rectangle.3.group")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("Tidy up")

                        Button {
                            fitToScreen(project: project, viewportSize: geo.size)
                        } label: {
                            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .help("Fit to screen")
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Command Palette

    private func handleCommandAction(_ action: CommandAction) {
        guard let project = activeProject else { return }

        switch action {
        case .addAgent:
            let pos = nextNodePosition(in: project, kind: .agent)
            project.addNode(kind: .agent, title: "AI Agent", at: pos)
        case .addTerminal:
            let pos = nextNodePosition(in: project, kind: .terminal)
            project.addNode(kind: .terminal, title: "Terminal", at: pos)
        case .fitToScreen:
            fitToScreen(project: project, viewportSize: CGSize(width: 800, height: 600))
        case .tidyUp:
            tidyUp(project: project, viewportSize: CGSize(width: 800, height: 600))
        case .zoomIn:
            project.canvasState.zoom = min(3.0, project.canvasState.zoom + 0.25)
        case .zoomOut:
            project.canvasState.zoom = max(0.1, project.canvasState.zoom - 0.25)
        case .resetZoom:
            project.canvasState.zoom = 1.0
            project.canvasState.offset = .zero
        case .newProject:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose the root folder for your project"
            panel.prompt = "Select Folder"
            if panel.runModal() == .OK, let url = panel.url {
                appState.createProject(name: url.lastPathComponent, rootPath: url.path)
            }
        case .toggleSidebar:
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Layout

    private func fitToScreen(project: ProjectState, viewportSize: CGSize) {
        guard !project.nodes.isEmpty else { return }

        let nodes = Array(project.nodes.values)

        // Calculate bounding box of all nodes
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity

        for node in nodes {
            minX = min(minX, node.position.x - node.position.width / 2)
            minY = min(minY, node.position.y - node.position.height / 2)
            maxX = max(maxX, node.position.x + node.position.width / 2)
            maxY = max(maxY, node.position.y + node.position.height / 2)
        }

        let contentWidth = max(1, maxX - minX)
        let contentHeight = max(1, maxY - minY)
        let padding: Double = 60

        // Zoom to fit all content with padding
        let availW = max(1, viewportSize.width - padding * 2)
        let availH = max(1, viewportSize.height - padding * 2)
        let newZoom = max(0.15, min(1.5, min(availW / contentWidth, availH / contentHeight)))

        // Center of all nodes in canvas space
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2

        // Offset so that canvas center maps to screen center
        // screen = canvas * zoom + offset → offset = screenCenter - canvasCenter * zoom
        let newOffsetX = viewportSize.width / 2 - cx * newZoom
        let newOffsetY = viewportSize.height / 2 - cy * newZoom

        withAnimation(.spring(duration: 0.4)) {
            project.canvasState.zoom = newZoom
            project.canvasState.offset = CGPoint(x: newOffsetX, y: newOffsetY)
        }
        project.onChange?()
    }

    private func tidyUp(project: ProjectState, viewportSize: CGSize) {
        // Sort by creation order (position on canvas: left-to-right, top-to-bottom)
        let sortedNodes = project.nodes.values.sorted {
            if abs($0.position.y - $1.position.y) < 100 {
                return $0.position.x < $1.position.x
            }
            return $0.position.y < $1.position.y
        }
        guard !sortedNodes.isEmpty else { return }

        let gap: Double = 20
        let columns = max(1, Int(ceil(sqrt(Double(sortedNodes.count)))))

        withAnimation(.spring(duration: 0.5)) {
            // Place nodes in a grid, using each node's actual size
            var cursorX: Double = 0
            var cursorY: Double = 0
            var rowHeight: Double = 0

            for (index, node) in sortedNodes.enumerated() {
                let col = index % columns

                if col == 0 && index > 0 {
                    // New row
                    cursorX = 0
                    cursorY += rowHeight + gap
                    rowHeight = 0
                }

                let w = node.position.width
                let h = node.position.height

                project.nodes[node.id]?.position.x = cursorX + w / 2
                project.nodes[node.id]?.position.y = cursorY + h / 2

                cursorX += w + gap
                rowHeight = max(rowHeight, h)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            fitToScreen(project: project, viewportSize: viewportSize)
        }
    }

    // MARK: - Node Panels

    @ViewBuilder
    private func nodePanel(node: WorkflowNode, isSelected: Bool, isTitleHovered: Bool, project: ProjectState) -> some View {
        switch node.kind {
        case .agent:
            let conversation = conversationFor(node.id)
            AgentNodePanel(
                    node: node,
                    isSelected: isSelected,
                    isTitleHovered: isTitleHovered,
                    conversation: conversation,
                    onSend: { text in
                        sendMessage(text, toNode: node.id, in: project)
                    },
                    onModelChange: { model in
                        project.nodes[node.id]?.configuration.modelID = model
                        // Auto-detect provider from model
                        let codexModels = ["gpt-5.4", "o3", "o4-mini"]
                        project.nodes[node.id]?.configuration.providerID = codexModels.contains(model) ? "codex" : "claude"
                    },
                    onEffortChange: { effort in
                        project.nodes[node.id]?.configuration.effort = effort
                    },
                    onCancel: {
                        conversationService?.cancelStreaming(for: node.id)
                    },
                    onSystemPromptChange: { prompt in
                        project.nodes[node.id]?.configuration.systemPrompt = prompt
                    },
                    onPermissionModeChange: { mode in
                        project.nodes[node.id]?.configuration.triggerType = mode
                    },
                    onDelete: {
                        project.removeNode(node.id)
                        conversations.removeValue(forKey: node.id)
                    }
                )

        case .terminal:
            let session = terminalSessionFor(node.id, rootPath: project.project.rootPath)
            TerminalNodePanel(
                node: node,
                isSelected: isSelected,
                isTitleHovered: isTitleHovered,
                session: session,
                onSave: { [self] in saveConversations() },
                onDelete: {
                    project.removeNode(node.id)
                    terminalSessions.removeValue(forKey: node.id)
                }
                )
        }
    }

    private func conversationFor(_ nodeID: UUID) -> ConversationState {
        if let existing = conversations[nodeID] { return existing }
        let conv = ConversationState(nodeID: nodeID)
        conversations[nodeID] = conv
        return conv
    }

    private func terminalSessionFor(_ nodeID: UUID, rootPath: String) -> TerminalSession {
        if let existing = terminalSessions[nodeID] { return existing }
        let session = TerminalSession(id: nodeID, currentDirectory: rootPath)
        terminalSessions[nodeID] = session
        return session
    }

    private func ensureSessionsExist(for project: ProjectState) {
        let cwd = project.project.rootPath
        for (id, node) in project.nodes {
            switch node.kind {
            case .agent:
                if conversations[id] == nil {
                    conversations[id] = ConversationState(nodeID: id)
                }
            case .terminal:
                if terminalSessions[id] == nil {
                    terminalSessions[id] = TerminalSession(id: id, currentDirectory: cwd)
                }
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String, toNode nodeID: UUID, in project: ProjectState) {
        guard let node = project.nodes[nodeID],
              node.kind == .agent,
              let service = conversationService
        else { return }

        guard let conversation = conversations[nodeID] else { return }
        let providerID = node.configuration.providerID ?? "claude"
        let model = node.configuration.modelID ?? "sonnet"
        let effort = node.configuration.effort ?? "high"
        let systemPrompt = node.configuration.systemPrompt
        let permMode = node.configuration.triggerType ?? "auto"

        let workingDir = URL(fileURLWithPath: project.project.rootPath)

        // Use --resume if we have a session ID from a previous conversation
        let sessionID = conversation.sessionID

        // Save immediately so user message is persisted
        saveConversations()

        service.send(
            prompt: text,
            to: conversation,
            providerID: providerID,
            model: model,
            effort: effort,
            systemPrompt: systemPrompt,
            permissionMode: permMode,
            workingDirectory: workingDir,
            resumeSessionID: sessionID,
            onComplete: { [saveConversations] in
                Task { @MainActor in
                    saveConversations()
                }
            }
        )
    }

    // MARK: - Conversation Persistence

    private func loadConversations(for project: ProjectState) {
        let loadedConvs = ConversationPersistence.loadConversations(for: project.project.id)
        for (id, conv) in loadedConvs {
            conversations[id] = conv
        }
        let loadedTerms = ConversationPersistence.loadTerminals(for: project.project.id, rootPath: project.project.rootPath)
        for (id, session) in loadedTerms {
            terminalSessions[id] = session
        }
    }

    private func saveConversations() {
        guard let project = activeProject else { return }
        ConversationPersistence.save(conversations: conversations, terminals: terminalSessions, for: project.project.id)
    }

    // MARK: - Node Positioning

    private func nextNodePosition(in project: ProjectState, kind: NodeKind) -> CGPoint {
        let size = WorkflowNode.defaultSize(for: kind)
        let padding: Double = 40

        if project.nodes.isEmpty {
            // First node: center of visible area, below toolbar
            let canvas = project.canvasState
            return canvas.screenToCanvas(CGPoint(x: 300 + size.width / 2, y: 80 + size.height / 2))
        }

        // Find rightmost edge of existing nodes
        var maxRight: Double = -Double.infinity
        var yAtMaxRight: Double = 0
        for node in project.nodes.values {
            let right = node.position.x + node.position.width / 2
            if right > maxRight {
                maxRight = right
                yAtMaxRight = node.position.y
            }
        }

        // Place to the right of the rightmost node
        return CGPoint(
            x: maxRight + padding + size.width / 2,
            y: yAtMaxRight
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showNodePicker = true
            } label: {
                Label("Add Node", systemImage: "plus.circle")
            }
            .popover(isPresented: $showNodePicker) {
                NodePickerView { kind, title in
                    if let project = activeProject {
                        let position = nextNodePosition(in: project, kind: kind)
                        let node = project.addNode(kind: kind, title: title, at: position)
                        // Center canvas on new node
                        withAnimation(.spring(duration: 0.3)) {
                            project.canvasState.offset = CGPoint(
                                x: -node.position.x * project.canvasState.zoom + 400,
                                y: -node.position.y * project.canvasState.zoom + 350
                            )
                        }
                    }
                    showNodePicker = false
                }
            }
        }

        // Git status
        if gitService.isGitRepo {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(gitService.branch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if gitService.changedFiles > 0 {
                        Text("\(gitService.changedFiles)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                    }
                }

                Button {
                    showCommitSheet = true
                } label: {
                    Label("Commit", systemImage: "checkmark.circle")
                }
                .disabled(gitService.changedFiles == 0)

                Button {
                    Task { _ = await gitService.push() }
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                }

                Button {
                    gitService.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Commit Sheet

    private var commitSheet: some View {
        VStack(spacing: 16) {
            Text("Commit Changes")
                .font(.headline)

            Text("\(gitService.changedFiles) file(s) changed")
                .foregroundStyle(.secondary)

            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .lineLimit(3...6)

            HStack {
                Button("Cancel") {
                    showCommitSheet = false
                    commitMessage = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Commit") {
                    Task {
                        _ = await gitService.commit(message: commitMessage)
                        commitMessage = ""
                        showCommitSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commitMessage.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
