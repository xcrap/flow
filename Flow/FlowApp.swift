import SwiftUI
import AFCore
import AFAgent
import AFCanvas

@main
struct FlowApp: App {
    @State private var appState: AppState
    @State private var providerRegistry = ProviderRegistry()
    @State private var gitStatus = GitStatusService()
    @State private var sidebarVisible = true
    @State private var showCommandPalette = false

    init() {
        let state = AppState()
        ProjectPersistence.load(into: state)
        _appState = State(initialValue: state)

        let appState = state
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let chars = event.charactersIgnoringModifiers else { return event }

            // ⌘ shortcuts (Command only, no other modifiers)
            if flags == .command {
                switch chars {
                case "w":
                    if let project = appState.activeProject, !project.selectedNodeIDs.isEmpty {
                        project.deleteSelected()
                    }
                    return nil

                case "a":
                    appState.activeProject?.selectAll()
                    return nil

                case "0":
                    if let project = appState.activeProject {
                        withAnimation(.easeOut(duration: 0.2)) {
                            project.canvasState.resetZoom(in: project.canvasState.viewportSize)
                            project.onChange?()
                        }
                    }
                    return nil

                case "c":
                    guard let project = appState.activeProject, !project.nodes.isEmpty else { return nil }
                    let nodes = Array(project.nodes.values)
                    var minX = Double.infinity, minY = Double.infinity
                    var maxX = -Double.infinity, maxY = -Double.infinity
                    for node in nodes {
                        minX = min(minX, node.position.x - node.position.width / 2)
                        minY = min(minY, node.position.y - node.position.height / 2)
                        maxX = max(maxX, node.position.x + node.position.width / 2)
                        maxY = max(maxY, node.position.y + node.position.height / 2)
                    }
                    let contentW = max(1, maxX - minX), contentH = max(1, maxY - minY)
                    let vp = project.canvasState.viewportSize
                    let padding: Double = 60
                    let zoom = max(0.15, min(1.5, min((vp.width - padding * 2) / contentW, (vp.height - padding * 2) / contentH)))
                    let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
                    withAnimation(.spring(duration: 0.4)) {
                        project.canvasState.zoom = zoom
                        project.canvasState.offset = CGPoint(x: vp.width / 2 - cx * zoom, y: vp.height / 2 - cy * zoom)
                    }
                    return nil

                default:
                    return event
                }
            }

            // Bare ⌫ (Delete/Backspace) — only when no text field has focus
            if chars == "\u{7F}",
               !flags.contains(.command), !flags.contains(.option), !flags.contains(.control)
            {
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   firstResponder is NSTextView
                {
                    return event
                }
                if let project = appState.activeProject, !project.selectedNodeIDs.isEmpty {
                    project.deleteSelected()
                    return nil
                }
            }

            return event
        }
    }

    var body: some Scene {
        Window("Flow", id: "main") {
            ProjectEditorView(
                sidebarVisible: $sidebarVisible,
                showCommandPalette: $showCommandPalette
            )
            .environment(appState)
            .environment(providerRegistry)
            .environment(gitStatus)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FlowCommands(
                appState: appState,
                sidebarVisible: $sidebarVisible,
                showCommandPalette: $showCommandPalette
            )
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}
