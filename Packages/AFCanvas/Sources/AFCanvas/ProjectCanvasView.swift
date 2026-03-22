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
            .onScrollGesture { [projectState] delta in
                let oldZoom = projectState.canvasState.zoom
                let factor = 1.0 + (delta.y * 0.01)
                let newZoom = max(0.1, min(3.0, oldZoom * factor))

                // Zoom centered on viewport center
                let cx = geometry.size.width / 2
                let cy = geometry.size.height / 2
                let offset = projectState.canvasState.offset

                // Adjust offset so the canvas point under center stays fixed
                projectState.canvasState.offset = CGPoint(
                    x: cx - (cx - offset.x) * (newZoom / oldZoom),
                    y: cy - (cy - offset.y) * (newZoom / oldZoom)
                )
                projectState.canvasState.zoom = newZoom
                projectState.onChange?()
            }
            .onTapGesture {
                projectState.deselectAll()
            }
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

struct ScrollMonitorModifier: ViewModifier {
    let handler: (CGPoint) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    if event.modifierFlags.contains(.command) {
                        handler(CGPoint(x: 0, y: event.scrollingDeltaY))
                        return nil // consume the event
                    }
                    return event // pass through
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

extension View {
    func onScrollGesture(handler: @escaping (CGPoint) -> Void) -> some View {
        modifier(ScrollMonitorModifier(handler: handler))
    }
}
