import Foundation
import os
import AFCore

private struct ClaudeLineBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: "")
    private static let maxBufferSize = 1_048_576 // 1MB

    func append(_ text: String) -> [String] {
        storage.withLock { value in
            value += text
            if value.count > Self.maxBufferSize {
                value = String(value.suffix(Self.maxBufferSize))
            }
            let parts = value.components(separatedBy: "\n")
            value = parts.last ?? ""
            return Array(parts.dropLast())
        }
    }

    func flush() -> String {
        storage.withLock { value in
            let v = value
            value = ""
            return v
        }
    }
}

private let claudeEffectiveContextWindow = 200_000

public final class ClaudeCodeProvider: AIProvider, Sendable {
    public let id = "claude"
    public let displayName = "Claude (via Claude Code)"

    public let availableModels: [AIModel] = [
        AIModel(id: "sonnet", name: "Sonnet (latest)", contextWindow: claudeEffectiveContextWindow),
        AIModel(id: "opus", name: "Opus (latest)", contextWindow: claudeEffectiveContextWindow),
        AIModel(id: "haiku", name: "Haiku (latest)", contextWindow: claudeEffectiveContextWindow),
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", contextWindow: claudeEffectiveContextWindow),
        AIModel(id: "claude-opus-4-6", name: "Claude Opus 4.6", contextWindow: claudeEffectiveContextWindow),
        AIModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", contextWindow: claudeEffectiveContextWindow),
    ]

    public init() {}

    public func sendMessage(
        prompt: String,
        attachments: [Attachment],
        messages: [ConversationMessage],
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?
    ) -> ProviderStreamHandle {
        let process = Process()

        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            let task = Task {
                do {
                    // Write image attachments to temp files for the CLI
                    let imagePaths = Self.writeAttachmentsToTemp(attachments)
                    defer {
                        for path in imagePaths {
                            try? FileManager.default.removeItem(at: path)
                        }
                    }

                    try await self.runClaude(
                        prompt: prompt,
                        imagePaths: imagePaths,
                        model: model,
                        effort: effort,
                        systemPrompt: systemPrompt,
                        permissionMode: permissionMode,
                        workingDirectory: workingDirectory,
                        resumeSessionID: resumeSessionID,
                        process: process,
                        continuation: continuation
                    )
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Self.forceKill(process)
            }
        }

        return ProviderStreamHandle(stream: stream) {
            Self.forceKill(process)
        }
    }

