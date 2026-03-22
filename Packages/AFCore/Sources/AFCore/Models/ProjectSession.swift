import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case failed
}

public struct ExecutionLogEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var nodeID: UUID
    public var timestamp: Date
    public var event: String
    public var data: String?

    public init(
        id: UUID = UUID(),
        nodeID: UUID,
        timestamp: Date = Date(),
        event: String,
        data: String? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.timestamp = timestamp
        self.event = event
        self.data = data
    }
}

public struct ProjectSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var projectID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public var executionLog: [ExecutionLogEntry]

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus = .active,
        executionLog: [ExecutionLogEntry] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.executionLog = executionLog
    }
}
