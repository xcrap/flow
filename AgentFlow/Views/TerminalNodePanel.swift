import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct TerminalNodePanel: View {
    let node: WorkflowNode
    let isSelected: Bool
    @Bindable var session: TerminalSession
    var onDelete: () -> Void

    @State private var inputText = ""
    @State private var isTitleHovered = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            outputArea
            Divider()
            commandInput
        }
        .frame(width: node.position.width, height: node.position.height)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 12 : 6, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.blue : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isRunning ? Color.green : .gray.opacity(0.4))
                .frame(width: 9, height: 9)

            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()

            if session.isRunning {
                Button {
                    session.interrupt()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Interrupt")
            }

            Button {
                session.clear()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear output")

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete node")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isTitleHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .onHover { isTitleHovered = $0 }
    }

    // MARK: - Output

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(session.outputLines) { line in
                        terminalLine(line)
                            .id(line.id)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 13, design: .monospaced))
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: session.outputLines.count) {
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(session.outputLines.last?.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func terminalLine(_ line: TerminalLine) -> some View {
        switch line.type {
        case .prompt:
            EmptyView()
        case .command:
            Text(line.text)
                .foregroundStyle(.green)
                .lineSpacing(2)
        case .output:
            Text(line.text)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineSpacing(2)
        case .error:
            Text(line.text)
                .foregroundStyle(.red)
                .lineSpacing(2)
        }
    }

    // MARK: - Command Input

    private var commandInput: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            TextField("command", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .focused($inputFocused)
                .onSubmit {
                    runCommand()
                }
                .disabled(session.isRunning)
                .onChange(of: session.isRunning) {
                    if !session.isRunning {
                        inputFocused = true
                    }
                }

            if session.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func runCommand() {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        session.execute(command: cmd)
        inputFocused = true
    }
}
