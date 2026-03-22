import Foundation
import AFCore

// MARK: - Provider Protocol

public enum ProviderSessionPhase: String, Codable, Sendable {
    case idle
    case preparing
    case responding
    case cancelling
    case failed

    public var isWorking: Bool {
        switch self {
        case .preparing, .responding, .cancelling:
            true
        case .idle, .failed:
            false
        }
    }

    public var statusLabel: String {
        switch self {
        case .idle:
            "Idle"
        case .preparing:
            "Starting"
        case .responding:
            "Working"
        case .cancelling:
            "Stopping"
        case .failed:
            "Error"
        }
    }
}

public enum ProviderLifecycleEvent: Sendable, Equatable {
    case turnStarted(turnID: String?)
}

public struct ProviderStreamHandle: Sendable {
    public let stream: AsyncThrowingStream<StreamEvent, Error>
    public let cancel: @Sendable () async -> Void

    public init(
        stream: AsyncThrowingStream<StreamEvent, Error>,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.stream = stream
        self.cancel = cancel
    }
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var availableModels: [AIModel] { get }

    func sendMessage(
        prompt: String,
        messages: [ConversationMessage],
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?
    ) -> ProviderStreamHandle
}

// MARK: - AI Model

public struct AIModel: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var contextWindow: Int
    public var supportsTools: Bool
    public var supportsVision: Bool

    public init(
        id: String,
        name: String,
        contextWindow: Int = 200_000,
        supportsTools: Bool = true,
        supportsVision: Bool = true
    ) {
        self.id = id
        self.name = name
        self.contextWindow = contextWindow
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
    }
}

// MARK: - Stream Events

public enum StreamEvent: Sendable {
    case initialized(sessionID: String, model: String)
    case lifecycle(ProviderLifecycleEvent)
    case textDelta(String)
    case text(String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(id: String, content: String, isError: Bool)
    case usage(inputTokens: Int, outputTokens: Int, costUSD: Double?)
    case contextUsage(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int,
        contextWindow: Int?
    )
    case usageTotal(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int,
        contextWindow: Int?
    )
    case done(stopReason: String)
    case error(String)
}

// MARK: - Provider Registry

@Observable
@MainActor
public final class ProviderRegistry {
    public private(set) var providers: [String: any AIProvider] = [:]

    public init() {}

    public func register(_ provider: any AIProvider) {
        providers[provider.id] = provider
    }

    public func provider(for id: String) -> (any AIProvider)? {
        providers[id]
    }

    public var allProviders: [any AIProvider] {
        Array(providers.values)
    }
}
