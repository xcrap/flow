import Foundation

@Observable
@MainActor
public final class TerminalSession {
    public let id: UUID
    public var outputLines: [TerminalLine] = []
    public var isRunning: Bool = false
    public var currentDirectory: String

    private var process: Process?

    public init(id: UUID, currentDirectory: String = FileManager.default.currentDirectoryPath) {
        self.id = id
        self.currentDirectory = currentDirectory
        outputLines.append(TerminalLine(text: "$ ", type: .prompt))
    }

    public func execute(command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        outputLines.append(TerminalLine(text: "$ \(command)", type: .command))
        isRunning = true

        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        proc.environment = env

        process = proc

        let handle = pipe.fileHandleForReading

        Task { @MainActor in
            do {
                try proc.run()

                handle.readabilityHandler = { [weak self] fh in
                    let data = fh.availableData
                    guard !data.isEmpty else {
                        fh.readabilityHandler = nil
                        return
                    }
                    if let text = String(data: data, encoding: .utf8) {
                        Task { @MainActor [weak self] in
                            let lines = text.components(separatedBy: "\n")
                            for line in lines where !line.isEmpty {
                                self?.outputLines.append(TerminalLine(text: line, type: .output))
                            }
                        }
                    }
                }

                proc.terminationHandler = { [weak self] p in
                    Task { @MainActor [weak self] in
                        self?.isRunning = false
                        if p.terminationStatus != 0 {
                            self?.outputLines.append(
                                TerminalLine(text: "exit \(p.terminationStatus)", type: .error)
                            )
                        }
                        self?.process = nil
                    }
                }
            } catch {
                outputLines.append(TerminalLine(text: "Error: \(error.localizedDescription)", type: .error))
                isRunning = false
            }
        }
    }

    public func interrupt() {
        process?.interrupt()
    }

    public func clear() {
        outputLines.removeAll()
    }
}

public struct TerminalLine: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let type: LineType
    public let timestamp = Date()

    public enum LineType: Sendable {
        case prompt, command, output, error
    }
}
