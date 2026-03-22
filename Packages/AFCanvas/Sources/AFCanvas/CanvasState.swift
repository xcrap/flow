import Foundation
import AFCore

@Observable
@MainActor
public final class CanvasState {
    public var offset: CGPoint = .zero
    public var zoom: Double = 1.0
    public var gridSize: Double = 20.0
    public var isDragging: Bool = false
    public var draggedNodeID: UUID?
    public var isDrawingConnection: Bool = false
    public var connectionDraftSource: ConnectionDraft?
    public var connectionDraftEndPoint: CGPoint?
    public var marqueeOrigin: CGPoint?
    public var marqueeRect: CGRect?

    public init() {}

    public func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * zoom + offset.x,
            y: point.y * zoom + offset.y
        )
    }

    public func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / zoom,
            y: (point.y - offset.y) / zoom
        )
    }

    public func center(on canvasPoint: CGPoint, in viewportSize: CGSize, zoom targetZoom: Double? = nil) {
        let resolvedZoom = max(0.1, min(3.0, targetZoom ?? zoom))

        if targetZoom != nil {
            zoom = resolvedZoom
        }

        offset = CGPoint(
            x: viewportSize.width / 2 - canvasPoint.x * resolvedZoom,
            y: viewportSize.height / 2 - canvasPoint.y * resolvedZoom
        )
    }

    public func visibleRect(in size: CGSize) -> CGRect {
        let origin = screenToCanvas(.zero)
        let extent = screenToCanvas(CGPoint(x: size.width, y: size.height))
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: extent.x - origin.x,
            height: extent.y - origin.y
        )
    }
}

public struct ConnectionDraft: Sendable {
    public var nodeID: UUID
    public var portID: String
    public var isInput: Bool

    public init(nodeID: UUID, portID: String, isInput: Bool = false) {
        self.nodeID = nodeID
        self.portID = portID
        self.isInput = isInput
    }
}
