import SwiftUI
import AFCore

struct ClickDetectorOverlay: NSViewRepresentable {
    let projectState: ProjectState

    func makeNSView(context: Context) -> ClickDetectorNSView {
        let view = ClickDetectorNSView()
        view.projectState = projectState
        return view
    }

    func updateNSView(_ nsView: ClickDetectorNSView, context: Context) {
        nsView.projectState = projectState
    }
}

class ClickDetectorNSView: NSView {
    weak var projectState: ProjectState?
    private var monitor: Any?

    private static func shouldIgnoreSelection(for hitView: NSView) -> Bool {
        var current: NSView? = hitView

        while let view = current {
            let className = NSStringFromClass(type(of: view))

            if view is NSTextView ||
                view is NSControl ||
                view is NSScrollView ||
                view is NSClipView ||
                className.contains("PromptTextEditor")
            {
                return true
            }
            current = view.superview
        }

        return false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()

        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleClick(event)
            return event
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        projectState = nil
        super.removeFromSuperview()
    }

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleClick(_ event: NSEvent) {
        guard let projectState,
              let window
        else { return }

        if let hitView = window.contentView?.hitTest(event.locationInWindow),
           Self.shouldIgnoreSelection(for: hitView)
        {
            return
        }

        // Convert window coords to THIS view's local coords
        let localPoint = convert(event.locationInWindow, from: nil)
        // Flip Y — NSView is bottom-up, SwiftUI canvas is top-down
        let canvasClickPoint = CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)

        // Check if click is even within this view
        guard bounds.contains(localPoint) else { return }

        let zoom = projectState.canvasState.zoom
        let orderedIDs = projectState.nodeZOrder.isEmpty
            ? Array(projectState.nodes.keys)
            : projectState.nodeZOrder

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

            if nodeRect.contains(canvasClickPoint) {
                let isAlreadyPrimarySelection =
                    projectState.selectedNodeIDs.count == 1 &&
                    projectState.selectedNodeIDs.contains(nodeID) &&
                    projectState.selectedConnectionIDs.isEmpty &&
                    projectState.nodeZOrder.last == nodeID

                if isAlreadyPrimarySelection {
                    return
                }

                Task { @MainActor in
                    projectState.selectNode(nodeID)
                    projectState.bringToFront(nodeID)
                }
                return
            }
        }

        Task { @MainActor in
            projectState.deselectAll()
        }
    }
}
