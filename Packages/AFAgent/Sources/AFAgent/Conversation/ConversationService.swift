import Foundation
import AFCore

@MainActor
public final class ConversationService {
    private struct PendingRequest {
        let prompt: String
        let providerID: String
        let model: String
        let effort: String?
        let systemPrompt: String?
        let permissionMode: String?
        let workingDirectory: URL?
        let resumeSessionID: String?
        let onComplete: (() -> Void)?
        let queued: Bool
    }

    private struct ActiveRequest {
        let task: Task<Void, Never>
        let cancel: @Sendable () async -> Void
    }

    private let registry: ProviderRegistry
    private var activeRequests: [UUID: ActiveRequest] = [:]
    private var activeStates: [UUID: ConversationState] = [:]
    private var pendingRequests: [UUID: [PendingRequest]] = [:]

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
        let isQueued = activeRequests[conversationState.nodeID] != nil

        let request = PendingRequest(
            prompt: prompt,
            providerID: providerID,
            model: model,
            effort: effort,
            systemPrompt: systemPrompt,
            permissionMode: permissionMode,
            workingDirectory: workingDirectory,
            resumeSessionID: resumeSessionID,
            onComplete: onComplete,
            queued: isQueued
        )

        if isQueued {
            conversationState.enqueuePrompt(prompt)
            pendingRequests[conversationState.nodeID, default: []].append(request)
            return
        }

        conversationState.appendUserMessage(prompt)
        start(request, for: conversationState)
    }

    public func clearPendingRequests(for nodeID: UUID) {
        pendingRequests[nodeID] = nil
    }

    public func cancelStreaming(for nodeID: UUID) {
        guard let activeRequest = activeRequests[nodeID] else { return }
        activeStates[nodeID]?.markCancellationRequested()
        activeRequest.task.cancel()
        Task {
            await activeRequest.cancel()
        }
    }

    private func start(_ request: PendingRequest, for conversationState: ConversationState) {
        if request.queued {
            conversationState.beginQueuedPrompt()
            conversationState.appendUserMessage(request.prompt)
        }

        conversationState.startStreaming(
            providerID: request.providerID,
            modelID: request.model
        )

        guard let provider = registry.provider(for: request.providerID) else {
            conversationState.setError("Provider '\(request.providerID)' not found. Configure it in Settings.")
            request.onComplete?()
            startNextRequestIfNeeded(for: conversationState)
            return
        }

        if let contextWindow = provider.availableModels.first(where: { $0.id == request.model })?.contextWindow,
           contextWindow > 0
        {
            conversationState.reportedContextWindow = contextWindow
        }

        let handle = provider.sendMessage(
            prompt: request.prompt,
            messages: conversationState.messages,
            model: request.model,
            effort: request.effort,
            systemPrompt: request.systemPrompt,
            permissionMode: request.permissionMode,
            workingDirectory: request.workingDirectory,
            resumeSessionID: request.resumeSessionID ?? conversationState.sessionID
        )

        let nodeID = conversationState.nodeID
        activeStates[nodeID] = conversationState
        let task = Task { [weak self] in
            var didReceiveCompletion = false
            var didReceiveError = false

            do {
                for try await event in handle.stream {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .initialized(let sessionID, let model):
                        conversationState.registerSession(sessionID, modelID: model)

                    case .lifecycle(let lifecycleEvent):
                        switch lifecycleEvent {
                        case .turnStarted(let turnID):
                            conversationState.markTurnStarted(turnID: turnID)
                        }

                    case .textDelta(let delta):
                        conversationState.appendStreamDelta(delta)

                    case .text(let text):
                        conversationState.appendStreamDelta(text)

                    case .toolUse(let id, let name, let input):
                        let toolMessage = ConversationMessage(
                            role: .assistant,
                            content: [.toolUse(id: id, name: name, input: input)]
                        )
                        if !conversationState.streamingText.isEmpty {
                            let activeTurnID = conversationState.activeTurnID
                            conversationState.finishStreaming()
                            conversationState.startStreaming(
                                providerID: conversationState.activeProviderID,
                                modelID: conversationState.activeModelID
                            )
                            conversationState.markTurnStarted(turnID: activeTurnID)
                        }
                        conversationState.messages.append(toolMessage)

                    case .toolResult(let id, let content, let isError):
                        let resultMessage = ConversationMessage(
                            role: .tool,
                            content: [.toolResult(id: id, content: content, isError: isError)]
                        )
                        conversationState.messages.append(resultMessage)

                    case .usage(let inputTokens, let outputTokens, let costUSD):
                        conversationState.updateUsage(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            costUSD: costUSD
                        )
                        if conversationState.currentContextTokens == nil,
                           conversationState.reportedContextWindow != nil
                        {
                            conversationState.setCurrentContextUsage(
                                inputTokens: inputTokens,
                                outputTokens: outputTokens,
                                cachedInputTokens: 0,
                                reasoningOutputTokens: 0,
                                totalTokens: inputTokens + outputTokens,
                                contextWindow: conversationState.reportedContextWindow
                            )
                        }

                    case .contextUsage(
                        let inputTokens,
                        let outputTokens,
                        let cachedInputTokens,
                        let reasoningOutputTokens,
                        let totalTokens,
                        let contextWindow
                    ):
                        conversationState.setCurrentContextUsage(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            cachedInputTokens: cachedInputTokens,
                            reasoningOutputTokens: reasoningOutputTokens,
                            totalTokens: totalTokens,
                            contextWindow: contextWindow
                        )

                    case .usageTotal(
                        let inputTokens,
                        let outputTokens,
                        let cachedInputTokens,
                        let reasoningOutputTokens,
                        let totalTokens,
                        let contextWindow
                    ):
                        conversationState.setUsageTotals(
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            cachedInputTokens: cachedInputTokens,
                            reasoningOutputTokens: reasoningOutputTokens,
                            totalTokens: totalTokens,
                            contextWindow: contextWindow
                        )

                    case .done(let stopReason):
                        didReceiveCompletion = true
                        conversationState.finishStreaming(stopReason: stopReason)

                    case .error(let message):
                        didReceiveError = true
                        conversationState.setError(message)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    didReceiveError = true
                    conversationState.setError(error.localizedDescription)
                }
            }

            if Task.isCancelled {
                conversationState.finishStreaming(stopReason: "cancelled")
            } else if !didReceiveCompletion && !didReceiveError {
                conversationState.finishStreaming()
            }

            guard let self else {
                request.onComplete?()
                return
            }

            self.activeRequests[nodeID] = nil
            self.activeStates[nodeID] = nil
            request.onComplete?()
            self.startNextRequestIfNeeded(for: conversationState)
        }

        activeRequests[nodeID] = ActiveRequest(task: task, cancel: handle.cancel)
    }

    private func startNextRequestIfNeeded(for conversationState: ConversationState) {
        let nodeID = conversationState.nodeID
        guard activeRequests[nodeID] == nil else { return }
        guard var queue = pendingRequests[nodeID], !queue.isEmpty else {
            pendingRequests[nodeID] = nil
            return
        }

        let next = queue.removeFirst()
        pendingRequests[nodeID] = queue.isEmpty ? nil : queue
        start(next, for: conversationState)
    }
}
