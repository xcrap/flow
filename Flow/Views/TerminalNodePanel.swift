import SwiftUI
import AFCore
import AFCanvas
import AFTerminal

struct TerminalNodePanel: View {
    let node: WorkflowNode
    var nodeNumber: Int?
    let isSelected: Bool
    let isTitleHovered: Bool
    @Bindable var session: TerminalSession
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            terminalArea
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.blue.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            restoreInputFocusIfNeeded()
        }
        .onChange(of: isSelected) {
            restoreInputFocusIfNeeded()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(session.isRunning ? .green : .orange)

            if let nodeNumber {
                Text("\(nodeNumber)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.blue.opacity(0.4)))
            }

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Text(statusText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(session.isRunning ? .green : .orange)

            if !session.currentDirectory.isEmpty {
                Text(shortDirectory(session.currentDirectory))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer()

            if session.isRunning {
                Button {
                    session.interrupt()
                } label: {
                    Text("^C")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Send Ctrl-C")
            }

            Button {
                session.restart()
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Restart shell in project root")

            Button {
                session.clearScreen()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear screen")

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete node")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(session.isRunning ? Color.green.opacity(0.12) : (isTitleHovered ? Color.white.opacity(0.06) : Color(red: 0.13, green: 0.13, blue: 0.14)))
    }

    private var terminalArea: some View {
        TerminalSurface(session: session)
            .id(session.viewIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(Color.black.opacity(0.12))
            .onAppear {
                restoreInputFocusIfNeeded()
            }
    }

    private func restoreInputFocusIfNeeded() {
        guard isSelected else { return }
        Task { @MainActor in
            session.focus()
        }
    }

    private var statusText: String {
        if session.isRunning {
            return "Shell"
        }

        if let lastExitCode = session.lastExitCode {
            return "Exit \(lastExitCode)"
        }

        return "Stopped"
    }

    private func shortDirectory(_ directory: String) -> String {
        let home = NSHomeDirectory()
        if directory.hasPrefix(home) {
            return "~" + directory.dropFirst(home.count)
        }
        return directory
    }
}
