import SwiftUI
import AFCore

struct SettingsView: View {
    static let preferredPanelWidth: CGFloat = 520

    var onClose: (() -> Void)? = nil

    @Environment(RuntimeHealthMonitor.self) private var healthMonitor
    @AppStorage("defaultProvider") private var defaultProvider = "claude"
    @AppStorage("defaultModel") private var defaultModel = "sonnet"
    @AppStorage("defaultAccess") private var defaultAccess = "fullAccess"
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

    private let shortcuts: [(title: String, shortcut: String)] = [
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
        ("Fit to Screen", "⇧⌘C"),
        ("Tidy Up", "⌘G"),
        ("Send Message", "↩ / ⌘↩"),
        ("Insert Line Break", "⇧↩"),
    ]

    private let shortcutColumnWidth: CGFloat = 208

    var body: some View {
        VStack(spacing: 0) {
            if let onClose {
                HStack {
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
            }

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

                        settingsRow("Default Access") {
                            Picker("", selection: $defaultAccess) {
                                Text("Supervised").tag("supervised")
                                Text("Accept Edits").tag("acceptEdits")
                                Text("Full access").tag("fullAccess")
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    settingsSection("Runtime Health", icon: "stethoscope") {
                        ForEach(healthMonitor.specs, id: \.id) { spec in
                            runtimeHealthRow(spec: spec)
                        }

                        HStack {
                            Spacer()
                            Button {
                                Task { await healthMonitor.refresh() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    settingsSection("Canvas", icon: "square.grid.3x3") {
                        settingsRow("Show Grid") {
                            Toggle("", isOn: $gridVisible)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    settingsSection("Keyboard Shortcuts", icon: "keyboard") {
                        ForEach(shortcuts, id: \.title) { shortcut in
                            shortcutRow(shortcut.title, shortcut: shortcut.shortcut)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await healthMonitor.loadCurrent()
        }
    }

    // MARK: - Runtime Health

    private func runtimeHealthRow(spec: BinarySpec) -> some View {
        let health = healthMonitor.health(for: spec.id)

        return HStack(spacing: 8) {
            Circle()
                .fill(healthColor(health))
                .frame(width: 7, height: 7)

            Text(spec.displayName)
                .font(.system(size: 13))

            Spacer()

            switch health {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .available(let path, let version):
                VStack(alignment: .trailing, spacing: 2) {
                    if let version {
                        Text("v\(version)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(abbreviatePath(path))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

            case .notFound:
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Not installed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                    if let hint = spec.installHint {
                        Text(hint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func healthColor(_ health: BinaryHealth) -> Color {
        switch health {
        case .checking: .orange
        case .available: .green
        case .notFound: .red
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(label)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                let alternatives = shortcutAlternatives(for: shortcut)

                ForEach(Array(alternatives.enumerated()), id: \.offset) { index, combination in
                    if index > 0 {
                        Text("/")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        let tokens = shortcutTokens(for: combination)

                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            shortcutKey(token)
                        }
                    }
                }
            }
            .frame(width: shortcutColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func shortcutAlternatives(for shortcut: String) -> [String] {
        shortcut
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func shortcutTokens(for shortcut: String) -> [String] {
        let modifierGlyphs: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        var tokens: [String] = []
        var pending = ""

        for character in shortcut {
            if modifierGlyphs.contains(character) {
                if !pending.isEmpty {
                    tokens.append(pending)
                    pending = ""
                }
                tokens.append(String(character))
            } else {
                pending.append(character)
            }
        }

        if !pending.isEmpty {
            tokens.append(pending)
        }

        return tokens
    }

    private func shortcutKey(_ token: String) -> some View {
        Text(token)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: max(22, CGFloat(token.count) * 11), minHeight: 22)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.75)
            }
    }
}
