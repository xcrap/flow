import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct ProjectEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProviderRegistry.self) private var providerRegistry
    @Binding var showNewProject: Bool
    @Binding var sidebarVisible: Bool
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
            if let project = activeProject {
                canvasArea(project: project)
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(activeProject?.project.name ?? "AgentFlow")
        .toolbar {
            toolbarContent
        }
        .onAppear {
            setupProviders()
            if let project = activeProject {
                loadConversations(for: project)
                ensureSessionsExist(for: project)
                gitService.configure(rootPath: project.project.rootPath)
            }
        }
        .onChange(of: appState.activeProjectID) {
            // Save conversations for previous project, load for new one
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
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, path in
                appState.createProject(name: name, rootPath: path)
                showNewProject = false
            }
        }
        .onChange(of: sidebarVisible) {
            columnVisibility = sidebarVisible ? .all : .detailOnly
        }
    }

    // MARK: - Provider Setup

    private func setupProviders() {
        if providerRegistry.provider(for: "claude") == nil {
            providerRegistry.register(ClaudeCodeProvider())
        }
        conversationService = ConversationService(registry: providerRegistry)
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvasArea(project: ProjectState) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ProjectCanvasView(projectState: project) { node, isSelected in
                nodePanel(node: node, isSelected: isSelected, project: project)
            }

            // Reset zoom button
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    project.canvasState.zoom = 1.0
                    project.canvasState.offset = .zero
                }
            } label: {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Reset view")
            .padding(12)
        }
    }

    // MARK: - Node Panels

    @ViewBuilder
    private func nodePanel(node: WorkflowNode, isSelected: Bool, project: ProjectState) -> some View {
        switch node.kind {
        case .agent:
            if let conversation = conversations[node.id] {
                AgentNodePanel(
                    node: node,
                    isSelected: isSelected,
                    conversation: conversation,
                    onSend: { text in
                        sendMessage(text, toNode: node.id, in: project)
                    },
                    onModelChange: { model in
                        project.nodes[node.id]?.configuration.modelID = model
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
            }

        case .terminal:
            if let session = terminalSessions[node.id] {
                TerminalNodePanel(
                    node: node,
                    isSelected: isSelected,
                    session: session,
                    onDelete: {
                        project.removeNode(node.id)
                        terminalSessions.removeValue(forKey: node.id)
                    }
                )
            }
        }
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
        let permMode = node.configuration.triggerType ?? "default"

        let workingDir = URL(fileURLWithPath: project.project.rootPath)

        // Use --resume if we have a session ID from a previous conversation
        let sessionID = conversation.sessionID

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
            onComplete: { [weak self] in
                Task { @MainActor in
                    self?.saveConversations()
                }
            }
        )
    }

    // MARK: - Conversation Persistence

    private func loadConversations(for project: ProjectState) {
        let loaded = ConversationPersistence.load(for: project.project.id)
        for (id, conv) in loaded {
            conversations[id] = conv
        }
    }

    private func saveConversations() {
        guard let project = activeProject else { return }
        ConversationPersistence.save(conversations: conversations, for: project.project.id)
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
