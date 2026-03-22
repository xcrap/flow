import Foundation

public struct NodeConnection: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var sourceNodeID: UUID
    public var sourcePortID: String
    public var targetNodeID: UUID
    public var targetPortID: String
    public var label: String?

    public init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePortID: String = "output",
        targetNodeID: UUID,
        targetPortID: String = "input",
        label: String? = nil
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
        self.label = label
    }
}
