import SwiftUI
import AFCore
import AFCanvas

struct FlowCommands: Commands {
    let appState: AppState
    @Binding var sidebarVisible: Bool
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
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button("Select All") {
                appState.activeProject?.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Duplicate Selected") {
                duplicateSelectedNodes()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Delete Selected") {
                appState.activeProject?.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
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
                    project.canvasState.zoom = min(3.0, project.canvasState.zoom + 0.25)
                }
            }
            .keyboardShortcut(KeyEquivalent("+"), modifiers: .command)

            Button("Zoom Out") {
                if let project = appState.activeProject {
                    project.canvasState.zoom = max(0.1, project.canvasState.zoom - 0.25)
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
            .keyboardShortcut("c", modifiers: .command)
        }
    }

    private func fitToScreen() {
        guard let project = appState.activeProject, !project.nodes.isEmpty else { return }

        let nodes = Array(project.nodes.values)
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
        let viewportSize = project.canvasState.viewportSize

        let availW = max(1, viewportSize.width - padding * 2)
        let availH = max(1, viewportSize.height - padding * 2)
        let newZoom = max(0.15, min(1.5, min(availW / contentWidth, availH / contentHeight)))

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let newOffsetX = viewportSize.width / 2 - cx * newZoom
        let newOffsetY = viewportSize.height / 2 - cy * newZoom

        withAnimation(.spring(duration: 0.4)) {
            project.canvasState.zoom = newZoom
            project.canvasState.offset = CGPoint(x: newOffsetX, y: newOffsetY)
        }
    }

    private func duplicateSelectedNodes() {
        guard let project = appState.activeProject else { return }
        let selectedIDs = project.selectedNodeIDs
        var newIDs: Set<UUID> = []

        for id in selectedIDs {
            guard let node = project.nodes[id] else { continue }
            let newNode = WorkflowNode(
                kind: node.kind,
                title: "\(node.title) Copy",
                position: NodePosition(
                    x: node.position.x + node.position.width + 30,
                    y: node.position.y,
                    width: node.position.width,
                    height: node.position.height
                ),
                configuration: node.configuration
            )
            project.nodes[newNode.id] = newNode
            newIDs.insert(newNode.id)
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
