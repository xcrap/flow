import SwiftUI
import AFCore

public struct ProjectCanvasView<NodeContent: View>: View {
    @Bindable var projectState: ProjectState
    @State private var panStart: CGPoint?
    let nodeContent: (WorkflowNode, Bool) -> NodeContent

    public init(
        projectState: ProjectState,
        @ViewBuilder nodeContent: @escaping (WorkflowNode, Bool) -> NodeContent
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
                    nodeContent: { node, isSelected in
                        AnyView(nodeContent(node, isSelected))
                    }
                )
            }
            .contentShape(Rectangle())
            .gesture(canvasPanGesture)
            .gesture(canvasZoomGesture)
            .onScrollGesture { delta in
                // Scroll wheel zoom
                let zoomDelta = delta.y > 0 ? 1.05 : 0.95
                let newZoom = max(0.1, min(3.0, projectState.canvasState.zoom * zoomDelta))
                projectState.canvasState.zoom = newZoom
            }
            .onTapGesture {
                projectState.deselectAll()
            }
            .clipped()
            .coordinateSpace(name: "canvas")
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("canvas"))
            .onChanged { value in
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
                panStart = nil
            }
    }

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = max(0.1, min(3.0, projectState.canvasState.zoom * value.magnification))
                projectState.canvasState.zoom = newZoom
            }
    }
}

// MARK: - Scroll Wheel Modifier

struct ScrollGestureModifier: ViewModifier {
    let handler: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content.background {
            ScrollWheelView(onScroll: handler)
        }
    }
}

struct ScrollWheelView: NSViewRepresentable {
    let onScroll: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Cmd + scroll = zoom (works with both mouse wheel and trackpad)
            onScroll?(CGPoint(x: 0, y: event.scrollingDeltaY))
        } else if event.phase == [] && event.momentumPhase == [] {
            // Discrete mouse scroll wheel (no trackpad) = also zoom
            onScroll?(CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        } else {
            super.scrollWheel(with: event)
        }
    }
}

extension View {
    func onScrollGesture(handler: @escaping (CGPoint) -> Void) -> some View {
        modifier(ScrollGestureModifier(handler: handler))
    }
}
