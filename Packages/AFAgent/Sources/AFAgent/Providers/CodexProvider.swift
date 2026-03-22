import Foundation
import AFCore

/// Manages a persistent codex app-server process per working directory
private actor CodexSession {
    var process: Process?
    var writer: FileHandle?
    var reader: FileHandle?
    var threadID: String?
    var initialized = false
    var nextID = 10
    nonisolated(unsafe) var pendingSetter: ((AsyncThrowingStream<StreamEvent, Error>.Continuation?) -> Void)?

    func getNextID() -> Int {
        nextID += 1
        return nextID
    }

    func setProcess(_ p: Process, writer w: FileHandle, reader r: FileHandle) {
        process = p
        writer = w
        reader = r
    }

    func setThreadID(_ id: String) { threadID = id }
    func setInitialized() { initialized = true }
    func setPendingSetter(_ s: ((AsyncThrowingStream<StreamEvent, Error>.Continuation?) -> Void)?) { pendingSetter = s }
    func setPending(_ c: AsyncThrowingStream<StreamEvent, Error>.Continuation?) { pendingSetter?(c) }

    func isAlive() -> Bool {
        process?.isRunning == true
    }

    func terminate() {
        process?.terminate()
        process = nil
        writer = nil
        reader = nil
        threadID = nil
        initialized = false
    }

    func write(_ method: String, id: Int, params: [String: Any]) {
        guard let writer else { return }
        let msg: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id, "params": params]
        if let data = try? JSONSerialization.data(withJSONObject: msg),
           var str = String(data: data, encoding: .utf8) {
            str += "\n"
            writer.write(str.data(using: .utf8)!)
        }
    }
}

public final class CodexProvider: AIProvider, Sendable {
    public let id = "codex"
    public let displayName = "Codex (OpenAI)"

    public let availableModels: [AIModel] = [
        AIModel(id: "gpt-5.4", name: "GPT-5.4", contextWindow: 200_000),
    ]

    private let session = CodexSession()

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
                    // Ensure app-server is running
                    let alive = await session.isAlive()
                    if !alive {
                        try await self.startServer(workingDirectory: workingDirectory, systemPrompt: systemPrompt)
                    }

                    // Wait for thread to be ready
                    let threadID = await session.threadID
                    guard let tid = threadID else {
                        continuation.yield(.error("Codex thread not initialized"))
                        continuation.finish()
                        return
                    }

                    // Send turn
                    let turnID = await session.getNextID()
                    await session.setPending(continuation)
                    await session.write("turn/start", id: turnID, params: [
                        "threadId": tid,
                        "input": [["type": "text", "text": prompt]]
                    ])

                    continuation.yield(.initialized(sessionID: tid, model: model))

                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    public func cancel() async {
        await session.terminate()
    }

    // MARK: - Server Lifecycle

    private static func findCodex() -> URL {
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(NSHomeDirectory())/.local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/codex")
    }

