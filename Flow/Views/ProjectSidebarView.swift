import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct ProjectSidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProviderRegistry.self) private var providerRegistry
    @Environment(GitStatusService.self) private var gitStatus
    let activeProject: ProjectState?
    let conversations: [UUID: ConversationState]
    let onSelectAgent: (UUID) -> Void
    let onDeleteProject: (UUID) -> Void

    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                projectSection

                if let activeProject {
                    agentSection(for: activeProject)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            Button {
                addProject()
            } label: {
                Label("New Project", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .alert("Rename Project", isPresented: Binding(
            get: { renamingProjectID != nil },
            set: { if !$0 { renamingProjectID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("OK") {
                if let id = renamingProjectID,
                   let index = appState.openProjects.firstIndex(where: { $0.project.id == id }) {
                    appState.openProjects[index].project.name = renameText
                    appState.scheduleSave()
                }
                renamingProjectID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingProjectID = nil
            }
        }
    }

    private var sidebarBackground: some View {
        Color(red: 0.09, green: 0.09, blue: 0.10)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Projects")

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(appState.openProjects, id: \.project.id) { project in
                    projectRow(project)
                }
            }
        }
    }

    private func agentSection(for project: ProjectState) -> some View {
        let agentNodes = project.nodeOrder
            .compactMap { project.nodes[$0] }
            .filter { $0.kind == .agent }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Agents")
                Spacer()
                Text("\(agentNodes.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if agentNodes.isEmpty {
                Text("Add an agent to start a conversation.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground(isSelected: false))
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(agentNodes) { node in
                        agentCard(node: node, isSelected: project.selectedNodeIDs.contains(node.id), nodeNumber: project.nodeNumber(for: node.id))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Agents")
            Text("Choose a project to see its agent activity.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.62))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground(isSelected: false))
        }
    }

    private func projectRow(_ project: ProjectState) -> some View {
        let isSelected = appState.activeProjectID == project.project.id
        let agentCount = project.nodes.values.filter { $0.kind == .agent }.count

        return Button {
            appState.activeProjectID = project.project.id
            appState.sidebarSelection = .project(project.project.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if agentCount > 0 {
                        Text("\(agentCount)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(project.project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.9))
                        .lineLimit(1)
                }

                Text(shortenPath(project.project.rootPath))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                }
            }
            .onAppear {
                gitStatus.startPolling(projectID: project.project.id, rootPath: project.project.rootPath)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renamingProjectID = project.project.id
                renameText = project.project.name
            }

            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.project.rootPath)
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDeleteProject(project.project.id)
            }
        }
    }

    private func agentCard(node: WorkflowNode, isSelected: Bool, nodeNumber: Int? = nil) -> some View {
        let conversation = conversations[node.id]
        let runtimePhase = conversation?.runtimePhase ?? .idle
        let isWorking = runtimePhase.isWorking
        let statusColor = runtimePhase.statusColor
        let previewText = (isWorking ? conversation?.latestRuntimeActivity?.summary : nil)
            ?? (conversation?.latestPreviewText?.isEmpty == false ? conversation?.latestPreviewText : nil)
            ?? "Start a conversation"
        let queuedPromptCount = conversation?.queuedPromptCount ?? 0

        return Button {
            onSelectAgent(node.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(isWorking ? 0.22 : 0.12))
                            .frame(width: 18, height: 18)

                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                    }

                    Capsule(style: .continuous)
                        .fill(statusColor.opacity(isWorking ? 0.35 : 0.10))
                        .frame(width: 2, height: 46)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(previewText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.98))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(relativeTimestamp(conversation?.lastVisibleActivityAt))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    HStack(spacing: 6) {
                        if let nodeNumber {
                            Text("\(nodeNumber)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Text(node.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.24))

                        Text(providerName(for: node.configuration.providerID))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        statusPill(
                            label: conversation?.statusLabel ?? runtimePhase.statusLabel,
                            color: statusColor,
                            isEmphasized: isWorking
                        )

                        if queuedPromptCount > 0 {
                            statusPill(
                                label: queuedPromptCount == 1 ? "1 queued" : "\(queuedPromptCount) queued",
                                color: Color.white.opacity(0.36),
                                isEmphasized: false
                            )
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05),
                        lineWidth: 0.5
                    )
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.38))
    }

    private func statusPill(label: String, color: Color, isEmphasized: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(isEmphasized ? 0.95 : 0.72))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(isEmphasized ? 0.12 : 0.08))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(color.opacity(isEmphasized ? 0.22 : 0.08), lineWidth: 1)
                }
        )
    }

    private func providerName(for providerID: String?) -> String {
        guard let providerID else { return "Unknown" }
        return providerRegistry.provider(for: providerID)?.displayName
            .replacingOccurrences(of: " (OpenAI)", with: "")
            .replacingOccurrences(of: " (via Claude Code)", with: "")
            ?? providerID.capitalized
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the root folder for your project"
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            appState.createProject(name: url.lastPathComponent, rootPath: url.path)
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func relativeTimestamp(_ date: Date?) -> String {
        guard let date else { return "new" }

        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 45 {
            return "now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = hours / 24
        if days < 7 {
            return "\(days)d"
        }

        let weeks = days / 7
        if weeks < 5 {
            return "\(weeks)w"
        }

        let months = days / 30
        return "\(max(1, months))mo"
    }
}
