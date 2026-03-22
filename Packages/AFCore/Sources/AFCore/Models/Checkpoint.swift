import Foundation

public struct Checkpoint: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var projectID: UUID
    public var label: String
    public var timestamp: Date
    public var snapshotData: Data

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        label: String,
        timestamp: Date = Date(),
        snapshotData: Data = Data()
    ) {
        self.id = id
        self.projectID = projectID
        self.label = label
        self.timestamp = timestamp
        self.snapshotData = snapshotData
    }
}
