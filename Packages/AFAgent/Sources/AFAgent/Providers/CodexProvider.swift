import Foundation
import AFCore

public final class CodexProvider: AIProvider, Sendable {
    public let id = "codex"
    public let displayName = "Codex (OpenAI)"

    public let availableModels: [AIModel] = [
        AIModel(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 200_000),
    ]

    private let holder = CodexProcessHolder()

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
                    try await self.runCodex(
                        prompt: prompt,
                        model: model,
                        systemPrompt: systemPrompt,
                        workingDirectory: workingDirectory,
                        resumeSessionID: resumeSessionID,
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

    // MARK: - Private

    private static func findCodex() -> URL {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fallback
        let shell = Process()
        let pipe = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-l", "-c", "which codex"]
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        try? shell.run()
        shell.waitUntilExit()
        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return URL(fileURLWithPath: output)
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    }

    private func runCodex(
        prompt: String,
        model: String,
        systemPrompt: String?,
        workingDirectory: URL?,
        resumeSessionID: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let codexURL = Self.findCodex()
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = codexURL
        process.arguments = ["app-server", "--transport", "stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        env["PATH"] = (extraPaths + [env["PATH"] ?? ""]).joined(separator: ":")
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

        let stdinHandle = stdin.fileHandleForWriting
        let stdoutHandle = stdout.fileHandleForReading

        // Helper to send JSON-RPC
        func send(_ method: String, id: Int, params: [String: Any] = [:]) {
            var msg: [String: Any] = ["method": method, "id": id, "params": params]
            if let data = try? JSONSerialization.data(withJSONObject: msg),
               var str = String(data: data, encoding: .utf8) {
                str += "\n"
                stdinHandle.write(str.data(using: .utf8)!)
            }
        }

        // 1. Start thread
        var threadParams: [String: Any] = ["model": model]
        if let systemPrompt, !systemPrompt.isEmpty {
            threadParams["instructions"] = systemPrompt
        }
        send("thread/start", id: 1, params: threadParams)

        // Read responses and wait for thread ID
        var threadID: String?
        var requestID = 10

        // Start reading in background
        continuation.yield(.initialized(sessionID: "", model: model))

        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    continuation.yield(.done(stopReason: "end_turn"))
                    continuation.finish()
                    outerCont.resume()
                    return
                }

                if let text = String(data: data, encoding: .utf8) {
                    let lines = text.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        guard let lineData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                        else { continue }

                        // Handle response to thread/start
                        if let id = json["id"] as? Int, id == 1,
                           let result = json["result"] as? [String: Any],
                           let thread = result["thread"] as? [String: Any] {
                            threadID = thread["id"] as? String

                            // 2. Start turn with the prompt
                            requestID += 1
                            send("turn/start", id: requestID, params: [
                                "thread_id": threadID ?? "",
                                "content": prompt
                            ])
                            continuation.yield(.initialized(sessionID: threadID ?? "", model: model))
                        }

                        // Handle notifications
                        if let method = json["method"] as? String {
                            let params = json["params"] as? [String: Any] ?? [:]

                            switch method {
                            case "turn/message_delta":
                                if let delta = params["delta"] as? String {
                                    continuation.yield(.textDelta(delta))
                                }

                            case "item/message_completed":
                                if let content = params["content"] as? String {
                                    // Full message if we didn't get deltas
                                }

                            case "turn/completed":
                                let usage = params["usage"] as? [String: Any]
                                let inputTokens = usage?["input_tokens"] as? Int ?? 0
                                let outputTokens = usage?["output_tokens"] as? Int ?? 0
                                continuation.yield(.usage(inputTokens: inputTokens, outputTokens: outputTokens, costUSD: nil))
                                continuation.yield(.done(stopReason: "end_turn"))
                                continuation.finish()
                                handle.readabilityHandler = nil
                                outerCont.resume()

                            case "item/tool_use":
                                let name = params["name"] as? String ?? ""
                                let toolID = params["id"] as? String ?? ""
                                let input = params["input"] as? String ?? "{}"
                                continuation.yield(.toolUse(id: toolID, name: name, input: input))

                            case "turn/error":
                                let error = params["message"] as? String ?? "Unknown error"
                                continuation.yield(.error(error))

                            default:
                                break
                            }
                        }

                        // Handle error responses
                        if let error = json["error"] as? [String: Any] {
                            let msg = error["message"] as? String ?? "Unknown error"
                            continuation.yield(.error(msg))
                        }
                    }
                }
            }
        }

        process.waitUntilExit()
    }
}

private actor CodexProcessHolder {
    var process: Process?

    func set(_ p: Process?) { process = p }
    func terminate() { process?.terminate(); process = nil }
}
