import SwiftUI
import AFCore

public struct CanvasNodeLayer: View {
    @Bindable var projectState: ProjectState
    let viewportSize: CGSize
    let nodeContent: (WorkflowNode, Bool) -> AnyView

    private let viewportBuffer: Double = 500

    private var visibleNodes: [WorkflowNode] {
        let viewport = projectState.canvasState.visibleRect(in: viewportSize)
        let buffered = viewport.insetBy(dx: -viewportBuffer, dy: -viewportBuffer)
        return projectState.nodes.values.filter { node in
            buffered.intersects(node.position.rect)
        }
    }

    public init(
        projectState: ProjectState,
        viewportSize: CGSize,
        @ViewBuilder nodeContent: @escaping (WorkflowNode, Bool) -> AnyView
    ) {
        self.projectState = projectState
        self.viewportSize = viewportSize
        self.nodeContent = nodeContent
    }

    public var body: some View {
        ForEach(visibleNodes) { node in
            nodePanel(node)
        }
    }

    @ViewBuilder
    private func nodePanel(_ node: WorkflowNode) -> some View {
        let isSelected = projectState.selectedNodeIDs.contains(node.id)

        nodeContent(node, isSelected)
            .overlay(alignment: .topLeading) {
                // Drag handle covers title area (left 60%), right side has pickers
                Color.clear
                    .frame(width: max(0, node.position.width * 0.55), height: 40)
                    .contentShape(Rectangle())
                    .gesture(nodeDragGesture(for: node.id))
            }
            .overlay(alignment: .bottomTrailing) {
                // Invisible resize area at bottom-right corner
                Color.clear
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(resizeGesture(for: node.id))
            }
            .scaleEffect(projectState.canvasState.zoom, anchor: .center)
            .position(projectState.canvasState.canvasToScreen(node.position.point))
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        projectState.selectNode(node.id, additive: NSEvent.modifierFlags.contains(.command))
                    }
            )
            .contextMenu {
                nodeContextMenu(for: node)
            }
    }

    private func nodeDragGesture(for nodeID: UUID) -> some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                let zoom = projectState.canvasState.zoom

                if projectState.canvasState.draggedNodeID != nodeID {
                    projectState.canvasState.draggedNodeID = nodeID
                    projectState.canvasState.isDragging = true
                    projectState.storeDragStartPositions(for: nodeID)
                }

                let translation = CGPoint(
                    x: value.translation.width / zoom,
                    y: value.translation.height / zoom
                )
                projectState.applyDragTranslation(translation, for: nodeID)
            }
            .onEnded { _ in
                projectState.canvasState.isDragging = false
                projectState.canvasState.draggedNodeID = nil
                projectState.clearDragStartPositions()
            }
    }

    private func resizeGesture(for nodeID: UUID) -> some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                let zoom = projectState.canvasState.zoom
                let dw = value.translation.width / zoom
                let dh = value.translation.height / zoom

                if projectState.canvasState.draggedNodeID != nodeID {
                    projectState.canvasState.draggedNodeID = nodeID
                    if let node = projectState.nodes[nodeID] {
                        // Store: x = startWidth, y = startHeight
                        // Also store center position to adjust for top-left anchoring
                        projectState.dragStartPositions[nodeID] = CGPoint(
                            x: node.position.width,
                            y: node.position.height
                        )
                        // Store original center as a second entry
                        let centerKey = UUID(uuid: (nodeID.uuid.0 ^ 0xFF, nodeID.uuid.1, nodeID.uuid.2, nodeID.uuid.3, nodeID.uuid.4, nodeID.uuid.5, nodeID.uuid.6, nodeID.uuid.7, nodeID.uuid.8, nodeID.uuid.9, nodeID.uuid.10, nodeID.uuid.11, nodeID.uuid.12, nodeID.uuid.13, nodeID.uuid.14, nodeID.uuid.15))
                        projectState.dragStartPositions[centerKey] = CGPoint(
                            x: node.position.x,
                            y: node.position.y
                        )
                    }
                }

                if let startSize = projectState.dragStartPositions[nodeID] {
                    let newWidth = max(280, startSize.x + dw)
                    let newHeight = max(200, startSize.y + dh)

                    // Shift center so top-left stays fixed
                    let centerKey = UUID(uuid: (nodeID.uuid.0 ^ 0xFF, nodeID.uuid.1, nodeID.uuid.2, nodeID.uuid.3, nodeID.uuid.4, nodeID.uuid.5, nodeID.uuid.6, nodeID.uuid.7, nodeID.uuid.8, nodeID.uuid.9, nodeID.uuid.10, nodeID.uuid.11, nodeID.uuid.12, nodeID.uuid.13, nodeID.uuid.14, nodeID.uuid.15))
                    if let startCenter = projectState.dragStartPositions[centerKey] {
                        projectState.nodes[nodeID]?.position.x = startCenter.x + (newWidth - startSize.x) / 2
                        projectState.nodes[nodeID]?.position.y = startCenter.y + (newHeight - startSize.y) / 2
                    }

                    projectState.nodes[nodeID]?.position.width = newWidth
                    projectState.nodes[nodeID]?.position.height = newHeight
                }
            }
            .onEnded { _ in
                projectState.canvasState.draggedNodeID = nil
                projectState.clearDragStartPositions()
            }
    }

    @ViewBuilder
    private func nodeContextMenu(for node: WorkflowNode) -> some View {
        Button("Duplicate") {
            let size = WorkflowNode.defaultSize(for: node.kind)
            let newNode = WorkflowNode(
                kind: node.kind,
                title: "\(node.title) Copy",
                position: NodePosition(
                    x: node.position.x + 50,
                    y: node.position.y + 50,
                    width: size.width,
                    height: size.height
                ),
                configuration: node.configuration
            )
            projectState.nodes[newNode.id] = newNode
        }

        Divider()

        Button("Delete", role: .destructive) {
            projectState.removeNode(node.id)
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
