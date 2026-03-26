import Foundation
import AFCore

@Observable
@MainActor
public final class CanvasState {
    public static let minimumZoom: Double = 0.1
    public static let maximumZoom: Double = 3.0

    public var offset: CGPoint = .zero
    public var zoom: Double = 1.0
    public var gridSize: Double = 20.0
    public var showGrid: Bool = true
    public var isDragging: Bool = false
    public var draggedNodeID: UUID?
    public var isDrawingConnection: Bool = false
    public var connectionDraftSource: ConnectionDraft?
    public var connectionDraftEndPoint: CGPoint?
    public var marqueeOrigin: CGPoint?
    public var marqueeRect: CGRect?
    public var viewportSize: CGSize = CGSize(width: 900, height: 700)

    public init() {}

    public static func clampedZoom(_ value: Double) -> Double {
        max(minimumZoom, min(maximumZoom, value))
    }

    public var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    public func setZoom(_ targetZoom: Double, around screenPoint: CGPoint) {
        let oldZoom = zoom
        let newZoom = Self.clampedZoom(targetZoom)
        guard oldZoom > 0, newZoom != oldZoom else { return }

        offset = CGPoint(
            x: screenPoint.x - (screenPoint.x - offset.x) * (newZoom / oldZoom),
            y: screenPoint.y - (screenPoint.y - offset.y) * (newZoom / oldZoom)
        )
        zoom = newZoom
    }

    public func zoom(by factor: Double, around screenPoint: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        setZoom(zoom * factor, around: screenPoint)
    }

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
        let resolvedZoom = Self.clampedZoom(targetZoom ?? zoom)

        if targetZoom != nil {
            zoom = resolvedZoom
        }

        offset = CGPoint(
            x: viewportSize.width / 2 - canvasPoint.x * resolvedZoom,
            y: viewportSize.height / 2 - canvasPoint.y * resolvedZoom
        )
    }

    /// Reset zoom to 1.0 while keeping the viewport center fixed.
    public func resetZoom(in viewportSize: CGSize) {
        let oldZoom = zoom
        guard oldZoom != 1.0 else { return }
        // Canvas point currently at screen center
        let cx = viewportSize.width / 2
        let cy = viewportSize.height / 2
        let canvasCenterX = (cx - offset.x) / oldZoom
        let canvasCenterY = (cy - offset.y) / oldZoom
        // New offset so that same canvas point stays at screen center with zoom = 1
        offset = CGPoint(
            x: cx - canvasCenterX,
            y: cy - canvasCenterY
        )
        zoom = 1.0
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
