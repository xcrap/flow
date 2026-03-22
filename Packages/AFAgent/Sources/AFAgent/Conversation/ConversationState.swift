import Foundation
import AFCore

@Observable
@MainActor
public final class ConversationState {
    public let nodeID: UUID
    public var messages: [ConversationMessage] = []
    public var runtimePhase: ProviderSessionPhase = .idle
    public var streamingText: String = ""
    public var inputText: String = ""
    public var error: String?
    public var sessionID: String?
    public var activeProviderID: String?
    public var activeModelID: String?
    public var activeTurnID: String?
    public var lastStopReason: String?
    public var lastRuntimeEventAt: Date?
    public var totalCostUSD: Double = 0
    public var totalInputTokens: Int = 0
    public var totalOutputTokens: Int = 0
    public var totalCachedInputTokens: Int = 0
    public var totalReasoningOutputTokens: Int = 0
    public var totalTokens: Int = 0
    public var reportedContextWindow: Int?
    public var currentContextTokens: Int?
    public var queuedPromptCount: Int = 0
    public var queuedPromptPreviews: [String] = []

    public init(nodeID: UUID) {
        self.nodeID = nodeID
    }

    public var isStreaming: Bool {
        runtimePhase.isWorking
    }

    public var statusLabel: String {
        runtimePhase.statusLabel
    }

    public func appendUserMessage(_ text: String) {
        let message = ConversationMessage(
            role: .user,
            content: [.text(text)]
        )
        messages.append(message)
    }

    public func startStreaming(providerID: String? = nil, modelID: String? = nil) {
        runtimePhase = .preparing
        streamingText = ""
        error = nil
        currentContextTokens = nil
        activeTurnID = nil
        lastStopReason = nil
        lastRuntimeEventAt = Date()
        if let providerID {
            activeProviderID = providerID
        }
        if let modelID {
            activeModelID = modelID
        }
    }

    public func registerSession(_ sessionID: String, modelID: String? = nil) {
        self.sessionID = sessionID
        if let modelID, !modelID.isEmpty {
            activeModelID = modelID
        }
        lastRuntimeEventAt = Date()
    }

    public func markTurnStarted(turnID: String? = nil) {
        if let turnID, !turnID.isEmpty {
            activeTurnID = turnID
        }
        if runtimePhase != .cancelling {
            runtimePhase = .responding
        }
        lastRuntimeEventAt = Date()
    }

    public func markCancellationRequested() {
        guard isStreaming else { return }
        runtimePhase = .cancelling
        lastRuntimeEventAt = Date()
    }

    public func appendStreamDelta(_ delta: String) {
        if runtimePhase == .preparing {
            runtimePhase = .responding
        }
        lastRuntimeEventAt = Date()
        streamingText += delta
    }

    public func finishStreaming(stopReason: String? = nil) {
        if !streamingText.isEmpty {
            let message = ConversationMessage(
                role: .assistant,
                content: [.text(streamingText)]
            )
            messages.append(message)
        }
        streamingText = ""
        runtimePhase = .idle
        activeTurnID = nil
        if let stopReason, !stopReason.isEmpty {
            lastStopReason = stopReason
        }
        lastRuntimeEventAt = Date()
    }

    public func setError(_ errorMessage: String) {
        error = errorMessage
        streamingText = ""
        runtimePhase = .failed
        activeTurnID = nil
        lastRuntimeEventAt = Date()
    }

    public func updateUsage(inputTokens: Int, outputTokens: Int, costUSD: Double?) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        totalTokens = totalInputTokens + totalOutputTokens + totalCachedInputTokens + totalReasoningOutputTokens
        if let cost = costUSD {
            totalCostUSD += cost
        }
    }

    public func setUsageTotals(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int,
        contextWindow: Int?
    ) {
        totalInputTokens = inputTokens
        totalOutputTokens = outputTokens
        totalCachedInputTokens = cachedInputTokens
        totalReasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        if let contextWindow, contextWindow > 0 {
            reportedContextWindow = contextWindow
        }
    }

    public func setCurrentContextUsage(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int,
        contextWindow: Int?
    ) {
        currentContextTokens = max(
            totalTokens,
            inputTokens + outputTokens + cachedInputTokens + reasoningOutputTokens
        )
        if let contextWindow, contextWindow > 0 {
            reportedContextWindow = contextWindow
        }
    }

    public func enqueuePrompt(_ prompt: String) {
        let preview = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        queuedPromptPreviews.append(preview)
        queuedPromptCount = queuedPromptPreviews.count
    }

    @discardableResult
    public func beginQueuedPrompt() -> String? {
        guard !queuedPromptPreviews.isEmpty else {
            queuedPromptCount = 0
            return nil
        }

        let prompt = queuedPromptPreviews.removeFirst()
        queuedPromptCount = queuedPromptPreviews.count
        return prompt
    }

    public func clearQueuedPrompts() {
        queuedPromptPreviews.removeAll()
        queuedPromptCount = 0
    }

    public func resetConversation() {
        messages.removeAll()
        runtimePhase = .idle
        streamingText = ""
        inputText = ""
        error = nil
        sessionID = nil
        activeProviderID = nil
        activeModelID = nil
        activeTurnID = nil
        lastStopReason = nil
        lastRuntimeEventAt = nil
        totalCostUSD = 0
        totalInputTokens = 0
        totalOutputTokens = 0
        totalCachedInputTokens = 0
        totalReasoningOutputTokens = 0
        totalTokens = 0
        reportedContextWindow = nil
        currentContextTokens = nil
        queuedPromptCount = 0
        queuedPromptPreviews.removeAll()
    }

    public var lastActivityAt: Date? {
        messages.last?.timestamp
    }

    public var latestUserPrompt: String? {
        messages
            .reversed()
            .first(where: { $0.role == .user })?
            .textContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var latestPreviewText: String? {
        if let latestUserPrompt, !latestUserPrompt.isEmpty {
            return latestUserPrompt
        }

        return messages
            .reversed()
            .compactMap { message in
                let text = message.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            .first
    }

    public var nextQueuedPromptPreview: String? {
        queuedPromptPreviews.first
    }

    public var visibleQueuedPromptPreviews: [String] {
        Array(queuedPromptPreviews.prefix(3))
    }
}
