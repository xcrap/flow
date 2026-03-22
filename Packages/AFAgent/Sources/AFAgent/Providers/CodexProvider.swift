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
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = Self.findCodex()
        process.arguments = ["app-server", "--transport", "stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

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

        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading

        // Send JSON-RPC message
        let writeMsg = { (method: String, id: Int, params: [String: Any]) in
            let msg: [String: Any] = ["method": method, "id": id, "params": params]
            if let data = try? JSONSerialization.data(withJSONObject: msg),
               var str = String(data: data, encoding: .utf8) {
                str += "\n"
                writer.write(str.data(using: .utf8)!)
            }
        }

        // Start thread
        var threadParams: [String: Any] = ["model": model]
        if let systemPrompt, !systemPrompt.isEmpty {
            threadParams["instructions"] = systemPrompt
        }
        writeMsg("thread/start", 1, threadParams)

        continuation.yield(.initialized(sessionID: "", model: model))

        // Read all responses synchronously on a detached task
        let promptCopy = prompt
        nonisolated(unsafe) let writeRef = writeMsg
        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var threadStarted = false
            nonisolated(unsafe) var finished = false

            reader.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    if !finished {
                        finished = true
                        continuation.yield(.done(stopReason: "end_turn"))
                        continuation.finish()
                        outerCont.resume()
                    }
                    return
                }

                guard let text = String(data: data, encoding: .utf8) else { return }

                for line in text.components(separatedBy: "\n") where !line.isEmpty {
                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { continue }

                    // Response to thread/start (id: 1)
                    if let respID = json["id"] as? Int, respID == 1,
                       let result = json["result"] as? [String: Any],
                       let thread = result["thread"] as? [String: Any],
                       let tid = thread["id"] as? String, !threadStarted {
                        threadStarted = true
                        continuation.yield(.initialized(sessionID: tid, model: model))
                        writeRef("turn/start", 2, ["thread_id": tid, "content": promptCopy])
                    }

                    // Notifications
                    if let method = json["method"] as? String {
                        let params = json["params"] as? [String: Any] ?? [:]

                        switch method {
                        case "turn/message_delta":
                            if let delta = params["delta"] as? String {
                                continuation.yield(.textDelta(delta))
                            }
                        case "turn/completed":
                            let usage = params["usage"] as? [String: Any]
                            continuation.yield(.usage(
                                inputTokens: usage?["input_tokens"] as? Int ?? 0,
                                outputTokens: usage?["output_tokens"] as? Int ?? 0,
                                costUSD: nil
                            ))
                            if !finished {
                                finished = true
                                continuation.yield(.done(stopReason: "end_turn"))
                                continuation.finish()
                                handle.readabilityHandler = nil
                                outerCont.resume()
                            }
                        case "item/tool_use":
                            continuation.yield(.toolUse(
                                id: params["id"] as? String ?? "",
                                name: params["name"] as? String ?? "",
                                input: params["input"] as? String ?? "{}"
                            ))
                        case "turn/error":
                            continuation.yield(.error(params["message"] as? String ?? "Unknown error"))
                        default:
                            break
                        }
                    }

                    // Error responses
                    if let error = json["error"] as? [String: Any] {
                        continuation.yield(.error(error["message"] as? String ?? "Unknown error"))
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
