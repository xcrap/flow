import SwiftUI
import AFCore

public struct CanvasNodeLayer: View {
    @Bindable var projectState: ProjectState
    let viewportSize: CGSize
    let nodeContent: (WorkflowNode, Bool, Bool) -> AnyView
    @State private var hoveredNodeID: UUID?
    @State private var renamingNodeID: UUID?
    @State private var renameText: String = ""

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

    @State private var clickMonitor: Any?

    public var body: some View {
        ForEach(visibleNodes) { node in
            nodePanel(node)
        }
        .onAppear {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                handleClick(event)
                return event
            }
        }
        .onDisappear {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
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
                        projectState.dragStartPositions[nodeID] = CGPoint(
                            x: node.position.width,
                            y: node.position.height
                        )
                        let centerKey = UUID(uuid: (nodeID.uuid.0 ^ 0xFF, nodeID.uuid.1, nodeID.uuid.2, nodeID.uuid.3, nodeID.uuid.4, nodeID.uuid.5, nodeID.uuid.6, nodeID.uuid.7, nodeID.uuid.8, nodeID.uuid.9, nodeID.uuid.10, nodeID.uuid.11, nodeID.uuid.12, nodeID.uuid.13, nodeID.uuid.14, nodeID.uuid.15))
                        projectState.dragStartPositions[centerKey] = CGPoint(
                            x: node.position.x,
                            y: node.position.y
                        )
                    }
                }

                if let startSize = projectState.dragStartPositions[nodeID] {
                    let centerKey = UUID(uuid: (nodeID.uuid.0 ^ 0xFF, nodeID.uuid.1, nodeID.uuid.2, nodeID.uuid.3, nodeID.uuid.4, nodeID.uuid.5, nodeID.uuid.6, nodeID.uuid.7, nodeID.uuid.8, nodeID.uuid.9, nodeID.uuid.10, nodeID.uuid.11, nodeID.uuid.12, nodeID.uuid.13, nodeID.uuid.14, nodeID.uuid.15))

                    switch edge {
                    case .right:
                        let newWidth = max(280, startSize.x + dw)
                        projectState.nodes[nodeID]?.position.width = newWidth
                        if let startCenter = projectState.dragStartPositions[centerKey] {
                            projectState.nodes[nodeID]?.position.x = startCenter.x + (newWidth - startSize.x) / 2
                        }
                    case .bottom:
                        let newHeight = max(200, startSize.y + dh)
                        projectState.nodes[nodeID]?.position.height = newHeight
                        if let startCenter = projectState.dragStartPositions[centerKey] {
                            projectState.nodes[nodeID]?.position.y = startCenter.y + (newHeight - startSize.y) / 2
                        }
                    }
                }
            }
            .onEnded { _ in
                projectState.canvasState.draggedNodeID = nil
                projectState.clearDragStartPositions()
            }
    }

    private func handleClick(_ event: NSEvent) {
        guard let window = event.window,
              let contentView = window.contentView
        else { return }

        let windowPoint = event.locationInWindow
        // AppKit Y is bottom-up, flip to top-down
        let contentHeight = contentView.bounds.height
        let clickPoint = CGPoint(x: windowPoint.x, y: contentHeight - windowPoint.y)

        let zoom = projectState.canvasState.zoom
        let orderedIDs = projectState.nodeZOrder.isEmpty ? Array(projectState.nodes.keys) : projectState.nodeZOrder

        // Check topmost first (last in z-order)
        for nodeID in orderedIDs.reversed() {
            guard let node = projectState.nodes[nodeID] else { continue }

            let screenCenter = projectState.canvasState.canvasToScreen(node.position.point)
            let halfW = (node.position.width * zoom) / 2
            let halfH = (node.position.height * zoom) / 2

            let nodeRect = CGRect(
                x: screenCenter.x - halfW,
                y: screenCenter.y - halfH,
                width: halfW * 2,
                height: halfH * 2
            )

            if nodeRect.contains(clickPoint) {
                projectState.selectNode(nodeID)
                projectState.bringToFront(nodeID)
                return
            }
        }

        // Clicked empty canvas — deselect all
        projectState.deselectAll()
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
