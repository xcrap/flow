import Foundation
import AFCore

/// Simple Codex provider — spawns `codex exec` per message (like Claude's -p mode)
public final class CodexProvider: AIProvider, Sendable {
    public let id = "codex"
    public let displayName = "Codex (OpenAI)"

    public let availableModels: [AIModel] = [
        AIModel(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 200_000),
    ]

    private let holder = ProcessHolder()

    public init() {}

    public func sendMessage(
        prompt: String,
        messages: [ConversationMessage],
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.run(
                        prompt: prompt,
                        model: model,
                        workingDirectory: workingDirectory,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancel() async {
        await holder.terminate()
    }

    private static func findCodex() -> URL {
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(NSHomeDirectory())/.local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    }

    private func run(
        prompt: String,
        model: String,
        workingDirectory: URL?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = Self.findCodex()
        process.arguments = [
            "exec",
            "-m", model,
            "--sandbox", "danger-full-access",
            prompt
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        process.environment = env

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        await holder.set(process)

        do {
            try process.run()
        } catch {
            continuation.yield(.error("Failed to start codex: \(error.localizedDescription)"))
            continuation.finish()
            return
        }

        continuation.yield(.initialized(sessionID: "", model: model))

        let handle = stdout.fileHandleForReading

        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var gotOutput = false

            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    fileHandle.readabilityHandler = nil
                    continuation.yield(.done(stopReason: "end_turn"))
                    continuation.finish()
                    outerCont.resume()
                    return
                }

                if let text = String(data: data, encoding: .utf8) {
                    if !gotOutput {
                        gotOutput = true
                    }
                    continuation.yield(.textDelta(text))
                }
            }
        }

        process.waitUntilExit()

        // Check stderr for errors
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        if let errText = String(data: errData, encoding: .utf8),
           !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Extract token usage from codex output
            if errText.contains("tokens used") {
                // Parse token count if available
            }
        }
    }
}

private actor ProcessHolder {
    var process: Process?
    func set(_ p: Process?) { process = p }
    func terminate() { process?.terminate(); process = nil }
}
