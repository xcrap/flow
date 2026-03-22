import SwiftUI
import AFCore
import AFAgent
import AFCanvas

@main
struct AgentFlowApp: App {
    @State private var appState: AppState
    @State private var providerRegistry = ProviderRegistry()
    @State private var sidebarVisible = true
    @State private var showCommandPalette = false

    init() {
        let state = AppState()
        ProjectPersistence.load(into: state)
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        Window("AgentFlow", id: "main") {
            ProjectEditorView(
                sidebarVisible: $sidebarVisible,
                showCommandPalette: $showCommandPalette
            )
            .environment(appState)
            .environment(providerRegistry)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AgentFlowCommands(
                appState: appState,
                sidebarVisible: $sidebarVisible,
                showCommandPalette: $showCommandPalette
            )
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
