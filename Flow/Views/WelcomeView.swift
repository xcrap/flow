import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.purple.opacity(0.5))

            Text("Flow")
                .font(.system(size: 32, weight: .bold))

            Text("AI agents and terminals on an infinite canvas")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                shortcutRow("⌘ N", "New project")
                shortcutRow("⌘ K", "Command palette")
                shortcutRow("⌘ B", "Toggle sidebar")
                shortcutRow("⌘ +/-", "Zoom in/out")
                shortcutRow("⌥ Drag", "Pan canvas")
                shortcutRow("⇧ Drag", "Snap to grid")
            }
            .padding(.top, 10)

            Spacer()

            Text("Select a project from the sidebar or press ⌘N")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
