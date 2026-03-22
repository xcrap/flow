import Foundation
import AFCore

@MainActor
public final class ConversationService {
    private let registry: ProviderRegistry
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    public init(registry: ProviderRegistry) {
        self.registry = registry
    }

    public func send(
        prompt: String,
        to conversationState: ConversationState,
        providerID: String,
        model: String,
        effort: String? = nil,
        systemPrompt: String? = nil,
        permissionMode: String? = nil,
        workingDirectory: URL? = nil,
        resumeSessionID: String? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        cancelStreaming(for: conversationState.nodeID)

        conversationState.appendUserMessage(prompt)
        conversationState.startStreaming()

        guard let provider = registry.provider(for: providerID) else {
            conversationState.setError("Provider '\(providerID)' not found. Configure it in Settings.")
            onComplete?()
            return
        }

        let task = Task {
            let stream = provider.sendMessage(
                prompt: prompt,
                messages: conversationState.messages,
                model: model,
                effort: effort,
                systemPrompt: systemPrompt,
                permissionMode: permissionMode,
                workingDirectory: workingDirectory,
                resumeSessionID: resumeSessionID ?? conversationState.sessionID
            )

            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .initialized(let sessionID, _):
                        conversationState.sessionID = sessionID

                    case .textDelta(let delta):
                        conversationState.appendStreamDelta(delta)

                    case .text(let text):
                        conversationState.appendStreamDelta(text)

                    case .toolUse(let id, let name, let input):
                        let toolMsg = ConversationMessage(
                            role: .assistant,
                            content: [.toolUse(id: id, name: name, input: input)]
                        )
                        if !conversationState.streamingText.isEmpty {
                            conversationState.finishStreaming()
                            conversationState.startStreaming()
                        }
                        conversationState.messages.append(toolMsg)

                    case .toolResult(let id, let content, let isError):
                        let resultMsg = ConversationMessage(
                            role: .tool,
                            content: [.toolResult(id: id, content: content, isError: isError)]
                        )
                        conversationState.messages.append(resultMsg)

                    case .usage(let inputTokens, let outputTokens, let costUSD):
                        conversationState.updateUsage(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            costUSD: costUSD
                        )

                    case .usageTotal(let inputTokens, let outputTokens):
                        conversationState.setUsage(inputTokens: inputTokens, outputTokens: outputTokens)

                    case .done:
                        conversationState.finishStreaming()

                    case .error(let message):
                        conversationState.setError(message)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    conversationState.setError(error.localizedDescription)
                }
            }

            conversationState.finishStreaming()
            activeTasks[conversationState.nodeID] = nil
            onComplete?()
        }

        activeTasks[conversationState.nodeID] = task
    }

    public func cancelStreaming(for nodeID: UUID) {
        activeTasks[nodeID]?.cancel()
        activeTasks[nodeID] = nil
    }
}
