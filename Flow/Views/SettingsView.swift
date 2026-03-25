import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("gridVisible") private var gridVisible = true

    private let shortcuts: [(String, String)] = [
        ("New Project", "⌘N"),
        ("New AI Agent", "⌘I"),
        ("New Terminal", "⌘T"),
        ("Command Palette", "⌘K"),
        ("Close Node", "⌘W"),
        ("Select All", "⌘A"),
        ("Duplicate Selected", "⌘D"),
        ("Delete Selected", "⌫"),
        ("Toggle Sidebar", "⌘B"),
        ("Zoom In", "⌘+"),
        ("Zoom Out", "⌘−"),
        ("Reset Zoom", "⌘0"),
        ("Fit to Screen", "⌘C"),
        ("Tidy Up", "⌘G"),
        ("Send Message", "⌘↩"),
    ]

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

            Section {
                ForEach(shortcuts, id: \.0) { shortcut in
                    HStack {
                        Text(shortcut.0)
                        Spacer()
                        Text(shortcut.1)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
            } header: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 400)
        .background(SettingsWindowResizer())
    }
}

/// Injects into the NSWindow hosting the Settings view to force it resizable.
private struct SettingsWindowResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.styleMask.insert(.resizable)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
