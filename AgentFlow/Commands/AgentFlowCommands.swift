import SwiftUI
import AFCore
import AFCanvas

struct AgentFlowCommands: Commands {
    let appState: AppState
    @Binding var showNewProject: Bool
    @Binding var sidebarVisible: Bool
    @Binding var showCommandPalette: Bool

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project") {
                showNewProject = true
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Command Palette") {
                showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
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
                    project.canvasState.zoom = 1.0
                    project.canvasState.offset = .zero
                }
            }
            .keyboardShortcut("0", modifiers: .command)
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
                    x: node.position.x + 50,
                    y: node.position.y + 50,
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
}
