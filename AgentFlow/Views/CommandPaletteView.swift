import SwiftUI
import AFCore
import AFCanvas

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var onAction: (CommandAction) -> Void

    private var filteredCommands: [CommandItem] {
        let all = CommandItem.allCommands
        if searchText.isEmpty { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.title.lowercased().contains(query) ||
            $0.subtitle.lowercased().contains(query) ||
            $0.keywords.contains(where: { $0.contains(query) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onSubmit {
                        executeSelected()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            commandRow(command, isSelected: index == selectedIndex)
                                .id(command.id)
                                .onTapGesture {
                                    onAction(command.action)
                                    isPresented = false
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedIndex) {
                    if let cmd = filteredCommands[safe: selectedIndex] {
                        proxy.scrollTo(cmd.id)
                    }
                }
            }
        }
        .frame(width: 500, height: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    @ViewBuilder
    private func commandRow(_ command: CommandItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .font(.system(size: 14))
                .foregroundStyle(command.iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }

    private func executeSelected() {
        guard let command = filteredCommands[safe: selectedIndex] else { return }
        onAction(command.action)
        isPresented = false
    }
}

// MARK: - Command Data

enum CommandAction {
    case addAgent
    case addTerminal
    case fitToScreen
    case tidyUp
    case zoomIn
    case zoomOut
    case resetZoom
    case newProject
    case toggleSidebar
    case openSettings
}

struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let action: CommandAction
    let shortcut: String?
    let keywords: [String]

    static let allCommands: [CommandItem] = [
        CommandItem(title: "Add AI Agent", subtitle: "Create a new Claude/OpenAI chat node", icon: "brain", iconColor: .purple, action: .addAgent, shortcut: nil, keywords: ["agent", "chat", "claude", "ai"]),
        CommandItem(title: "Add Terminal", subtitle: "Create a new shell terminal node", icon: "terminal", iconColor: .blue, action: .addTerminal, shortcut: nil, keywords: ["terminal", "shell", "bash", "command"]),
        CommandItem(title: "Fit to Screen", subtitle: "Zoom to show all nodes", icon: "arrow.up.backward.and.arrow.down.forward", iconColor: .primary, action: .fitToScreen, shortcut: nil, keywords: ["fit", "zoom", "center", "all"]),
        CommandItem(title: "Tidy Up", subtitle: "Arrange nodes in a grid", icon: "rectangle.3.group", iconColor: .primary, action: .tidyUp, shortcut: nil, keywords: ["tidy", "arrange", "grid", "layout", "organize"]),
        CommandItem(title: "Zoom In", subtitle: "Increase canvas zoom", icon: "plus.magnifyingglass", iconColor: .primary, action: .zoomIn, shortcut: "⌘+", keywords: ["zoom", "bigger"]),
        CommandItem(title: "Zoom Out", subtitle: "Decrease canvas zoom", icon: "minus.magnifyingglass", iconColor: .primary, action: .zoomOut, shortcut: "⌘-", keywords: ["zoom", "smaller"]),
        CommandItem(title: "Reset Zoom", subtitle: "Reset to 100% zoom", icon: "1.magnifyingglass", iconColor: .primary, action: .resetZoom, shortcut: "⌘0", keywords: ["reset", "zoom", "100"]),
        CommandItem(title: "New Project", subtitle: "Create a new project from folder", icon: "folder.badge.plus", iconColor: .orange, action: .newProject, shortcut: "⌘N", keywords: ["new", "project", "folder", "create"]),
        CommandItem(title: "Toggle Sidebar", subtitle: "Show or hide the projects sidebar", icon: "sidebar.leading", iconColor: .primary, action: .toggleSidebar, shortcut: "⌘B", keywords: ["sidebar", "toggle", "hide", "show"]),
        CommandItem(title: "Settings", subtitle: "Open app settings", icon: "gear", iconColor: .gray, action: .openSettings, shortcut: "⌘,", keywords: ["settings", "preferences", "config"]),
    ]
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