    private static func writeAttachmentsToTemp(_ attachments: [Attachment]) -> [URL] {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("flow-attachments", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var paths: [URL] = []
        for attachment in attachments where attachment.isImage {
            let ext = attachment.mimeType.components(separatedBy: "/").last ?? "png"
            let filename = "\(attachment.id.uuidString).\(ext)"
            let url = tempDir.appendingPathComponent(filename)
            if fm.createFile(atPath: url.path, contents: attachment.data) {
                paths.append(url)
            }
        }
        return paths
    }

    private static func forceKill(_ process: Process) {
        guard process.isRunning else { return }
        // SIGINT first — Claude Code handles this gracefully
        process.interrupt()
        // If still running after 1s, force terminate
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            process.terminate()
            // Last resort after another 1s
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    private static func findClaude() -> URL {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin/claude",
        ]

        for path in candidates {
            if path.contains("*") {
                let dir = (path as NSString).deletingLastPathComponent
                let file = (path as NSString).lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                    for item in contents {
                        let fullPath = "\(dir)/\(item)/\(file)"
                        if FileManager.default.isExecutableFile(atPath: fullPath) {
                            return URL(fileURLWithPath: fullPath)
                        }
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

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
        imagePaths: [URL] = [],
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?,
        process: Process,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let claudeURL = Self.findClaude()
        let stdout = Pipe()
        let stderr = Pipe()

        if claudeURL.path == "/usr/bin/env" {
            process.executableURL = claudeURL
            var args = ["claude"]
            args += Self.buildArgs(
                model: model,
                effort: effort,
                systemPrompt: systemPrompt,
                permissionMode: permissionMode,
                prompt: prompt,
                resumeSessionID: resumeSessionID,
                imagePaths: imagePaths
            )
            process.arguments = args
        } else {
            process.executableURL = claudeURL
            process.arguments = Self.buildArgs(
                model: model,
                effort: effort,
                systemPrompt: systemPrompt,
                permissionMode: permissionMode,
                prompt: prompt,
                resumeSessionID: resumeSessionID,
                imagePaths: imagePaths
            )
        }

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        do {
            try process.run()
        } catch {
            continuation.yield(.error("Failed to start claude: \(error.localizedDescription). Is Claude Code installed?"))
            continuation.finish()
            return
        }

        continuation.yield(.lifecycle(.turnStarted(turnID: nil)))

        let handle = stdout.fileHandleForReading
        let buffer = ClaudeLineBuffer()

        await withCheckedContinuation { (outerContinuation: CheckedContinuation<Void, Never>) in
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    let remaining = buffer.flush()
                    if !remaining.isEmpty {
                        Self.parseBufferedLines(remaining, continuation: continuation)
                    }
                    fileHandle.readabilityHandler = nil
                    continuation.yield(.done(stopReason: "end_turn"))
                    continuation.finish()
                    outerContinuation.resume()
                    return
                }

                guard let text = String(data: data, encoding: .utf8) else { return }
                let completedLines = buffer.append(text)

                for line in completedLines where !line.isEmpty {
                    if let event = Self.parseStreamEvent(line) {
                        continuation.yield(event)
                    }
                }
            }
        }

        process.waitUntilExit()

        guard !Task.isCancelled else { return }

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            let trimmedError = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedError.isEmpty {
                continuation.yield(.error("Claude exited with error: \(trimmedError)"))
            }
        }
    }

    private static func parseBufferedLines(
        _ buffer: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        for line in buffer.components(separatedBy: "\n") where !line.isEmpty {
            if let event = parseStreamEvent(line) {
                continuation.yield(event)
            }
        }
    }

    private static func buildArgs(
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        prompt: String,
        resumeSessionID: String?,
        imagePaths: [URL] = []
    ) -> [String] {
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

        if let permissionMode, !permissionMode.isEmpty {
            args += ["--permission-mode", permissionMode]
        }

        args += ["--dangerously-skip-permissions"]

        if let resumeSessionID, !resumeSessionID.isEmpty {
            args += ["--resume", resumeSessionID]
        }

        // Build prompt with image references so Claude Code can read them
        var fullPrompt = ""
        for imagePath in imagePaths {
            fullPrompt += "[Image: \(imagePath.path)]\n"
        }
        fullPrompt += prompt

        args.append(fullPrompt)
        return args
    }

    static func parseStreamEvent(_ jsonLine: String) -> StreamEvent? {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        switch type {
        case "system":
            let subtype = json["subtype"] as? String

            switch subtype {
            case nil, "", "init":
                let sessionID = json["session_id"] as? String ?? ""
                let model = json["model"] as? String ?? ""
                return .initialized(sessionID: sessionID, model: model)

            case "status":
                guard let status = json["status"] as? String else { return nil }
                if status == "compacting" {
                    return .lifecycle(.phaseChanged(.compacting))
                }
                return nil

            case "compact_boundary":
                return .lifecycle(.phaseChanged(.compacted))

            default:
                return nil
            }

        case "stream_event":
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
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]]
            {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "tool_use" {
                        let id = block["id"] as? String ?? ""
                        let name = block["name"] as? String ?? ""
                        let input: String
                        if let inputObject = block["input"] {
                            if let inputData = try? JSONSerialization.data(withJSONObject: inputObject),
                               let inputString = String(data: inputData, encoding: .utf8)
                            {
                                input = inputString
                            } else {
                                input = "\(inputObject)"
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
                var inputTokens = 0
                var outputTokens = 0
                for (_, value) in modelUsage {
                    if let modelData = value as? [String: Any] {
                        inputTokens += modelData["inputTokens"] as? Int ?? 0
                        outputTokens += modelData["outputTokens"] as? Int ?? 0
                    }
                }
                return .usage(inputTokens: inputTokens, outputTokens: outputTokens, costUSD: cost)
            }
            return .usage(inputTokens: 0, outputTokens: 0, costUSD: cost)

        default:
            return nil
        }
    }
}
