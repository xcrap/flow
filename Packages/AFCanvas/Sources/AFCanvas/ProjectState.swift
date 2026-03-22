import Foundation
import AFCore

@Observable
@MainActor
public final class ProjectState {
    public var project: Project
    public var canvasState: CanvasState
    public var selectedNodeIDs: Set<UUID> = []
    public var selectedConnectionIDs: Set<UUID> = []
    public var nodes: [UUID: WorkflowNode] = [:]
    public var connections: [UUID: NodeConnection] = [:]
    public var nodeZOrder: [UUID] = [] // back to front
    public var isExecuting: Bool = false
    // Drag tracking: stores initial positions when drag starts
    var dragStartPositions: [UUID: CGPoint] = [:]
    // Called after mutations to trigger persistence
    public var onChange: (() -> Void)?

    public init(project: Project = Project()) {
        self.project = project
        self.canvasState = CanvasState()
    }

    // MARK: - Node Operations

    @discardableResult
    public func addNode(kind: NodeKind, title: String, at position: CGPoint) -> WorkflowNode {
        let size = WorkflowNode.defaultSize(for: kind)
        let node = WorkflowNode(
            kind: kind,
            title: title,
            position: NodePosition(x: position.x, y: position.y, width: size.width, height: size.height),
            configuration: defaultConfiguration(for: kind)
        )
        nodes[node.id] = node
        nodeZOrder.append(node.id)
        onChange?()
        return node
    }

    public func removeNode(_ id: UUID) {
        nodes.removeValue(forKey: id)
        nodeZOrder.removeAll { $0 == id }
        let toRemove = connections.values.filter { $0.sourceNodeID == id || $0.targetNodeID == id }
        for connection in toRemove {
            connections.removeValue(forKey: connection.id)
        }
        selectedNodeIDs.remove(id)
        onChange?()
    }

    public func moveNode(_ id: UUID, to position: CGPoint) {
        nodes[id]?.position.x = position.x
        nodes[id]?.position.y = position.y
    }

    public func bringToFront(_ id: UUID) {
        nodeZOrder.removeAll { $0 == id }
        nodeZOrder.append(id)
    }

    // MARK: - Connection Operations

    @discardableResult
    public func addConnection(
        from sourceNodeID: UUID, sourcePort: String = "output",
        to targetNodeID: UUID, targetPort: String = "input"
    ) -> NodeConnection? {
        // Prevent self-connections
        guard sourceNodeID != targetNodeID else { return nil }

        // Prevent duplicate connections
        let exists = connections.values.contains {
            $0.sourceNodeID == sourceNodeID && $0.sourcePortID == sourcePort
                && $0.targetNodeID == targetNodeID && $0.targetPortID == targetPort
        }
        guard !exists else { return nil }

        let connection = NodeConnection(
            sourceNodeID: sourceNodeID,
            sourcePortID: sourcePort,
            targetNodeID: targetNodeID,
            targetPortID: targetPort
        )
        connections[connection.id] = connection
        return connection
    }

    public func removeConnection(_ id: UUID) {
        connections.removeValue(forKey: id)
        selectedConnectionIDs.remove(id)
    }

    // MARK: - Selection

    public func selectNode(_ id: UUID, additive: Bool = false) {
        if !additive {
            selectedNodeIDs.removeAll()
            selectedConnectionIDs.removeAll()
        }
        selectedNodeIDs.insert(id)
    }

    public func selectAll() {
        selectedNodeIDs = Set(nodes.keys)
    }

    public func deselectAll() {
        selectedNodeIDs.removeAll()
        selectedConnectionIDs.removeAll()
    }

    public func deleteSelected() {
        for id in selectedNodeIDs {
            removeNode(id)
        }
        for id in selectedConnectionIDs {
            removeConnection(id)
        }
    }

    // MARK: - Drag Operations

    public func storeDragStartPositions(for nodeID: UUID) {
        dragStartPositions.removeAll()
        if let node = nodes[nodeID] {
            dragStartPositions[nodeID] = node.position.point
        }
    }

    public func applyDragTranslation(_ translation: CGPoint, for nodeID: UUID) {
        if let start = dragStartPositions[nodeID] {
            nodes[nodeID]?.position.x = start.x + translation.x
            nodes[nodeID]?.position.y = start.y + translation.y
        }
    }

    public func clearDragStartPositions() {
        dragStartPositions.removeAll()
        onChange?()
    }

    // MARK: - Helpers

    public func nodesInRect(_ rect: CGRect) -> [WorkflowNode] {
        nodes.values.filter { rect.intersects($0.position.rect) }
    }

    public var sortedNodes: [WorkflowNode] {
        nodes.values.sorted { $0.position.x < $1.position.x }
    }

    private func defaultConfiguration(for kind: NodeKind) -> NodeConfiguration {
        switch kind {
        case .agent:
            return NodeConfiguration(providerID: "claude", modelID: "sonnet")
        case .terminal:
            return NodeConfiguration(language: "bash")
        }
    }
}
