import Foundation
import AFCore

private actor TaskHolder {
    var task: Task<Void, Never>?

    func set(_ t: Task<Void, Never>?) { task = t }
    func cancel() { task?.cancel(); task = nil }
}

public final class OpenAIProvider: AIProvider, Sendable {
    public let id = "openai"
    public let displayName = "OpenAI"

    public let availableModels: [AIModel] = [
        AIModel(id: "gpt-4o", name: "GPT-4o", contextWindow: 128_000, supportsVision: true),
        AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", contextWindow: 128_000, supportsVision: true),
        AIModel(id: "o3", name: "o3", contextWindow: 200_000, supportsVision: true),
        AIModel(id: "o4-mini", name: "o4-mini", contextWindow: 200_000, supportsVision: true),
    ]

    private let apiKey: String
    private let baseURL: URL
    private let holder = TaskHolder()

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func sendMessage(
        prompt: String,
        messages: [ConversationMessage],
        model: String,
        effort: String?,
        systemPrompt: String?,
        workingDirectory: URL?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.streamChat(
                        prompt: prompt,
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        continuation: continuation
                    )
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish(throwing: error)
                    }
                }
            }
            Task { await holder.set(task) }
        }
    }

    public func cancel() async {
        await holder.cancel()
    }

    // MARK: - Private

    private func streamChat(
        prompt: String,
        messages: [ConversationMessage],
        model: String,
        systemPrompt: String?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var requestMessages: [[String: Any]] = []

        if let systemPrompt, !systemPrompt.isEmpty {
            requestMessages.append(["role": "system", "content": systemPrompt])
        }

        for msg in messages {
            let role: String = switch msg.role {
            case .user: "user"
            case .assistant: "assistant"
            case .system: "system"
            case .tool: "tool"
            }
            requestMessages.append(["role": role, "content": msg.textContent])
        }

        requestMessages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": requestMessages,
            "stream": true,
        ]

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.yield(.error("Invalid response"))
            continuation.finish()
            return
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            continuation.yield(.error("HTTP \(httpResponse.statusCode): \(errorBody)"))
            continuation.finish()
            return
        }

        continuation.yield(.initialized(sessionID: UUID().uuidString, model: model))

        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            if jsonStr == "[DONE]" {
                continuation.yield(.done(stopReason: "end_turn"))
                continuation.finish()
                return
            }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first
            else { continue }

            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String
            {
                continuation.yield(.textDelta(content))
            }

            if let finishReason = choice["finish_reason"] as? String, finishReason == "stop" {
                continuation.yield(.done(stopReason: "end_turn"))
                continuation.finish()
                return
            }
        }

        continuation.yield(.done(stopReason: "end_turn"))
        continuation.finish()
    }
}
