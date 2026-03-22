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
        process.arguments = ["app-server"]
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
        let promptText = prompt

        // JSON-RPC write helper
        nonisolated(unsafe) let writeMsg = { (method: String, id: Int, params: [String: Any]) in
            let msg: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id, "params": params]
            if let data = try? JSONSerialization.data(withJSONObject: msg),
               var str = String(data: data, encoding: .utf8) {
                str += "\n"
                writer.write(str.data(using: .utf8)!)
            }
        }

        // Step 1: Initialize
        writeMsg("initialize", 0, ["clientInfo": ["name": "AgentFlow", "version": "1.0"]])

        // Step 2: Start thread (after init response)
        // Step 3: Start turn (after thread response)

        continuation.yield(.initialized(sessionID: "", model: model))

        await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var phase = 0 // 0=waiting init, 1=waiting thread, 2=streaming
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

                    // Response to initialize (id: 0)
                    if let respID = json["id"] as? Int, respID == 0, phase == 0 {
                        phase = 1
                        var threadParams: [String: Any] = [:]
                        if let systemPrompt, !systemPrompt.isEmpty {
                            threadParams["developerInstructions"] = systemPrompt
                        }
                        writeMsg("thread/start", 1, threadParams)
                        continue
                    }

                    // Response to thread/start (id: 1)
                    if let respID = json["id"] as? Int, respID == 1, phase == 1,
                       let result = json["result"] as? [String: Any],
                       let thread = result["thread"] as? [String: Any],
                       let tid = thread["id"] as? String {
                        phase = 2
                        continuation.yield(.initialized(sessionID: tid, model: model))
                        writeMsg("turn/start", 2, [
                            "threadId": tid,
                            "input": [["type": "text", "text": promptText]]
                        ])
                        continue
                    }

                    // Notifications (streaming)
                    if let method = json["method"] as? String {
                        let params = json["params"] as? [String: Any] ?? [:]

                        switch method {
                        case "item/agentMessage/delta":
                            if let delta = params["delta"] as? String {
                                continuation.yield(.textDelta(delta))
                            }

                        case "turn/completed":
                            if !finished {
                                finished = true
                                continuation.yield(.done(stopReason: "end_turn"))
                                continuation.finish()
                                handle.readabilityHandler = nil
                                outerCont.resume()
                            }

                        case "thread/tokenUsage/updated":
                            if let usage = params["tokenUsage"] as? [String: Any],
                               let total = usage["total"] as? [String: Any] {
                                let inputTokens = total["inputTokens"] as? Int ?? 0
                                let outputTokens = total["outputTokens"] as? Int ?? 0
                                continuation.yield(.usage(inputTokens: inputTokens, outputTokens: outputTokens, costUSD: nil))
                            }

                        case "item/started":
                            if let item = params["item"] as? [String: Any],
                               let type = item["type"] as? String, type == "toolCall",
                               let name = item["name"] as? String {
                                let id = item["id"] as? String ?? ""
                                continuation.yield(.toolUse(id: id, name: name, input: ""))
                            }

                        default:
                            break
                        }
                    }

                    // Error
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
