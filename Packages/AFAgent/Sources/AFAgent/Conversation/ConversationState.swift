import Foundation
import AFCore

@Observable
@MainActor
public final class ConversationState {
    public let nodeID: UUID
    public var messages: [ConversationMessage] = []
    public var isStreaming: Bool = false
    public var streamingText: String = ""
    public var inputText: String = ""
    public var error: String?
    public var sessionID: String?
    public var totalCostUSD: Double = 0
    public var totalInputTokens: Int = 0
    public var totalOutputTokens: Int = 0

    public init(nodeID: UUID) {
        self.nodeID = nodeID
    }

    public func appendUserMessage(_ text: String) {
        let message = ConversationMessage(
            role: .user,
            content: [.text(text)]
        )
        messages.append(message)
    }

    public func startStreaming() {
        isStreaming = true
        streamingText = ""
        error = nil
    }

    public func appendStreamDelta(_ delta: String) {
        streamingText += delta
    }

    public func finishStreaming() {
        if !streamingText.isEmpty {
            let message = ConversationMessage(
                role: .assistant,
                content: [.text(streamingText)]
            )
            messages.append(message)
        }
        streamingText = ""
        isStreaming = false
    }

    public func setError(_ errorMessage: String) {
        error = errorMessage
        isStreaming = false
        streamingText = ""
    }

    public func updateUsage(inputTokens: Int, outputTokens: Int, costUSD: Double?) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        if let cost = costUSD {
            totalCostUSD += cost
        }
    }

    public var reportedContextWindow: Int?

    public func setUsageTotal(totalTokens: Int, contextWindow: Int) {
        totalInputTokens = totalTokens
        totalOutputTokens = 0
        if contextWindow > 0 { reportedContextWindow = contextWindow }
    }
}
