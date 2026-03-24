import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("gridVisible") private var gridVisible = true

    var body: some View {
        Form {
            Section {
                Picker("Default Provider", selection: $defaultProvider) {
                    Text("Claude (via Claude Code)").tag("claude")
                    Text("Codex (via OpenAI)").tag("codex")
                }
            } header: {
                Label("AI Provider", systemImage: "cpu")
            }

            Section {
                Toggle("Show Grid", isOn: $gridVisible)
            } header: {
                Label("Canvas", systemImage: "square.grid.3x3")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 260)
    }
}
