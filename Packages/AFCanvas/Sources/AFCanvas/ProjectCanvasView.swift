import SwiftUI
import AFCore

public struct ProjectCanvasView<NodeContent: View>: View {
    @Bindable var projectState: ProjectState
    @State private var panStart: CGPoint?
    @State private var zoomStart: Double?
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
                    .contentShape(Rectangle())
                    .gesture(canvasPanGesture)

                CanvasNodeLayer(
                    projectState: projectState,
                    viewportSize: geometry.size,
                    nodeContent: { node, isSelected, isTitleHovered in
                        AnyView(nodeContent(node, isSelected, isTitleHovered))
                    }
                )

            }
            .background {
                ClickDetectorOverlay(projectState: projectState)
            }
            .gesture(canvasZoomGesture)
            .canvasEventMonitor(
                onZoomScroll: { [projectState] delta, mouseLocation in
                    // Cooldown: ignore rapid-fire scroll events to prevent bounce
                    let now = CACurrentMediaTime()
                    guard now - projectState.canvasState.lastZoomScrollTime > 0.25 else { return }
                    projectState.canvasState.lastZoomScrollTime = now

                    let oldZoom = projectState.canvasState.zoom
                    let newZoom = delta.y > 0
                        ? CanvasState.nextZoomLevel(above: oldZoom)
                        : CanvasState.nextZoomLevel(below: oldZoom)
                    guard newZoom != oldZoom else { return }

                    let offset = projectState.canvasState.offset

                    // Instant snap — no animation avoids overlapping animation bounce
                    projectState.canvasState.offset = CGPoint(
                        x: mouseLocation.x - (mouseLocation.x - offset.x) * (newZoom / oldZoom),
                        y: mouseLocation.y - (mouseLocation.y - offset.y) * (newZoom / oldZoom)
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
                // Ignore tiny magnification changes (can trigger on clicks)
                guard abs(value.magnification - 1.0) > 0.01 else { return }

                if zoomStart == nil {
                    zoomStart = projectState.canvasState.zoom
                }
                let baseZoom = zoomStart ?? projectState.canvasState.zoom
                let oldZoom = projectState.canvasState.zoom
                let newZoom = max(0.1, min(3.0, baseZoom * value.magnification))

                let vp = projectState.canvasState.viewportSize
                let cx = vp.width / 2
                let cy = vp.height / 2
                let offset = projectState.canvasState.offset
                projectState.canvasState.offset = CGPoint(
                    x: cx - (cx - offset.x) * (newZoom / oldZoom),
                    y: cy - (cy - offset.y) * (newZoom / oldZoom)
                )
                projectState.canvasState.zoom = newZoom
            }
            .onEnded { _ in
                // Only snap if a real pinch gesture occurred
                guard zoomStart != nil else { return }

                let oldZoom = projectState.canvasState.zoom
                let snapped = CanvasState.snapZoom(oldZoom)
                if snapped != oldZoom {
                    let vp = projectState.canvasState.viewportSize
                    let cx = vp.width / 2
                    let cy = vp.height / 2
                    let offset = projectState.canvasState.offset
                    withAnimation(.easeOut(duration: 0.15)) {
                        projectState.canvasState.offset = CGPoint(
                            x: cx - (cx - offset.x) * (snapped / oldZoom),
                            y: cy - (cy - offset.y) * (snapped / oldZoom)
                        )
                        projectState.canvasState.zoom = snapped
                    }
                }
                zoomStart = nil
                projectState.onChange?()
            }
    }
}

// MARK: - NSView Anchor for Coordinate Conversion

/// Holds a reference to an NSView placed inside the canvas so that
/// NSEvent window coordinates can be converted to canvas-local coordinates.
final class CanvasViewAnchor: @unchecked Sendable {
    var view: NSView?
}

private struct CanvasAnchorRepresentable: NSViewRepresentable {
    let anchor: CanvasViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Scroll Wheel Modifier

struct CanvasEventMonitor: ViewModifier {
    let onZoomScroll: (_ delta: CGPoint, _ mouseLocation: CGPoint) -> Void
    let onPanDelta: (CGPoint) -> Void
    let onPanEnd: () -> Void
    @State private var scrollMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var dragMonitor: Any?
    @State private var dragUpMonitor: Any?
    @State private var isPanning = false
    @State private var anchor = CanvasViewAnchor()

    private func removeAllMonitors() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = dragUpMonitor { NSEvent.removeMonitor(m); dragUpMonitor = nil }
    }

    func body(content: Content) -> some View {
        content
            .background(CanvasAnchorRepresentable(anchor: anchor))
            .onAppear {
                // Remove any existing monitors to prevent duplicate registration
                removeAllMonitors()

                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [anchor] event in
                    if event.modifierFlags.contains(.command) {
                        // Convert window coordinates to canvas-local (flipped Y for SwiftUI)
                        var mousePos = CGPoint.zero
                        if let view = anchor.view {
                            let viewLoc = view.convert(event.locationInWindow, from: nil)
                            mousePos = CGPoint(x: viewLoc.x, y: view.bounds.height - viewLoc.y)
                        }
                        onZoomScroll(CGPoint(x: 0, y: event.scrollingDeltaY), mousePos)
                        return nil
                    }
                    return event
                }

                mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    guard event.modifierFlags.contains(.command) else {
                        return event
                    }

                    // Consume the full command-drag sequence up front so text views
                    // do not start their own drag/select tracking and then lose it mid-stream.
                    isPanning = true
                    return nil
                }

                dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { event in
                    if isPanning {
                        let delta = CGPoint(x: event.deltaX, y: event.deltaY)
                        onPanDelta(delta)
                        return nil // consume
                    }
                    return event
                }

                dragUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
                    if isPanning {
                        isPanning = false
                        onPanEnd()
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                removeAllMonitors()
            }
    }
}

extension View {
    func onScrollGesture(handler: @escaping (_ delta: CGPoint, _ mouseLocation: CGPoint) -> Void) -> some View {
        modifier(CanvasEventMonitor(
            onZoomScroll: handler,
            onPanDelta: { _ in },
            onPanEnd: { }
        ))
    }

    func canvasEventMonitor(
        onZoomScroll: @escaping (_ delta: CGPoint, _ mouseLocation: CGPoint) -> Void,
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
