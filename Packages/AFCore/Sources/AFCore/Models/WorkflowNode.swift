import CoreGraphics
import Foundation

// MARK: - Node Kind

public enum NodeKind: String, Codable, Sendable, CaseIterable {
    case agent
    case terminal
}

// MARK: - Node Position

public struct NodePosition: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    public var rect: CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    public init(x: Double = 0, y: Double = 0, width: Double = 520, height: Double = 620) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Execution State

public enum NodeExecutionState: String, Codable, Sendable {
    case idle
    case running
    case success
    case failure
    case waitingForApproval
}

// MARK: - Agent Mode & Access

public enum AgentMode: String, Codable, Sendable, CaseIterable {
    case auto
    case plan
}

public enum AgentAccess: String, Codable, Sendable, CaseIterable {
    case supervised
    case acceptEdits
    case fullAccess
}

// MARK: - Node Configuration

public struct NodeConfiguration: Codable, Sendable, Equatable {
    public var providerID: String?
    public var modelID: String?
    public var effort: String?
    public var systemPrompt: String?
    public var temperature: Double?
    public var maxTokens: Int?
    public var language: String?
    public var script: String?
    public var conditionExpression: String?
    public var triggerType: String?
    public var cronExpression: String?
    public var transformExpression: String?
    public var toolName: String?
    public var toolParameters: [String: String]?
    public var agentMode: AgentMode?
    public var agentAccess: AgentAccess?
    public var contextWindowSize: Int?

    public var resolvedMode: AgentMode {
        agentMode ?? .auto
    }

    public var resolvedAccess: AgentAccess {
        if let agentAccess { return agentAccess }
        if let raw = UserDefaults.standard.string(forKey: "defaultAccess"),
           let access = AgentAccess(rawValue: raw) {
            return access
        }
        return .fullAccess
    }

    public init(
        providerID: String? = nil,
        modelID: String? = nil,
        effort: String? = nil,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        language: String? = nil,
        script: String? = nil,
        conditionExpression: String? = nil,
        triggerType: String? = nil,
        cronExpression: String? = nil,
        transformExpression: String? = nil,
        toolName: String? = nil,
        toolParameters: [String: String]? = nil,
        agentMode: AgentMode? = nil,
        agentAccess: AgentAccess? = nil,
        contextWindowSize: Int? = nil
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.effort = effort
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.language = language
        self.script = script
        self.conditionExpression = conditionExpression
        self.triggerType = triggerType
        self.cronExpression = cronExpression
        self.transformExpression = transformExpression
        self.toolName = toolName
        self.toolParameters = toolParameters
        self.agentMode = agentMode
        self.agentAccess = agentAccess
        self.contextWindowSize = contextWindowSize
    }

    // MARK: - Backward Compatible Decoding

    private enum CodingKeys: String, CodingKey {
        case providerID, modelID, effort, systemPrompt, temperature, maxTokens
        case language, script, conditionExpression, triggerType, cronExpression
        case transformExpression, toolName, toolParameters
        case agentMode, agentAccess
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try c.decodeIfPresent(String.self, forKey: .providerID)
        modelID = try c.decodeIfPresent(String.self, forKey: .modelID)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        script = try c.decodeIfPresent(String.self, forKey: .script)
        conditionExpression = try c.decodeIfPresent(String.self, forKey: .conditionExpression)
        triggerType = try c.decodeIfPresent(String.self, forKey: .triggerType)
        cronExpression = try c.decodeIfPresent(String.self, forKey: .cronExpression)
        transformExpression = try c.decodeIfPresent(String.self, forKey: .transformExpression)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        toolParameters = try c.decodeIfPresent([String: String].self, forKey: .toolParameters)

        agentMode = try c.decodeIfPresent(AgentMode.self, forKey: .agentMode)
        agentAccess = try c.decodeIfPresent(AgentAccess.self, forKey: .agentAccess)

        // Migrate from legacy triggerType when new fields are absent
        if agentMode == nil, agentAccess == nil, let legacy = triggerType {
            switch legacy {
            case "plan":
                agentMode = .plan
                agentAccess = .fullAccess
            case "acceptEdits":
                agentMode = .auto
                agentAccess = .acceptEdits
            case "bypassPermissions":
                agentMode = .auto
                agentAccess = .fullAccess
            case "default":
                agentMode = .auto
                agentAccess = .supervised
            default: // "auto" or anything else
                agentMode = .auto
                agentAccess = .fullAccess
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(providerID, forKey: .providerID)
        try c.encodeIfPresent(modelID, forKey: .modelID)
        try c.encodeIfPresent(effort, forKey: .effort)
        try c.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(script, forKey: .script)
        try c.encodeIfPresent(conditionExpression, forKey: .conditionExpression)
        try c.encodeIfPresent(cronExpression, forKey: .cronExpression)
        try c.encodeIfPresent(transformExpression, forKey: .transformExpression)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(toolParameters, forKey: .toolParameters)
        try c.encodeIfPresent(agentMode, forKey: .agentMode)
        try c.encodeIfPresent(agentAccess, forKey: .agentAccess)

        // Write legacy triggerType for backward compat
        let legacy: String? = {
            let mode = resolvedMode
            let access = resolvedAccess
            if mode == .plan { return "plan" }
            switch access {
            case .supervised: return "default"
            case .acceptEdits: return "acceptEdits"
            case .fullAccess: return "bypassPermissions"
            }
        }()
        try c.encodeIfPresent(legacy, forKey: .triggerType)
    }
}

// MARK: - Workflow Node

public struct WorkflowNode: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: NodeKind
    public var title: String
    public var position: NodePosition
    public var isCollapsed: Bool
    public var configuration: NodeConfiguration
    public var executionState: NodeExecutionState

    public init(
        id: UUID = UUID(),
        kind: NodeKind,
        title: String,
        position: NodePosition = NodePosition(),
        isCollapsed: Bool = false,
        configuration: NodeConfiguration = NodeConfiguration(),
        executionState: NodeExecutionState = .idle
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.position = position
        self.isCollapsed = isCollapsed
        self.configuration = configuration
        self.executionState = executionState
    }
}

extension WorkflowNode {
    public var iconName: String {
        switch kind {
        case .agent: "brain"
        case .terminal: "terminal"
        }
    }

    public var accentColorName: String {
        switch kind {
        case .agent: "purple"
        case .terminal: "blue"
        }
    }

    public static func defaultSize(for kind: NodeKind) -> (width: Double, height: Double) {
        switch kind {
        case .agent: (560, 680)
        case .terminal: (560, 680)
        }
    }
}
