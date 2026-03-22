import SwiftUI
import AFCore

public struct ProjectCanvasView<NodeContent: View>: View {
    @Bindable var projectState: ProjectState
    @State private var panStart: CGPoint?
    let nodeContent: (WorkflowNode, Bool, Bool) -> NodeContent

    public init(
        projectState: ProjectState,
        @ViewBuilder nodeContent: @escaping (WorkflowNode, Bool, Bool) -> NodeContent
    ) {
        self.projectState = projectState
        self.nodeContent = nodeContent
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                CanvasBackgroundLayer(canvasState: projectState.canvasState)

                CanvasNodeLayer(
                    projectState: projectState,
                    viewportSize: geometry.size,
                    nodeContent: { node, isSelected, isTitleHovered in
                        AnyView(nodeContent(node, isSelected, isTitleHovered))
                    }
                )
            }
            .contentShape(Rectangle())
            .gesture(canvasPanGesture)
            .gesture(canvasZoomGesture)
            .canvasEventMonitor(
                onZoomScroll: { [projectState] delta in
                    let oldZoom = projectState.canvasState.zoom
                    let factor = 1.0 + (delta.y * 0.01)
                    let newZoom = max(0.1, min(3.0, oldZoom * factor))

                    let cx = geometry.size.width / 2
                    let cy = geometry.size.height / 2
                    let offset = projectState.canvasState.offset

                    projectState.canvasState.offset = CGPoint(
                        x: cx - (cx - offset.x) * (newZoom / oldZoom),
                        y: cy - (cy - offset.y) * (newZoom / oldZoom)
                    )
                    projectState.canvasState.zoom = newZoom
                    projectState.onChange?()
                },
                onPanDelta: { [projectState] delta in
                    projectState.canvasState.offset.x += delta.x
                    projectState.canvasState.offset.y += delta.y
                },
                onPanEnd: { [projectState] in
                    projectState.onChange?()
                }
            )
            .clipped()
            .coordinateSpace(name: "canvas")
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("canvas"))
            .onChanged { value in
                // Only pan when no node is being dragged
                guard projectState.canvasState.draggedNodeID == nil else { return }

                if panStart == nil {
                    panStart = projectState.canvasState.offset
                }

                if let start = panStart {
                    projectState.canvasState.offset = CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if panStart != nil {
                    panStart = nil
                    projectState.onChange?()
                }
            }
    }

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = max(0.1, min(3.0, projectState.canvasState.zoom * value.magnification))
                projectState.canvasState.zoom = newZoom
            }
            .onEnded { _ in
                projectState.onChange?()
            }
    }
}

// MARK: - Scroll Wheel Modifier

struct CanvasEventMonitor: ViewModifier {
    let onZoomScroll: (CGPoint) -> Void
    let onPanDelta: (CGPoint) -> Void
    let onPanEnd: () -> Void
    @State private var scrollMonitor: Any?
    @State private var dragMonitor: Any?
    @State private var dragUpMonitor: Any?
    @State private var isPanning = false
    @State private var lastDragPoint: NSPoint?

    func body(content: Content) -> some View {
        content
            .onAppear {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    if event.modifierFlags.contains(.command) {
                        onZoomScroll(CGPoint(x: 0, y: event.scrollingDeltaY))
                        return nil
                    }
                    return event
                }

                dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { event in
                    if event.modifierFlags.contains(.option) {
                        let delta = CGPoint(x: event.deltaX, y: -event.deltaY)
                        onPanDelta(delta)
                        isPanning = true
                        return nil // consume
                    }
                    return event
                }

                dragUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
                    if isPanning {
                        isPanning = false
                        onPanEnd()
                    }
                    return event
                }
            }
            .onDisappear {
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
                if let dragUpMonitor { NSEvent.removeMonitor(dragUpMonitor) }
            }
    }
}

extension View {
    func onScrollGesture(handler: @escaping (CGPoint) -> Void) -> some View {
        modifier(CanvasEventMonitor(
            onZoomScroll: handler,
            onPanDelta: { _ in },
            onPanEnd: { }
        ))
    }

    func canvasEventMonitor(
        onZoomScroll: @escaping (CGPoint) -> Void,
        onPanDelta: @escaping (CGPoint) -> Void,
        onPanEnd: @escaping () -> Void
    ) -> some View {
        modifier(CanvasEventMonitor(
            onZoomScroll: onZoomScroll,
            onPanDelta: onPanDelta,
            onPanEnd: onPanEnd
        ))
    }
}
