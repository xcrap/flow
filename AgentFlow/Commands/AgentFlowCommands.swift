import SwiftUI
import AFCanvas

struct AgentFlowCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Choose the root folder for your project"
                if panel.runModal() == .OK, let url = panel.url {
                    appState.createProject(name: url.lastPathComponent, rootPath: url.path)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Button("Select All") {
                appState.activeProject?.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Delete Selected") {
                appState.activeProject?.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
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
}
