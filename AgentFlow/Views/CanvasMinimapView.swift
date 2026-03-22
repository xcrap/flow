import SwiftUI
import AFCanvas
import AFCore

struct CanvasMinimapView: View {
    var projectState: ProjectState
    var viewportSize: CGSize

    private let minimapWidth: CGFloat = 160
    private let minimapHeight: CGFloat = 100

    var body: some View {
        Canvas { context, size in
            // Draw background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(0.35))
            )

            let layout = computeLayout(in: size)

            // Draw each node as a small colored rectangle
            for node in projectState.nodes.values {
                let rect = nodeRect(for: node, layout: layout)
                let color: Color = node.kind == .agent ? .purple : .blue
                context.fill(Path(rect), with: .color(color))
            }

            // Draw viewport indicator
            let viewportRect = self.viewportRect(layout: layout, canvasSize: size)
            let viewportPath = Path(viewportRect)
            context.stroke(viewportPath, with: .color(.white.opacity(0.9)), lineWidth: 1)
            context.fill(viewportPath, with: .color(.white.opacity(0.15)))
        }
        .frame(width: minimapWidth, height: minimapHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { location in
            panCanvas(to: location)
        }
        .padding(12)
    }

    // MARK: - Layout Computation

    private struct MinimapLayout {
        var boundsOrigin: CGPoint
        var boundsSize: CGSize
        var scale: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat
    }

    private func computeLayout(in size: CGSize) -> MinimapLayout {
        let nodes = Array(projectState.nodes.values)
        guard !nodes.isEmpty else {
            return MinimapLayout(
                boundsOrigin: .zero,
                boundsSize: CGSize(width: 1000, height: 1000),
                scale: min(size.width / 1000, size.height / 1000),
                offsetX: 0,
                offsetY: 0
            )
        }

        // Compute bounding box of all nodes
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        for node in nodes {
            let r = node.position.rect
            minX = min(minX, r.minX)
            minY = min(minY, r.minY)
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }

        // Add some padding around the bounds
        let padding: CGFloat = 200
        minX -= padding
        minY -= padding
        maxX += padding
        maxY += padding

        // Also include the current viewport in the bounds so it is always visible
        let canvas = projectState.canvasState
        let vpTopLeft = canvas.screenToCanvas(.zero)
        let vpBottomRight = canvas.screenToCanvas(CGPoint(x: viewportSize.width, y: viewportSize.height))

        minX = min(minX, vpTopLeft.x)
        minY = min(minY, vpTopLeft.y)
        maxX = max(maxX, vpBottomRight.x)
        maxY = max(maxY, vpBottomRight.y)

        let boundsWidth = maxX - minX
        let boundsHeight = maxY - minY

        let scale = min(size.width / boundsWidth, size.height / boundsHeight)

        // Center the content in the minimap
        let scaledWidth = boundsWidth * scale
        let scaledHeight = boundsHeight * scale
        let offsetX = (size.width - scaledWidth) / 2
        let offsetY = (size.height - scaledHeight) / 2

        return MinimapLayout(
            boundsOrigin: CGPoint(x: minX, y: minY),
            boundsSize: CGSize(width: boundsWidth, height: boundsHeight),
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    private func nodeRect(for node: WorkflowNode, layout: MinimapLayout) -> CGRect {
        let r = node.position.rect
        let x = (r.minX - layout.boundsOrigin.x) * layout.scale + layout.offsetX
        let y = (r.minY - layout.boundsOrigin.y) * layout.scale + layout.offsetY
        let w = max(r.width * layout.scale, 3)
        let h = max(r.height * layout.scale, 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func viewportRect(layout: MinimapLayout, canvasSize: CGSize) -> CGRect {
        let canvas = projectState.canvasState
        let topLeft = canvas.screenToCanvas(.zero)
        let bottomRight = canvas.screenToCanvas(CGPoint(x: viewportSize.width, y: viewportSize.height))

        let x = (topLeft.x - layout.boundsOrigin.x) * layout.scale + layout.offsetX
        let y = (topLeft.y - layout.boundsOrigin.y) * layout.scale + layout.offsetY
        let w = (bottomRight.x - topLeft.x) * layout.scale
        let h = (bottomRight.y - topLeft.y) * layout.scale

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Interaction

    private func panCanvas(to minimapPoint: CGPoint) {
        let layout = computeLayout(in: CGSize(width: minimapWidth, height: minimapHeight))

        // Convert minimap tap location to canvas coordinates
        let canvasX = (minimapPoint.x - layout.offsetX) / layout.scale + layout.boundsOrigin.x
        let canvasY = (minimapPoint.y - layout.offsetY) / layout.scale + layout.boundsOrigin.y

        // Set offset so this canvas point is centered in the viewport
        withAnimation(.easeInOut(duration: 0.3)) {
            let zoom = projectState.canvasState.zoom
            projectState.canvasState.offset = CGPoint(
                x: -canvasX * zoom + viewportSize.width / 2,
                y: -canvasY * zoom + viewportSize.height / 2
            )
        }
    }
}
