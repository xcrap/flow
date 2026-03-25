import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("defaultModel") private var defaultModel = "sonnet"
    @AppStorage("gridVisible") private var gridVisible = true

    private var modelsForProvider: [(id: String, name: String)] {
        switch defaultProvider {
        case "codex":
            return [("gpt-5.4", "GPT-5.4")]
        default:
            return [
                ("sonnet", "Sonnet (latest)"),
                ("opus", "Opus (latest)"),
                ("haiku", "Haiku (latest)"),
                ("claude-sonnet-4-20250514", "Claude Sonnet 4"),
                ("claude-opus-4-6", "Claude Opus 4.6"),
                ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
            ]
        }
    }

    private let shortcuts: [(String, String)] = [
        ("New Project", "⌘N"),
        ("New AI Agent", "⌘I"),
        ("New Terminal", "⌘T"),
        ("Command Palette", "⌘K"),
        ("Close Node", "⌘W"),
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection("AI Provider", icon: "cpu") {
                    settingsRow("Default Provider") {
                        Picker("", selection: $defaultProvider) {
                            Text("Claude (via Claude Code)").tag("claude")
                            Text("Codex (via OpenAI)").tag("codex")
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: defaultProvider) {
                            if !modelsForProvider.contains(where: { $0.id == defaultModel }) {
                                defaultModel = modelsForProvider.first?.id ?? "sonnet"
                            }
                        }
                    }

                    settingsRow("Default Model") {
                        Picker("", selection: $defaultModel) {
                            ForEach(modelsForProvider, id: \.id) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                settingsSection("Canvas", icon: "square.grid.3x3") {
                    settingsRow("Show Grid") {
                        Toggle("", isOn: $gridVisible)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                settingsSection("Keyboard Shortcuts", icon: "keyboard") {
                    ForEach(shortcuts, id: \.0) { shortcut in
                        settingsRow(shortcut.0) {
                            Text(shortcut.1)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 420, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowConfigurator())
    }

    // MARK: - Components

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            }
        }
    }

    private func settingsRow<Content: View>(
        _ label: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Configures the NSWindow to be opaque and non-click-through.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.isOpaque = true
            window.ignoresMouseEvents = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
