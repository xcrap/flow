import SwiftUI
import AFCore

struct CanvasBackgroundLayer: View {
    let canvasState: CanvasState

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        guard canvasState.showGrid else { return }
        let gridSize = canvasState.gridSize * canvasState.zoom
        guard gridSize > 4 else { return }

        let opacity = min(1.0, (gridSize - 4) / 16.0)
        let dotColor = Color.primary.opacity(0.08 * opacity)

        let startX = canvasState.offset.x.truncatingRemainder(dividingBy: gridSize)
        let startY = canvasState.offset.y.truncatingRemainder(dividingBy: gridSize)

        // Batch all dots into a single path to avoid per-dot allocations
        var dots = Path()
        var x = startX
        while x < size.width {
            var y = startY
            while y < size.height {
                dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                y += gridSize
            }
            x += gridSize
        }
        context.fill(dots, with: .color(dotColor))
    }
}
