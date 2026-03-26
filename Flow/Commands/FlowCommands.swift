import SwiftUI
import AFCore
import AFCanvas

struct FlowCommands: Commands {
    let appState: AppState
    @Binding var sidebarVisible: Bool
    @Binding var settingsVisible: Bool
    @Binding var showCommandPalette: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
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
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("New AI Agent") {
                addNode(kind: .agent, title: "AI Agent")
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(appState.activeProject == nil)

            Button("New Terminal") {
                addNode(kind: .terminal, title: "Terminal")
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState.activeProject == nil)

            Button("Command Palette") {
                showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Close Node") {
                if let project = appState.activeProject, !project.selectedNodeIDs.isEmpty {
                    project.deleteSelected()
                    appState.flushSaveNow()
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button("Duplicate Selected") {
                duplicateSelectedNodes()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Delete Selected") {
                if appState.activeProject?.selectedNodeIDs.isEmpty == false {
                    appState.activeProject?.deleteSelected()
                    appState.flushSaveNow()
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                settingsVisible.toggle()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                if let project = appState.activeProject {
                    zoom(project, by: 1.1)
                }
            }
            .keyboardShortcut(KeyEquivalent("+"), modifiers: .command)

            Button("Zoom Out") {
                if let project = appState.activeProject {
                    zoom(project, by: 1 / 1.1)
                }
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Zoom") {
                if let project = appState.activeProject {
                    project.canvasState.resetZoom(in: project.canvasState.viewportSize)
                }
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Fit to Screen") {
                fitToScreen()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Tidy Up") {
                tidyUp()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(appState.activeProject == nil || (appState.activeProject?.nodes.count ?? 0) < 2)
        }
    }

    private func fitToScreen() {
        guard let project = appState.activeProject else { return }
        project.fitToScreen(viewportSize: project.canvasState.viewportSize)
    }

    private func tidyUp() {
        guard let project = appState.activeProject else { return }
        project.tidyUp(viewportSize: project.canvasState.viewportSize)
    }

    private func zoom(_ project: ProjectState, by factor: Double) {
        project.canvasState.zoom(by: factor, around: project.canvasState.viewportCenter)
        project.onChange?()
    }

    private func duplicateSelectedNodes() {
        guard let project = appState.activeProject else { return }
        let selectedIDs = project.selectedNodeIDs
        var newIDs: Set<UUID> = []

        for id in selectedIDs {
            if let newNode = project.duplicateNode(id) {
                newIDs.insert(newNode.id)
            }
        }

        project.selectedNodeIDs = newIDs
    }

    private func addNode(kind: NodeKind, title: String) {
        guard let project = appState.activeProject else { return }
        let position = nextNodePosition(in: project, kind: kind)
        let node = project.addNode(kind: kind, title: title, at: position)
        project.selectedNodeIDs = [node.id]
        project.selectedConnectionIDs.removeAll()
        project.bringToFront(node.id)
    }

    private func nextNodePosition(in project: ProjectState, kind: NodeKind) -> CGPoint {
        let size = WorkflowNode.defaultSize(for: kind)
        let padding: Double = 40

        if project.nodes.isEmpty {
            return project.canvasState.screenToCanvas(
                CGPoint(x: 300 + size.width / 2, y: 80 + size.height / 2)
            )
        }

        var maxRight: Double = -Double.infinity
        var yAtMaxRight: Double = 0

        for node in project.nodes.values {
            let right = node.position.x + node.position.width / 2
            if right > maxRight {
                maxRight = right
                yAtMaxRight = node.position.y
            }
        }

        return CGPoint(
            x: maxRight + padding + size.width / 2,
            y: yAtMaxRight
        )
    }
}
