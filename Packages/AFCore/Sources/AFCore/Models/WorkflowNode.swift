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
        toolParameters: [String: String]? = nil
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
