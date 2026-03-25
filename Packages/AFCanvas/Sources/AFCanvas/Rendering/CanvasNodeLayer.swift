import SwiftUI
import AFCore

public struct CanvasNodeLayer: View {
    @Bindable var projectState: ProjectState
    let viewportSize: CGSize
    let nodeContent: (WorkflowNode, Bool, Bool) -> AnyView
    @State private var hoveredNodeID: UUID?
    @State private var renamingNodeID: UUID?
    @State private var renameText: String = ""

    /// Tracks the initial size and center position at the start of a resize gesture.
    private struct ResizeStart {
        let startWidth: Double
        let startHeight: Double
        let centerX: Double
        let centerY: Double
    }
    @State private var resizeStart: ResizeStart?

    private let viewportBuffer: Double = 500

    private var visibleNodes: [WorkflowNode] {
        let viewport = projectState.canvasState.visibleRect(in: viewportSize)
        let buffered = viewport.insetBy(dx: -viewportBuffer, dy: -viewportBuffer)

        // Use z-order for rendering order, fallback to dict order for new nodes
        let ordered: [UUID]
        if projectState.nodeZOrder.isEmpty {
            ordered = Array(projectState.nodes.keys)
        } else {
            // Include any nodes not yet in zOrder
            let zSet = Set(projectState.nodeZOrder)
            let missing = projectState.nodes.keys.filter { !zSet.contains($0) }
            ordered = projectState.nodeZOrder + missing
        }

        return ordered.compactMap { projectState.nodes[$0] }.filter { node in
            buffered.intersects(node.position.rect)
        }
    }

    public init(
        projectState: ProjectState,
        viewportSize: CGSize,
        @ViewBuilder nodeContent: @escaping (WorkflowNode, Bool, Bool) -> AnyView
    ) {
        self.projectState = projectState
        self.viewportSize = viewportSize
        self.nodeContent = nodeContent
    }

    public var body: some View {
        ForEach(visibleNodes) { node in
            nodePanel(node)
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingNodeID != nil },
            set: { if !$0 { renamingNodeID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("OK") {
                if let id = renamingNodeID {
                    projectState.nodes[id]?.title = renameText
                    projectState.onChange?()
                }
                renamingNodeID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingNodeID = nil
            }
        }
    }

    @ViewBuilder
    private func nodePanel(_ node: WorkflowNode) -> some View {
        let isSelected = projectState.selectedNodeIDs.contains(node.id)
        let isTitleHovered = hoveredNodeID == node.id

        nodeContent(node, isSelected, isTitleHovered)
            .id(node.id)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    // Left: drag handle + hover area
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .highPriorityGesture(nodeDragGesture(for: node.id))

                    // Right: not interactive (pickers underneath handle clicks)
                    Color.clear
                        .frame(width: node.position.width * 0.45)
                        .allowsHitTesting(false)
                }
                .frame(height: 42)
                .onHover { hovering in
                    hoveredNodeID = hovering ? node.id : nil
                }
            }
            .overlay(alignment: .trailing) {
                // Right edge resize
                Color.clear
                    .frame(width: 6, height: node.position.height * 0.6)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(edgeResizeGesture(for: node.id, edge: .right))
            }
            .overlay(alignment: .bottom) {
                // Bottom edge resize
                Color.clear
                    .frame(width: node.position.width * 0.6, height: 6)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(edgeResizeGesture(for: node.id, edge: .bottom))
            }
            .overlay(alignment: .bottomTrailing) {
                // Corner resize
                Color.clear
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                    .cursor(.crosshair)
                    .gesture(resizeGesture(for: node.id))
            }
            .scaleEffect(projectState.canvasState.zoom, anchor: .center)
            .position(projectState.canvasState.canvasToScreen(node.position.point))
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
                    projectState.selectedNodeIDs = [nodeID]
                    projectState.selectedConnectionIDs.removeAll()
                    projectState.bringToFront(nodeID)
                    projectState.storeDragStartPositions(for: nodeID)
                }

                var translation = CGPoint(
                    x: value.translation.width / zoom,
                    y: value.translation.height / zoom
                )

                // Snap to grid when Shift is held
                if NSEvent.modifierFlags.contains(.shift) {
                    let gridSize: Double = 20
                    if let start = projectState.dragStartPositions[nodeID] {
                        let rawX = start.x + translation.x
                        let rawY = start.y + translation.y
                        let snappedX = (rawX / gridSize).rounded() * gridSize
                        let snappedY = (rawY / gridSize).rounded() * gridSize
                        translation = CGPoint(x: snappedX - start.x, y: snappedY - start.y)
                    }
                }

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
                        resizeStart = ResizeStart(
                            startWidth: node.position.width,
                            startHeight: node.position.height,
                            centerX: node.position.x,
                            centerY: node.position.y
                        )
                    }
                }

                if let rs = resizeStart {
                    let newWidth = max(280, rs.startWidth + dw)
                    let newHeight = max(200, rs.startHeight + dh)
                    projectState.nodes[nodeID]?.position.x = rs.centerX + (newWidth - rs.startWidth) / 2
                    projectState.nodes[nodeID]?.position.y = rs.centerY + (newHeight - rs.startHeight) / 2
                    projectState.nodes[nodeID]?.position.width = newWidth
                    projectState.nodes[nodeID]?.position.height = newHeight
                }
            }
            .onEnded { _ in
                projectState.canvasState.draggedNodeID = nil
                resizeStart = nil
                projectState.onChange?()
            }
    }

    enum ResizeEdge { case right, bottom }

    private func edgeResizeGesture(for nodeID: UUID, edge: ResizeEdge) -> some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                let zoom = projectState.canvasState.zoom
                let dw = value.translation.width / zoom
                let dh = value.translation.height / zoom

                if projectState.canvasState.draggedNodeID != nodeID {
                    projectState.canvasState.draggedNodeID = nodeID
                    if let node = projectState.nodes[nodeID] {
                        resizeStart = ResizeStart(
                            startWidth: node.position.width,
                            startHeight: node.position.height,
                            centerX: node.position.x,
                            centerY: node.position.y
                        )
                    }
                }

                if let rs = resizeStart {
                    switch edge {
                    case .right:
                        let newWidth = max(280, rs.startWidth + dw)
                        projectState.nodes[nodeID]?.position.width = newWidth
                        projectState.nodes[nodeID]?.position.x = rs.centerX + (newWidth - rs.startWidth) / 2
                    case .bottom:
                        let newHeight = max(200, rs.startHeight + dh)
                        projectState.nodes[nodeID]?.position.height = newHeight
                        projectState.nodes[nodeID]?.position.y = rs.centerY + (newHeight - rs.startHeight) / 2
                    }
                }
            }
            .onEnded { _ in
                projectState.canvasState.draggedNodeID = nil
                resizeStart = nil
                projectState.onChange?()
            }
    }

    @ViewBuilder
    private func nodeContextMenu(for node: WorkflowNode) -> some View {
        Button("Rename") {
            renamingNodeID = node.id
            renameText = node.title
        }

        Button("Duplicate") {
            let newNode = WorkflowNode(
                kind: node.kind,
                title: "\(node.title) Copy",
                position: NodePosition(
                    x: node.position.x + node.position.width + 30,
                    y: node.position.y,
                    width: node.position.width,
                    height: node.position.height
                ),
                configuration: node.configuration
            )
            projectState.nodes[newNode.id] = newNode
            projectState.bringToFront(newNode.id)
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
