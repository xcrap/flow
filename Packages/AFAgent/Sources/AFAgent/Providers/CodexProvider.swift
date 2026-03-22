import Foundation
import AFCore

public final class CodexProvider: AIProvider, Sendable {
    public let id = "codex"
    public let displayName = "Codex (OpenAI)"
    public let availableModels: [AIModel] = [
        AIModel(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 200_000),
    ]

    // Shared persistent state across messages
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var writer: FileHandle?
    nonisolated(unsafe) private var threadID: String?
    nonisolated(unsafe) private var nextID: Int = 10
    nonisolated(unsafe) private var activeCont: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    nonisolated(unsafe) private var initialized = false

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
            Task { @MainActor in
                // Start server if not running
                if self.process == nil || self.process?.isRunning != true {
                    self.startServer(workingDirectory: workingDirectory, systemPrompt: systemPrompt)

                    // Wait for thread
                    for _ in 0..<200 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if self.threadID != nil { break }
                    }
                }

                guard let tid = self.threadID else {
                    continuation.yield(.error("Codex thread not ready. Try again."))
                    continuation.finish()
                    return
                }

                // Set active continuation
                self.activeCont = continuation
                continuation.yield(.initialized(sessionID: tid, model: model))

                // Send turn
                self.nextID += 1
                self.writeJSON("turn/start", id: self.nextID, params: [
                    "threadId": tid,
                    "input": [["type": "text", "text": prompt]]
                ])
            }
        }
    }

    public func cancel() async {
        process?.terminate()
        process = nil
        threadID = nil
        initialized = false
    }

    // MARK: - Server

    private static func findCodex() -> URL {
        for p in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(NSHomeDirectory())/.local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    }

    private func writeJSON(_ method: String, id: Int, params: [String: Any]) {
        guard let writer else { return }
        let msg: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id, "params": params]
        if let data = try? JSONSerialization.data(withJSONObject: msg),
           var str = String(data: data, encoding: .utf8) {
            str += "\n"
            writer.write(str.data(using: .utf8)!)
        }
    }

    private func startServer(workingDirectory: URL?, systemPrompt: String?) {
        let proc = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        proc.executableURL = Self.findCodex()
        proc.arguments = ["app-server"]
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        proc.environment = env
        if let workingDirectory { proc.currentDirectoryURL = workingDirectory }

        self.process = proc
        self.writer = stdinPipe.fileHandleForWriting
        self.threadID = nil
        self.initialized = false

        do { try proc.run() } catch { return }

        let sysPrompt = systemPrompt

        // Read stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                handle.readabilityHandler = nil
                return
            }

            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                // Init response → start thread
                if let respID = json["id"] as? Int, respID == 0 {
                    var tp: [String: Any] = ["approvalPolicy": "never", "sandbox": "danger-full-access"]
                    if let sp = sysPrompt, !sp.isEmpty { tp["developerInstructions"] = sp }
                    self?.writeJSON("thread/start", id: 1, params: tp)
                }

                // Thread response → store ID
                if let respID = json["id"] as? Int, respID == 1,
                   let result = json["result"] as? [String: Any],
                   let thread = result["thread"] as? [String: Any],
                   let tid = thread["id"] as? String {
                    self?.threadID = tid
                }

                // Notifications
                if let method = json["method"] as? String {
                    let params = json["params"] as? [String: Any] ?? [:]

                    switch method {
                    case "item/agentMessage/delta":
                        if let delta = params["delta"] as? String {
                            self?.activeCont?.yield(.textDelta(delta))
                        }
                    case "turn/completed":
                        self?.activeCont?.yield(.done(stopReason: "end_turn"))
                        self?.activeCont?.finish()
                        self?.activeCont = nil
                    case "thread/tokenUsage/updated":
                        if let usage = params["tokenUsage"] as? [String: Any],
                           let total = usage["total"] as? [String: Any] {
                            self?.activeCont?.yield(.usageTotal(
                                inputTokens: total["inputTokens"] as? Int ?? 0,
                                outputTokens: total["outputTokens"] as? Int ?? 0
                            ))
                        }
                    case "item/started":
                        if let item = params["item"] as? [String: Any] {
                            let type = item["type"] as? String ?? ""
                            if type == "toolCall" || type == "commandExecution" {
                                let name = item["name"] as? String ?? item["command"] as? String ?? type
                                self?.activeCont?.yield(.toolUse(id: item["id"] as? String ?? "", name: name, input: ""))
                            }
                        }
                    default: break
                    }
                }

                // Auto-approve server requests
                if let reqID = json["id"], json["method"] != nil,
                   let method = json["method"] as? String,
                   method.contains("requestApproval") || method.contains("Approval") || method == "item/tool/call" {
                    let resp: [String: Any] = ["jsonrpc": "2.0", "id": reqID, "result": ["approved": true]]
                    if let d = try? JSONSerialization.data(withJSONObject: resp),
                       var s = String(data: d, encoding: .utf8) {
                        s += "\n"
                        self?.writer?.write(s.data(using: .utf8)!)
                    }
                }

                // Errors
                if let error = json["error"] as? [String: Any], json["method"] == nil {
                    self?.activeCont?.yield(.error(error["message"] as? String ?? "Unknown error"))
                }
            }
        }

        // Send initialize
        writeJSON("initialize", id: 0, params: [
            "clientInfo": ["name": "AgentFlow", "version": "1.0"]
        ])
    }
}
