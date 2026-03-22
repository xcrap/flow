import SwiftUI
import AFCore
import AFCanvas

struct ProjectSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.sidebarSelection) {
            Section("Projects") {
                ForEach(appState.openProjects, id: \.project.id) { project in
                    projectRow(project)
                        .tag(SidebarItem.project(project.project.id))
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
                                appState.deleteProject(project.project.id)
                            }
                        }
                }
            }
        }
        .onChange(of: appState.sidebarSelection) { _, newValue in
            if case .project(let id) = newValue {
                appState.activeProjectID = id
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                addProject()
            } label: {
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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

    @ViewBuilder
    private func projectRow(_ project: ProjectState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(project.project.name, systemImage: "folder.fill")

            HStack(spacing: 8) {
                Text(shortenPath(project.project.rootPath))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                let agentCount = project.nodes.values.filter { $0.kind == .agent }.count
                let terminalCount = project.nodes.values.filter { $0.kind == .terminal }.count

                if agentCount > 0 {
                    Text("\(agentCount) agent\(agentCount > 1 ? "s" : "")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if terminalCount > 0 {
                    Text("\(terminalCount) term\(terminalCount > 1 ? "s" : "")")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
