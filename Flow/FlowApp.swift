import SwiftUI
import AFCore
import AFAgent
import AFCanvas

@main
struct FlowApp: App {
    @State private var appState: AppState
    @State private var providerRegistry = ProviderRegistry()
    @State private var gitStatus = GitStatusService()
    @State private var healthMonitor: RuntimeHealthMonitor
    @State private var sidebarVisible = true
    @State private var settingsVisible = false
    @State private var showCommandPalette = false

    init() {
        let state = AppState()
        ProjectPersistence.load(into: state)
        _appState = State(initialValue: state)
        _healthMonitor = State(initialValue: RuntimeHealthMonitor(discovery: RuntimeDiscovery()))

        let appState = state
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let chars = event.charactersIgnoringModifiers else { return event }

            if flags == [.command, .shift], chars == "c" {
                if let project = appState.activeProject, !project.nodes.isEmpty {
                    project.fitToScreen(viewportSize: project.canvasState.viewportSize)
                }
                return nil
            }

            // ⌘ shortcuts (Command only, no other modifiers)
            if flags == .command {
                switch chars {
                case "w":
                    if let project = appState.activeProject, !project.selectedNodeIDs.isEmpty {
                        project.deleteSelected()
                        appState.flushSaveNow()
                    }
                    return nil

                case "0":
                    if let project = appState.activeProject {
                        withAnimation(.easeOut(duration: 0.2)) {
                            project.canvasState.resetZoom(in: project.canvasState.viewportSize)
                            project.onChange?()
                        }
                    }
                    return nil

                case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                    if let project = appState.activeProject,
                       let digit = Int(chars),
                       let nodeID = project.nodeID(atNumber: digit),
                       let node = project.nodes[nodeID] {
                        project.selectedNodeIDs = [nodeID]
                        project.selectedConnectionIDs.removeAll()
                        project.bringToFront(nodeID)
                        withAnimation(.spring(duration: 0.35)) {
                            project.canvasState.center(
                                on: node.position.point,
                                in: project.canvasState.viewportSize
                            )
                        }
                        project.onChange?()
                    }
                    return nil

                default:
                    return event
                }
            }

            return event
        }
    }

    var body: some Scene {
        Window("Flow", id: "main") {
            ProjectEditorView(
                sidebarVisible: $sidebarVisible,
                settingsVisible: $settingsVisible,
                showCommandPalette: $showCommandPalette
            )
            .environment(appState)
            .environment(providerRegistry)
            .environment(gitStatus)
            .environment(healthMonitor)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            FlowCommands(
                appState: appState,
                sidebarVisible: $sidebarVisible,
                settingsVisible: $settingsVisible,
                showCommandPalette: $showCommandPalette
            )
        }
    }
}
