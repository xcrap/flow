import SwiftUI
import AFCore
import AFCanvas

struct ProjectSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showNewProject = false

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.sidebarSelection) {
            Section("Projects") {
                ForEach(appState.openProjects, id: \.project.id) { project in
                    projectRow(project)
                        .tag(SidebarItem.project(project.project.id))
                        .contextMenu {
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
                showNewProject = true
            } label: {
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { name, path in
                appState.createProject(name: name, rootPath: path)
                showNewProject = false
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: ProjectState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(project.project.name, systemImage: "folder.fill")
            Text(shortenPath(project.project.rootPath))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    var onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var selectedPath = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.headline)

            Form {
                TextField("Name", text: $name)

                HStack {
                    Text(selectedPath.isEmpty ? "No folder selected" : shortenPath(selectedPath))
                        .foregroundStyle(selectedPath.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Choose...") {
                        pickFolder()
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let projectName = name.isEmpty ? URL(fileURLWithPath: selectedPath).lastPathComponent : name
                    onCreate(projectName, selectedPath)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the root folder for your project"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
            if name.isEmpty {
                name = url.lastPathComponent
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