    private func startServer(workingDirectory: URL?, systemPrompt: String?) async throws {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = Self.findCodex()
        process.arguments = ["app-server"]
        process.standardInput = stdinPipe
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Log stderr for debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                print("[Codex stderr] \(text)")
            }
        }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        process.environment = env

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading

        await session.setProcess(process, writer: writer, reader: reader)

        try process.run()

        // Initialize
        await session.write("initialize", id: 0, params: [
            "clientInfo": ["name": "AgentFlow", "version": "1.0"]
        ])

        // Start reading responses
        let sessionRef = session
        let sysPrompt = systemPrompt

        // Use a dispatch-based handler to avoid Sendable issues
        nonisolated(unsafe) var pendingCont: AsyncThrowingStream<StreamEvent, Error>.Continuation?

        reader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            guard let text = String(data: data, encoding: .utf8) else { return }

            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                // Response to initialize (id: 0)
                if let respID = json["id"] as? Int, respID == 0 {
                    var threadParams: [String: Any] = [
                        "approvalPolicy": "never",
                    ]
                    if let sp = sysPrompt, !sp.isEmpty {
                        threadParams["developerInstructions"] = sp
                    }
                    let msg: [String: Any] = ["jsonrpc": "2.0", "method": "thread/start", "id": 1, "params": threadParams]
                    if let d = try? JSONSerialization.data(withJSONObject: msg),
                       var s = String(data: d, encoding: .utf8) {
                        s += "\n"
                        writer.write(s.data(using: .utf8)!)
                    }
                }

                // Response to thread/start (id: 1)
                if let respID = json["id"] as? Int, respID == 1,
                   let result = json["result"] as? [String: Any],
                   let thread = result["thread"] as? [String: Any],
                   let tid = thread["id"] as? String {
                    Task { await sessionRef.setThreadID(tid) }
                }

                // Notifications
                if let method = json["method"] as? String {
                    let params = json["params"] as? [String: Any] ?? [:]

                    switch method {
                    case "item/agentMessage/delta":
                        if let delta = params["delta"] as? String {
                            pendingCont?.yield(.textDelta(delta))
                        }
                    case "turn/completed":
                        pendingCont?.yield(.done(stopReason: "end_turn"))
                        pendingCont?.finish()
                        pendingCont = nil
                    case "thread/tokenUsage/updated":
                        if let usage = params["tokenUsage"] as? [String: Any],
                           let total = usage["total"] as? [String: Any] {
                            pendingCont?.yield(.usageTotal(
                                inputTokens: total["inputTokens"] as? Int ?? 0,
                                outputTokens: total["outputTokens"] as? Int ?? 0
                            ))
                        }
                    case "item/started":
                        if let item = params["item"] as? [String: Any],
                           let type = item["type"] as? String {
                            if type == "toolCall" || type == "commandExecution" {
                                let name = item["name"] as? String ?? item["command"] as? String ?? type
                                pendingCont?.yield(.toolUse(id: item["id"] as? String ?? "", name: name, input: ""))
                            }
                        }
                    default:
                        break
                    }
                }

                // Handle SERVER REQUESTS (need a response) — auto-approve
                if let reqID = json["id"], let method = json["method"] as? String {
                    let approvalMethods = [
                        "item/commandExecution/requestApproval",
                        "item/fileChange/requestApproval",
                        "item/permissions/requestApproval",
                        "applyPatchApproval",
                        "execCommandApproval",
                        "item/tool/call",
                    ]

                    if approvalMethods.contains(method) {
                        // Auto-approve by sending a response
                        let response: [String: Any] = [
                            "jsonrpc": "2.0",
                            "id": reqID,
                            "result": ["approved": true, "behavior": "allow"]
                        ]
                        if let d = try? JSONSerialization.data(withJSONObject: response),
                           var s = String(data: d, encoding: .utf8) {
                            s += "\n"
                            writer.write(s.data(using: .utf8)!)
                        }

                        // Show in chat
                        let params = json["params"] as? [String: Any] ?? [:]
                        let desc = params["command"] as? String ?? params["path"] as? String ?? method
                        pendingCont?.yield(.toolUse(id: "", name: "Approved", input: desc))
                    }
                }

                // Errors
                if let error = json["error"] as? [String: Any] {
                    pendingCont?.yield(.error(error["message"] as? String ?? "Unknown error"))
                }
            }
        }

        // Store the pending continuation setter for use in sendMessage
        nonisolated(unsafe) let setCont = { (c: AsyncThrowingStream<StreamEvent, Error>.Continuation?) in
            pendingCont = c
        }
        await session.setPendingSetter(setCont)

        // Wait for thread to be ready (up to 30 seconds)
        for _ in 0..<300 {
            try await Task.sleep(for: .milliseconds(100))
            let tid = await session.threadID
            if tid != nil { return }
        }

        throw NSError(domain: "CodexProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for Codex thread. Check your Codex login (run 'codex login' in terminal)."])
    }
}
