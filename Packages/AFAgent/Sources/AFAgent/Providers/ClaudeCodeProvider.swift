import Foundation
import AFCore

private actor ProcessHolder {
    var process: Process?

    func set(_ p: Process?) { process = p }
    func get() -> Process? { process }
}

public final class ClaudeCodeProvider: AIProvider, Sendable {
    public let id = "claude"
    public let displayName = "Claude (via Claude Code)"

    public let availableModels: [AIModel] = [
        AIModel(id: "sonnet", name: "Sonnet (latest)", contextWindow: 200_000),
        AIModel(id: "opus", name: "Opus (latest)", contextWindow: 1_000_000),
        AIModel(id: "haiku", name: "Haiku (latest)", contextWindow: 200_000),
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: 200_000),
        AIModel(id: "claude-opus-4-6", name: "Claude Opus 4", contextWindow: 1_000_000),
        AIModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", contextWindow: 200_000),
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
                    try await self.runClaude(
                        prompt: prompt,
                        model: model,
                        effort: effort,
                        systemPrompt: systemPrompt,
                        permissionMode: permissionMode,
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
        await holder.get()?.terminate()
    }

    // MARK: - Private

    private static func findClaude() -> URL {
        // Check common locations
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin/claude",
        ]

        for path in candidates {
            if path.contains("*") {
                // Glob expansion
                let dir = (path as NSString).deletingLastPathComponent
                let file = (path as NSString).lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                    for item in contents {
                        let full = "\(dir)/\(item)/\(file)"
                        if FileManager.default.isExecutableFile(atPath: full) {
                            return URL(fileURLWithPath: full)
                        }
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Fallback: try to find via shell
        let shell = Process()
        let pipe = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-l", "-c", "which claude"]
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        try? shell.run()
        shell.waitUntilExit()
        if let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty
        {
            return URL(fileURLWithPath: output)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func runClaude(
        prompt: String,
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let claudeURL = Self.findClaude()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        if claudeURL.path == "/usr/bin/env" {
            process.executableURL = claudeURL
            var args = ["claude"]
            args += Self.buildArgs(model: model, effort: effort, systemPrompt: systemPrompt, permissionMode: permissionMode, prompt: prompt, resumeSessionID: resumeSessionID)
            process.arguments = args
        } else {
            process.executableURL = claudeURL
            process.arguments = Self.buildArgs(model: model, effort: effort, systemPrompt: systemPrompt, prompt: prompt, resumeSessionID: resumeSessionID)
        }

        // Ensure PATH includes common locations
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        process.standardOutput = stdout
        process.standardError = stderr

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        await holder.set(process)

        process.terminationHandler = { [holder] _ in
            Task { await holder.set(nil) }
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.error("Failed to start claude: \(error.localizedDescription). Is Claude Code installed?"))
            continuation.finish()
            return
        }

        let handle = stdout.fileHandleForReading

        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
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
                    let lines = text.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        if let event = Self.parseStreamEvent(line) {
                            continuation.yield(event)
                        }
                    }
                }
            }
        }

        process.waitUntilExit()

        // Check for errors
        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
            if !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continuation.yield(.error("Claude exited with error: \(errText)"))
            }
        }
    }

    private static func buildArgs(model: String, effort: String?, systemPrompt: String?, permissionMode: String? = nil, prompt: String, resumeSessionID: String? = nil) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", model,
        ]

        if let effort, !effort.isEmpty {
            args += ["--effort", effort]
        }

        if let systemPrompt, !systemPrompt.isEmpty {
            args += ["--system-prompt", systemPrompt]
        }

        // In -p mode, always skip permissions since interactive approval is impossible
        args += ["--dangerously-skip-permissions"]

        if let resumeSessionID, !resumeSessionID.isEmpty {
            args += ["--resume", resumeSessionID]
        }

        args.append(prompt)
        return args
    }

    static func parseStreamEvent(_ jsonLine: String) -> StreamEvent? {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "system":
            let sessionID = json["session_id"] as? String ?? ""
            let model = json["model"] as? String ?? ""
            return .initialized(sessionID: sessionID, model: model)

        case "stream_event":
            // Partial streaming events (token-by-token)
            guard let event = json["event"] as? [String: Any],
                  let eventType = event["type"] as? String
            else { return nil }

            switch eventType {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let deltaType = delta["type"] as? String,
                   deltaType == "text_delta",
                   let text = delta["text"] as? String
                {
                    return .textDelta(text)
                }
                return nil

            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String
                {
                    return .done(stopReason: reason)
                }
                return nil

            default:
                return nil
            }

        case "assistant":
            // Full message (comes after stream_events, skip text since we got deltas)
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]]
            {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "tool_use" {
                        let id = block["id"] as? String ?? ""
                        let name = block["name"] as? String ?? ""
                        let input: String
                        if let inputObj = block["input"] {
                            if let inputData = try? JSONSerialization.data(withJSONObject: inputObj),
                               let inputStr = String(data: inputData, encoding: .utf8)
                            {
                                input = inputStr
                            } else {
                                input = "\(inputObj)"
                            }
                        } else {
                            input = "{}"
                        }
                        return .toolUse(id: id, name: name, input: input)
                    }
                }
            }
            return nil

        case "result":
            let cost = json["total_cost_usd"] as? Double
            if let modelUsage = json["modelUsage"] as? [String: Any] {
                // Extract from modelUsage for accurate token counts
                for (_, value) in modelUsage {
                    if let modelData = value as? [String: Any] {
                        let inputTokens = modelData["inputTokens"] as? Int ?? 0
                        let outputTokens = modelData["outputTokens"] as? Int ?? 0
                        return .usage(inputTokens: inputTokens, outputTokens: outputTokens, costUSD: cost)
                    }
                }
            }
            return .usage(inputTokens: 0, outputTokens: 0, costUSD: cost)

        default:
            return nil
        }
    }
}
