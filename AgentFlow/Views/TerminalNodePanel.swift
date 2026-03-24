import SwiftUI
import AFCore
import AFAgent
import AFCanvas

struct TerminalNodePanel: View {
    let node: WorkflowNode
    let isSelected: Bool
    let isTitleHovered: Bool
    @Bindable var session: TerminalSession
    var onSave: () -> Void
    var onDelete: () -> Void

    @State private var inputText = ""
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
                .foregroundStyle(session.isRunning ? .green : .blue)

            Text(node.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            if session.isRunning {
                Text("Running")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
            }

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
            .background(.clear)
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("Enter command...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit {
                        runCommand()
                    }
                    .disabled(session.isRunning)
                    .onChange(of: session.isRunning) {
                        if !session.isRunning {
                            inputFocused = true
                            onSave()
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HStack {
                if session.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func runCommand() {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        session.execute(command: cmd)
        inputFocused = true
    }

    private func restoreInputFocusIfNeeded() {
        guard isSelected else { return }
        Task { @MainActor in
            inputFocused = true
        }
    }
}
