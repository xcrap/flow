import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("gridVisible") private var gridVisible = true

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                Form {
                    Section("AI Provider") {
                        Picker("Default Provider", selection: $defaultProvider) {
                            Text("Claude (via Claude Code)").tag("claude")
                        }
                    }

                    Section("Canvas") {
                        Toggle("Show Grid", isOn: $gridVisible)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .scenePadding()
        .frame(width: 400, height: 200)
    }
}
