import SwiftUI
import AFCore
import AFAgent
import AFCanvas
import AFTerminal

struct ProjectEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProviderRegistry.self) private var providerRegistry
    @Environment(GitStatusService.self) private var gitStatus
    @Environment(RuntimeHealthMonitor.self) private var healthMonitor
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("gridVisible") private var gridVisible = true
    @Binding var sidebarVisible: Bool
    @Binding var settingsVisible: Bool
    @Binding var showCommandPalette: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNodePicker = false
    @State private var conversationsByProject: [UUID: [UUID: ConversationState]] = [:]
    @State private var terminalSessionsByProject: [UUID: [UUID: TerminalSession]] = [:]
    @State private var conversationService: ConversationService?
    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var includeUntracked = false
    @State private var canvasViewportSize: CGSize = CGSize(width: 900, height: 700)
    @State private var loadedPersistenceProjectIDs: Set<UUID> = []

    private var activeProject: ProjectState? {
        appState.activeProject
    }

    private var activeGit: GitStatusService.GitInfo {
        guard let id = activeProject?.project.id else { return GitStatusService.GitInfo() }
        return gitStatus.info[id] ?? GitStatusService.GitInfo()
    }

    private var activeConversations: [UUID: ConversationState] {
        guard let activeProject else { return [:] }
        return conversationsByProject[activeProject.project.id] ?? [:]
    }

    var body: some View {
        HStack(spacing: 0) {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectSidebarView(
                activeProject: activeProject,
                conversations: activeConversations,
                onSelectAgent: { nodeID in
                    if let project = activeProject {
                        focusAgentNode(nodeID, in: project)
                    }
                },
                onDeleteProject: deleteProject
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            ZStack {
                if let project = activeProject {
                    if loadedPersistenceProjectIDs.contains(project.project.id) {
                        canvasArea(project: project)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
        .navigationTitle(activeProject?.project.name ?? "Flow")
        .toolbar {
            toolbarContent
        }
        .onAppear {
            setupProviders()
        }
        .task(id: appState.activeProjectID) {
            if let project = activeProject {
                prepareProjectForDisplay(project)
            }
        }
        .onChange(of: appState.activeProjectID) { previousProjectID, _ in
            if let previousProjectID {
                saveConversations(for: previousProjectID)
            }
            appState.scheduleSave()
        }
        .onChange(of: activeProject?.nodes.count) {
            Task { @MainActor in
                if let project = activeProject {
                    ensureSessionsExist(for: project)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if let id = activeProject?.project.id {
                    gitStatus.forceRefresh(projectID: id)
                }
            } else {
                flushAllPersistence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushAllPersistence()
        }
        .sheet(isPresented: $showCommitSheet) {
            commitSheet
        }
        .onChange(of: gridVisible) {
            activeProject?.canvasState.showGrid = gridVisible
        }
        .onChange(of: sidebarVisible) {
            withAnimation {
                columnVisibility = sidebarVisible ? .all : .detailOnly
            }
        }
        .onChange(of: columnVisibility) {
            sidebarVisible = columnVisibility != .detailOnly
        }
        .onDisappear {
            flushAllPersistence()
        }

        if settingsVisible {
            Divider()
            SettingsView(onClose: { settingsVisible = false })
                .frame(width: 420)
                .transition(.move(edge: .trailing))
        }
        }
        .animation(.smooth, value: settingsVisible)
    }

    // MARK: - Provider Setup

    private func setupProviders() {
        let discovery = healthMonitor.discovery

        // Register providers immediately so conversationService is available
        if providerRegistry.provider(for: "claude") == nil {
            providerRegistry.register(ClaudeCodeProvider(discovery: discovery))
        }
        if providerRegistry.provider(for: "codex") == nil {
            providerRegistry.register(CodexProvider(discovery: discovery))
        }
        conversationService = ConversationService(registry: providerRegistry)

        // Register binary specs asynchronously (path resolution + version checks)
        Task {
            await discovery.register(BinarySpec.claude)
            await discovery.register(BinarySpec.codex)
        }
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
                .onAppear {
                    canvasViewportSize = geo.size
                    project.canvasState.viewportSize = geo.size
                }
                .onChange(of: geo.size) { _, newSize in
                    canvasViewportSize = newSize
                    project.canvasState.viewportSize = newSize
                }

                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        if project.canvasState.zoom != 1.0 {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    project.canvasState.resetZoom(in: geo.size)
                                    project.onChange?()
                                }
                            } label: {
                                Text("\(Int(round(project.canvasState.zoom * 100)))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .frame(height: 28)
                            }
                            .buttonStyle(.bordered)
                            .help("Reset zoom (⌘0)")
                        }

                        if project.nodes.count > 1 {
                            Button {
                                tidyUp(project: project, viewportSize: geo.size)
                            } label: {
                                Image(systemName: "rectangle.3.group")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.bordered)
                            .help("Tidy up (⌘G)")
                        }

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
            project.canvasState.resetZoom(in: canvasViewportSize)
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
            settingsVisible.toggle()
        }
    }

    // MARK: - Layout

    private func fitToScreen(project: ProjectState, viewportSize: CGSize) {
        project.fitToScreen(viewportSize: viewportSize)
    }

    private func tidyUp(project: ProjectState, viewportSize: CGSize) {
        project.tidyUp(viewportSize: viewportSize)
    }

    // MARK: - Node Panels

    @ViewBuilder
    private func nodePanel(node: WorkflowNode, isSelected: Bool, isTitleHovered: Bool, project: ProjectState) -> some View {
        let nodeNumber = project.nodeNumber(for: node.id)
        switch node.kind {
        case .agent:
            let projectID = project.project.id
            let conversation = conversationFor(node.id, in: projectID)
            AgentNodePanel(
                    node: node,
                    nodeNumber: nodeNumber,
                    isSelected: isSelected,
                    isTitleHovered: isTitleHovered,
                    conversation: conversation,
                    onProviderChange: { providerID in
                        let previousProviderID = project.nodes[node.id]?.configuration.providerID
                        project.nodes[node.id]?.configuration.providerID = providerID
                        if previousProviderID != providerID {
                            conversation.sessionID = nil
                            conversation.reportedContextWindow = nil
                        }
                        project.onChange?()
                    },
                    onSend: { text, attachments in
                        sendMessage(text, attachments: attachments, toNode: node.id, in: project)
                    },
                    onModelChange: { model in
                        project.nodes[node.id]?.configuration.modelID = model
                        conversation.reportedContextWindow = nil
                        project.onChange?()
                    },
                    onEffortChange: { effort in
                        project.nodes[node.id]?.configuration.effort = effort
                        project.onChange?()
                    },
                    onCancel: {
                        conversationService?.cancelStreaming(for: node.id)
                    },
                    onClearConversation: {
                        clearConversation(nodeID: node.id, in: projectID)
                    },
                    onSystemPromptChange: { prompt in
                        let previousPrompt = project.nodes[node.id]?.configuration.systemPrompt
                        project.nodes[node.id]?.configuration.systemPrompt = prompt
                        if previousPrompt != prompt {
                            conversation.sessionID = nil
                        }
                        project.onChange?()
                    },
                    onModeChange: { mode in
                        project.nodes[node.id]?.configuration.agentMode = mode
                        project.onChange?()
                    },
                    onAccessChange: { access in
                        project.nodes[node.id]?.configuration.agentAccess = access
                        project.onChange?()
                    },
                    onRemoveQueuedPrompt: { index in
                        conversationService?.removeQueuedPrompt(at: index, for: node.id, conversationState: conversation)
                    },
                    onDelete: {
                        project.removeNode(node.id)
                        conversationsByProject[projectID]?.removeValue(forKey: node.id)
                        saveConversations(for: projectID)
                    }
                )

        case .terminal:
            let projectID = project.project.id
            let session = terminalSessionFor(node.id, in: projectID, rootPath: project.project.rootPath)
            TerminalNodePanel(
                node: node,
                nodeNumber: nodeNumber,
                isSelected: isSelected,
                isTitleHovered: isTitleHovered,
                session: session,
                onDelete: {
                    session.shutdown()
                    project.removeNode(node.id)
                    terminalSessionsByProject[projectID]?.removeValue(forKey: node.id)
                    saveConversations(for: projectID)
                }
                )
        }
    }

    private func conversationFor(_ nodeID: UUID, in projectID: UUID) -> ConversationState {
        if let existing = conversationsByProject[projectID]?[nodeID] { return existing }
        let conv = ConversationState(nodeID: nodeID)
        conversationsByProject[projectID, default: [:]][nodeID] = conv
        return conv
    }

    private func terminalSessionFor(_ nodeID: UUID, in projectID: UUID, rootPath: String) -> TerminalSession {
        if let existing = terminalSessionsByProject[projectID]?[nodeID] {
            existing.setLaunchDirectory(rootPath)
            wireTerminalSession(existing, projectID: projectID)
            return existing
        }
        let session = TerminalSession(id: nodeID, currentDirectory: rootPath)
        wireTerminalSession(session, projectID: projectID)
        terminalSessionsByProject[projectID, default: [:]][nodeID] = session
        return session
    }

    private func ensureSessionsExist(for project: ProjectState) {
        let projectID = project.project.id
        let cwd = project.project.rootPath
        for (id, node) in project.nodes {
            switch node.kind {
            case .agent:
                if conversationsByProject[projectID]?[id] == nil {
                    conversationsByProject[projectID, default: [:]][id] = ConversationState(nodeID: id)
                }
            case .terminal:
                if terminalSessionsByProject[projectID]?[id] == nil {
                    let session = TerminalSession(id: id, currentDirectory: cwd)
                    wireTerminalSession(session, projectID: projectID)
                    terminalSessionsByProject[projectID, default: [:]][id] = session
                }
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String, attachments: [Attachment] = [], toNode nodeID: UUID, in project: ProjectState) {
        guard let node = project.nodes[nodeID],
              node.kind == .agent,
              let service = conversationService
        else { return }

        let projectID = project.project.id
        guard let conversation = conversationsByProject[projectID]?[nodeID] else { return }
        let providerID = node.configuration.providerID ?? "claude"
        let model = node.configuration.modelID ?? "sonnet"
        let effort = node.configuration.effort ?? "high"
        let systemPrompt = node.configuration.systemPrompt
        let mode = node.configuration.resolvedMode
        let access = node.configuration.resolvedAccess

        let workingDir = URL(fileURLWithPath: project.project.rootPath)

        // Use --resume if we have a session ID from a previous conversation
        let sessionID = conversation.sessionID

        service.send(
            prompt: text,
            attachments: attachments,
            to: conversation,
            providerID: providerID,
            model: model,
            effort: effort,
            systemPrompt: systemPrompt,
            agentMode: mode,
            agentAccess: access,
            workingDirectory: workingDir,
            resumeSessionID: sessionID,
            onComplete: { [projectID] in
                Task { @MainActor in
                    self.saveConversations(for: projectID)
                }
            }
        )
        saveConversations(for: projectID)
    }

    // MARK: - Conversation Persistence

    private func prepareProjectForDisplay(_ project: ProjectState) {
        appState.sidebarSelection = .project(project.project.id)
        project.canvasState.showGrid = gridVisible
        loadConversations(for: project)
        ensureSessionsExist(for: project)
        gitStatus.startPolling(projectID: project.project.id, rootPath: project.project.rootPath)
    }

    private func loadConversations(for project: ProjectState) {
        let projectID = project.project.id
        guard !loadedPersistenceProjectIDs.contains(projectID) else { return }

        var conversations = conversationsByProject[projectID] ?? [:]
        for (nodeID, persistedState) in ConversationPersistence.loadConversations(for: projectID) {
            if let existingState = conversations[nodeID] {
                hydrate(existingState, with: persistedState)
            } else {
                conversations[nodeID] = persistedState
            }
        }
        conversationsByProject[projectID] = conversations

        var terminalSessions = terminalSessionsByProject[projectID] ?? [:]
        for (nodeID, persistedSession) in ConversationPersistence.loadTerminals(
            for: projectID,
            rootPath: project.project.rootPath
        ) {
            if let existingSession = terminalSessions[nodeID] {
                hydrate(existingSession, with: persistedSession, rootPath: project.project.rootPath)
                wireTerminalSession(existingSession, projectID: projectID)
            } else {
                persistedSession.setLaunchDirectory(project.project.rootPath)
                wireTerminalSession(persistedSession, projectID: projectID)
                terminalSessions[nodeID] = persistedSession
            }
        }
        terminalSessionsByProject[projectID] = terminalSessions

        loadedPersistenceProjectIDs.insert(projectID)
    }

    private func saveConversations(for projectID: UUID, flushProjectState: Bool = true) {
        guard let project = appState.openProjects.first(where: { $0.project.id == projectID }) else { return }
        loadConversations(for: project)
        if flushProjectState {
            appState.flushSaveNow()
        }
        ConversationPersistence.save(
            conversations: conversationsByProject[projectID] ?? [:],
            terminals: terminalSessionsByProject[projectID] ?? [:],
            for: project.project.id
        )
    }

    private func flushAllPersistence() {
        appState.flushSaveNow()

        let loadedProjectIDs = Set(conversationsByProject.keys).union(terminalSessionsByProject.keys)
        for projectID in loadedProjectIDs {
            saveConversations(for: projectID, flushProjectState: false)
        }
    }

    private func clearConversation(nodeID: UUID, in projectID: UUID) {
        conversationService?.clearPendingRequests(for: nodeID)
        conversationService?.cancelStreaming(for: nodeID)
        conversationFor(nodeID, in: projectID).resetConversation()
        saveConversations(for: projectID)
    }

    private func centerCanvas(on node: WorkflowNode, in project: ProjectState, animated: Bool = true) {
        let updateCanvas = {
            project.canvasState.center(on: node.position.point, in: canvasViewportSize)
        }

        if animated {
            withAnimation(.spring(duration: 0.35)) {
                updateCanvas()
            }
        } else {
            updateCanvas()
        }

        project.onChange?()
    }

    private func focusAgentNode(_ nodeID: UUID, in project: ProjectState) {
        guard let node = project.nodes[nodeID] else { return }
        project.selectedNodeIDs = [nodeID]
        project.selectedConnectionIDs.removeAll()
        project.bringToFront(nodeID)
        centerCanvas(on: node, in: project)
    }

    private func deleteProject(_ projectID: UUID) {
        if let nodeIDs = conversationsByProject[projectID]?.keys {
            for nodeID in nodeIDs {
                conversationService?.clearPendingRequests(for: nodeID)
                conversationService?.cancelStreaming(for: nodeID)
            }
        }

        if let terminalSessions = terminalSessionsByProject[projectID]?.values {
            for session in terminalSessions {
                session.shutdown()
            }
        }

        // Stop git polling for the deleted project
        gitStatus.stopPolling(projectID: projectID)

        conversationsByProject.removeValue(forKey: projectID)
        terminalSessionsByProject.removeValue(forKey: projectID)
        loadedPersistenceProjectIDs.remove(projectID)
        ConversationPersistence.delete(for: projectID)
        appState.deleteProject(projectID)
    }

    private func hydrate(_ target: ConversationState, with persisted: ConversationState) {
        target.messages = persisted.messages
        target.runtimeActivities = persisted.runtimeActivities
        target.runtimePhase = .idle
        target.streamingText = ""
        target.error = nil
        target.sessionID = persisted.sessionID
        target.activeProviderID = persisted.activeProviderID
        target.activeModelID = persisted.activeModelID
        target.activeTurnID = nil
        target.lastStopReason = nil
        target.lastRuntimeEventAt = persisted.lastActivityAt
        target.totalCostUSD = persisted.totalCostUSD
        target.totalInputTokens = persisted.totalInputTokens
        target.totalOutputTokens = persisted.totalOutputTokens
        target.totalCachedInputTokens = persisted.totalCachedInputTokens
        target.totalReasoningOutputTokens = persisted.totalReasoningOutputTokens
        target.totalTokens = persisted.totalTokens
        target.reportedContextWindow = persisted.reportedContextWindow
        target.currentContextTokens = persisted.currentContextTokens
        target.clearQueuedPrompts()
    }

    private func hydrate(_ target: TerminalSession, with persisted: TerminalSession, rootPath: String) {
        target.setLaunchDirectory(rootPath)
        target.setPersistedTranscript(persisted.snapshotTranscript())
        if !target.isRunning {
            target.currentDirectory = persisted.currentDirectory
        }
    }

    private func wireTerminalSession(_ session: TerminalSession, projectID: UUID) {
        session.onChange = { [projectID] in
            Task { @MainActor in
                guard self.loadedPersistenceProjectIDs.contains(projectID) else { return }
                self.saveConversations(for: projectID)
            }
        }
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
                        centerCanvas(on: node, in: project)
                    }
                    showNodePicker = false
                }
            }
        }

        // Git status
        if activeGit.isGitRepo {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(activeGit.branch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if activeGit.statusFileCount > 0 {
                        Text("\(activeGit.statusFileCount)")
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
                .disabled(activeGit.statusFileCount == 0)

                Button {
                    if let id = activeProject?.project.id {
                        Task { _ = await gitStatus.push(projectID: id) }
                    }
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                }

                Button {
                    if let id = activeProject?.project.id {
                        gitStatus.forceRefresh(projectID: id)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Commit Sheet

    private var commitSheet: some View {
        let trackedFiles = activeGit.files.filter { !$0.isUntracked }
        let untrackedFiles = activeGit.files.filter { $0.isUntracked }
        let commitFileCount = includeUntracked ? activeGit.statusFileCount : trackedFiles.count

        return VStack(alignment: .leading, spacing: 16) {
            Text("Commit Changes")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            // File list
            if !activeGit.files.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !trackedFiles.isEmpty {
                            ForEach(trackedFiles) { file in
                                fileRow(file)
                            }
                        }

                        if !untrackedFiles.isEmpty {
                            HStack(spacing: 8) {
                                Toggle("Include untracked files", isOn: $includeUntracked)
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("\(untrackedFiles.count) file(s)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            if includeUntracked {
                                ForEach(untrackedFiles) { file in
                                    fileRow(file)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Text("\(commitFileCount) file(s) will be committed")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showCommitSheet = false
                    commitMessage = ""
                    includeUntracked = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Commit") {
                    Task {
                        if let id = activeProject?.project.id {
                            _ = await gitStatus.commit(projectID: id, message: commitMessage, includeUntracked: includeUntracked)
                        }
                        commitMessage = ""
                        includeUntracked = false
                        showCommitSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commitMessage.isEmpty || commitFileCount == 0)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func fileRow(_ file: GitStatusService.FileStatus) -> some View {
        HStack(spacing: 8) {
            Text(file.status)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(fileStatusColor(file.status))
                .frame(width: 22, alignment: .center)
            Text(file.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }

    private func fileStatusColor(_ status: String) -> Color {
        switch status {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        case "??": return .blue
        case "R": return .purple
        default: return .secondary
        }
    }
}
