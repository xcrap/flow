import Foundation
import SwiftUI
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
        onChange?()
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
        onChange?()
        return connection
    }

    public func removeConnection(_ id: UUID) {
        connections.removeValue(forKey: id)
        selectedConnectionIDs.remove(id)
        onChange?()
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

    // MARK: - Layout

    public func fitToScreen(viewportSize: CGSize) {
        guard !nodes.isEmpty else { return }

        let allNodes = Array(nodes.values)
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity

        for node in allNodes {
            minX = min(minX, node.position.x - node.position.width / 2)
            minY = min(minY, node.position.y - node.position.height / 2)
            maxX = max(maxX, node.position.x + node.position.width / 2)
            maxY = max(maxY, node.position.y + node.position.height / 2)
        }

        let contentWidth = max(1, maxX - minX)
        let contentHeight = max(1, maxY - minY)
        let padding: Double = 60

        let availW = max(1, viewportSize.width - padding * 2)
        let availH = max(1, viewportSize.height - padding * 2)
        let newZoom = max(0.15, min(1.5, min(availW / contentWidth, availH / contentHeight)))

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2

        withAnimation(.spring(duration: 0.4)) {
            canvasState.zoom = newZoom
            canvasState.offset = CGPoint(
                x: viewportSize.width / 2 - cx * newZoom,
                y: viewportSize.height / 2 - cy * newZoom
            )
        }
        onChange?()
    }

    public func tidyUp(viewportSize: CGSize) {
        let sortedNodes = nodes.values.sorted {
            if abs($0.position.y - $1.position.y) < 100 {
                return $0.position.x < $1.position.x
            }
            return $0.position.y < $1.position.y
        }
        guard !sortedNodes.isEmpty else { return }

        let gap: Double = 20
        let columns = max(1, Int(ceil(sqrt(Double(sortedNodes.count)))))

        withAnimation(.spring(duration: 0.5)) {
            var cursorX: Double = 0
            var cursorY: Double = 0
            var rowHeight: Double = 0

            for (index, node) in sortedNodes.enumerated() {
                let col = index % columns
                if col == 0 && index > 0 {
                    cursorX = 0
                    cursorY += rowHeight + gap
                    rowHeight = 0
                }
                let w = node.position.width
                let h = node.position.height
                nodes[node.id]?.position.x = cursorX + w / 2
                nodes[node.id]?.position.y = cursorY + h / 2
                cursorX += w + gap
                rowHeight = max(rowHeight, h)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.fitToScreen(viewportSize: viewportSize)
        }
    }

    private func defaultConfiguration(for kind: NodeKind) -> NodeConfiguration {
        switch kind {
        case .agent:
            return NodeConfiguration(providerID: "claude", modelID: "sonnet", triggerType: "auto")
        case .terminal:
            return NodeConfiguration(language: "bash")
        }
    }
}
