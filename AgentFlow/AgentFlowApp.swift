import SwiftUI
import AFCore
import AFAgent
import AFCanvas

@main
struct AgentFlowApp: App {
    @State private var appState: AppState
    @State private var providerRegistry = ProviderRegistry()

    init() {
        let state = AppState()
        ProjectPersistence.load(into: state)
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ProjectEditorView()
                .environment(appState)
                .environment(providerRegistry)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AgentFlowCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
