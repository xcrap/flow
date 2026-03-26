import XCTest
import CoreGraphics
@testable import AFCanvas
@testable import AFCore

// MARK: - ProjectState Tests

final class ProjectStateTests: XCTestCase {

    // MARK: - addNode

    @MainActor
    func testAddNodeAgent() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "Agent 1", at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(node.kind, .agent)
        XCTAssertEqual(node.title, "Agent 1")
        XCTAssertEqual(node.position.x, 100)
        XCTAssertEqual(node.position.y, 200)
        // Default size for agent
        XCTAssertEqual(node.position.width, 560)
        XCTAssertEqual(node.position.height, 680)
        // Should be stored
        XCTAssertNotNil(state.nodes[node.id])
    }

    @MainActor
    func testAddNodeTerminal() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .terminal, title: "Shell", at: CGPoint(x: 50, y: 75))
        XCTAssertEqual(node.kind, .terminal)
        XCTAssertEqual(node.title, "Shell")
        XCTAssertNotNil(state.nodes[node.id])
    }

    @MainActor
    func testAddMultipleNodes() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(state.nodes.count, 2)
        XCTAssertNotNil(state.nodes[n1.id])
        XCTAssertNotNil(state.nodes[n2.id])
    }

    @MainActor
    func testAddNodeDefaultConfiguration() throws {
        let state = ProjectState()
        let agent = state.addNode(kind: .agent, title: "Agent", at: .zero)
        XCTAssertEqual(agent.configuration.providerID, "claude")
        XCTAssertEqual(agent.configuration.modelID, "sonnet")

        let terminal = state.addNode(kind: .terminal, title: "Term", at: .zero)
        XCTAssertEqual(terminal.configuration.language, "bash")
    }

    @MainActor
    func testAddNodeTriggersOnChange() throws {
        let state = ProjectState()
        var called = false
        state.onChange = { called = true }
        state.addNode(kind: .agent, title: "A", at: .zero)
        XCTAssertTrue(called)
    }

    // MARK: - removeNode

    @MainActor
    func testRemoveNode() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "To Remove", at: .zero)
        XCTAssertEqual(state.nodes.count, 1)
        state.removeNode(node.id)
        XCTAssertEqual(state.nodes.count, 0)
        XCTAssertNil(state.nodes[node.id])
    }

    @MainActor
    func testRemoveNodeRemovesConnections() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 200, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)
        XCTAssertNotNil(conn)
        XCTAssertEqual(state.connections.count, 1)

        state.removeNode(n1.id)
        XCTAssertEqual(state.connections.count, 0)
    }

    @MainActor
    func testRemoveNodeRemovesFromSelection() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "Selected", at: .zero)
        state.selectNode(node.id)
        XCTAssertTrue(state.selectedNodeIDs.contains(node.id))

        state.removeNode(node.id)
        XCTAssertFalse(state.selectedNodeIDs.contains(node.id))
    }

    @MainActor
    func testRemoveNonexistentNodeIsHarmless() throws {
        let state = ProjectState()
        state.addNode(kind: .agent, title: "A", at: .zero)
        state.removeNode(UUID()) // should not crash
        XCTAssertEqual(state.nodes.count, 1)
    }

    // MARK: - moveNode

    @MainActor
    func testMoveNode() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "Movable", at: CGPoint(x: 0, y: 0))
        state.moveNode(node.id, to: CGPoint(x: 300, y: 400))
        XCTAssertEqual(state.nodes[node.id]?.position.x, 300)
        XCTAssertEqual(state.nodes[node.id]?.position.y, 400)
    }

    @MainActor
    func testMoveNonexistentNode() throws {
        let state = ProjectState()
        // Should not crash
        state.moveNode(UUID(), to: CGPoint(x: 100, y: 100))
        XCTAssertTrue(state.nodes.isEmpty)
    }

    // MARK: - selectNode

    @MainActor
    func testSelectNodeSingle() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 100, y: 0))

        state.selectNode(n1.id)
        XCTAssertEqual(state.selectedNodeIDs, [n1.id])

        // Selecting another without additive replaces
        state.selectNode(n2.id)
        XCTAssertEqual(state.selectedNodeIDs, [n2.id])
    }

    @MainActor
    func testSelectNodeAdditive() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 100, y: 0))

        state.selectNode(n1.id)
        state.selectNode(n2.id, additive: true)
        XCTAssertEqual(state.selectedNodeIDs, [n1.id, n2.id])
    }

    @MainActor
    func testSelectNodeClearsConnectionSelection() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 200, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)!
        state.selectedConnectionIDs.insert(conn.id)

        state.selectNode(n1.id) // non-additive should clear connections
        XCTAssertTrue(state.selectedConnectionIDs.isEmpty)
    }

    @MainActor
    func testSelectNodeSameSingleSelectionIsNoOp() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "A", at: .zero)

        state.selectedNodeIDs = [node.id]
        state.selectedConnectionIDs = []

        state.selectNode(node.id)

        XCTAssertEqual(state.selectedNodeIDs, [node.id])
        XCTAssertTrue(state.selectedConnectionIDs.isEmpty)
    }

    // MARK: - selectAll

    @MainActor
    func testSelectAll() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 100, y: 0))
        let n3 = state.addNode(kind: .agent, title: "C", at: CGPoint(x: 200, y: 0))

        state.selectAll()
        XCTAssertEqual(state.selectedNodeIDs.count, 3)
        XCTAssertTrue(state.selectedNodeIDs.contains(n1.id))
        XCTAssertTrue(state.selectedNodeIDs.contains(n2.id))
        XCTAssertTrue(state.selectedNodeIDs.contains(n3.id))
    }

    @MainActor
    func testSelectAllEmpty() throws {
        let state = ProjectState()
        state.selectAll()
        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
    }

    // MARK: - deselectAll

    @MainActor
    func testDeselectAll() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 100, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)!

        state.selectAll()
        state.selectedConnectionIDs.insert(conn.id)

        state.deselectAll()
        XCTAssertTrue(state.selectedNodeIDs.isEmpty)
        XCTAssertTrue(state.selectedConnectionIDs.isEmpty)
    }

    // MARK: - deleteSelected

    @MainActor
    func testDeleteSelectedNodes() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 100, y: 0))
        let _ = state.addNode(kind: .agent, title: "C", at: CGPoint(x: 200, y: 0))

        state.selectNode(n1.id)
        state.selectNode(n2.id, additive: true)

        state.deleteSelected()
        XCTAssertEqual(state.nodes.count, 1) // only C remains
        XCTAssertNil(state.nodes[n1.id])
        XCTAssertNil(state.nodes[n2.id])
    }

    @MainActor
    func testDeleteSelectedConnections() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 200, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)!

        state.selectedConnectionIDs.insert(conn.id)
        state.deleteSelected()
        XCTAssertTrue(state.connections.isEmpty)
        // Nodes should still exist
        XCTAssertEqual(state.nodes.count, 2)
    }

    @MainActor
    func testDeleteSelectedWithNoSelection() throws {
        let state = ProjectState()
        state.addNode(kind: .agent, title: "A", at: .zero)
        state.deleteSelected()
        XCTAssertEqual(state.nodes.count, 1) // nothing deleted
    }

    // MARK: - Connection Operations

    @MainActor
    func testAddConnection() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 200, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)
        XCTAssertNotNil(conn)
        XCTAssertEqual(conn?.sourceNodeID, n1.id)
        XCTAssertEqual(conn?.targetNodeID, n2.id)
        XCTAssertEqual(conn?.sourcePortID, "output")
        XCTAssertEqual(conn?.targetPortID, "input")
        XCTAssertEqual(state.connections.count, 1)
    }

    @MainActor
    func testAddConnectionPreventsSelfConnection() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "Self", at: .zero)
        let conn = state.addConnection(from: node.id, to: node.id)
        XCTAssertNil(conn)
        XCTAssertTrue(state.connections.isEmpty)
    }

    @MainActor
    func testAddConnectionPreventsDuplicates() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 200, y: 0))

        let conn1 = state.addConnection(from: n1.id, to: n2.id)
        let conn2 = state.addConnection(from: n1.id, to: n2.id)
        XCTAssertNotNil(conn1)
        XCTAssertNil(conn2)
        XCTAssertEqual(state.connections.count, 1)
    }

    @MainActor
    func testRemoveConnection() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: .zero)
        let n2 = state.addNode(kind: .terminal, title: "B", at: CGPoint(x: 200, y: 0))
        let conn = state.addConnection(from: n1.id, to: n2.id)!

        state.selectedConnectionIDs.insert(conn.id)
        state.removeConnection(conn.id)
        XCTAssertTrue(state.connections.isEmpty)
        XCTAssertFalse(state.selectedConnectionIDs.contains(conn.id))
    }

    // MARK: - Drag Operations

    @MainActor
    func testStoreDragStartPositionsForSelectedNode() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: CGPoint(x: 10, y: 20))
        let _ = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 30, y: 40))

        state.selectNode(n1.id)

        state.storeDragStartPositions(for: n1.id)
        // Only the dragged node stored (single-node drag)
        XCTAssertEqual(state.dragStartPositions.count, 1)
        XCTAssertEqual(state.dragStartPositions[n1.id], CGPoint(x: 10, y: 20))
    }

    @MainActor
    func testStoreDragStartPositionsForUnselectedNode() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: CGPoint(x: 10, y: 20))
        let n2 = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 30, y: 40))

        // n2 is not selected, drag n2
        state.selectNode(n1.id)
        state.storeDragStartPositions(for: n2.id)
        // Only the dragged node gets stored (not the selected one)
        XCTAssertEqual(state.dragStartPositions.count, 1)
        XCTAssertEqual(state.dragStartPositions[n2.id], CGPoint(x: 30, y: 40))
    }

    @MainActor
    func testApplyDragTranslationSingleNode() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: CGPoint(x: 10, y: 20))
        let n2 = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 30, y: 40))

        state.storeDragStartPositions(for: n1.id)
        state.applyDragTranslation(CGPoint(x: 100, y: 50), for: n1.id)

        XCTAssertEqual(state.nodes[n1.id]?.position.x, 110) // 10 + 100
        XCTAssertEqual(state.nodes[n1.id]?.position.y, 70)  // 20 + 50
        // n2 should NOT move
        XCTAssertEqual(state.nodes[n2.id]?.position.x, 30)
        XCTAssertEqual(state.nodes[n2.id]?.position.y, 40)
    }

    @MainActor
    func testApplyDragTranslationUnselectedNode() throws {
        let state = ProjectState()
        let n1 = state.addNode(kind: .agent, title: "A", at: CGPoint(x: 10, y: 20))

        // Not selected, drag directly
        state.storeDragStartPositions(for: n1.id)
        state.applyDragTranslation(CGPoint(x: 50, y: -10), for: n1.id)

        XCTAssertEqual(state.nodes[n1.id]?.position.x, 60)  // 10 + 50
        XCTAssertEqual(state.nodes[n1.id]?.position.y, 10)  // 20 + (-10)
    }

    @MainActor
    func testClearDragStartPositions() throws {
        let state = ProjectState()
        let node = state.addNode(kind: .agent, title: "A", at: CGPoint(x: 10, y: 20))
        state.storeDragStartPositions(for: node.id)
        XCTAssertFalse(state.dragStartPositions.isEmpty)

        var onChangeCalled = false
        state.onChange = { onChangeCalled = true }

        state.clearDragStartPositions()
        XCTAssertTrue(state.dragStartPositions.isEmpty)
        XCTAssertTrue(onChangeCalled)
    }

    @MainActor
    func testBringToFrontFrontmostNodeIsNoOp() throws {
        let state = ProjectState()
        state.addNode(kind: .agent, title: "A", at: .zero)
        let frontmost = state.addNode(kind: .agent, title: "B", at: CGPoint(x: 200, y: 0))
        let originalOrder = state.nodeZOrder

        state.bringToFront(frontmost.id)

        XCTAssertEqual(state.nodeZOrder, originalOrder)
        XCTAssertEqual(state.nodeZOrder.last, frontmost.id)
    }

    // MARK: - Helpers

    @MainActor
    func testSortedNodes() throws {
        let state = ProjectState()
        state.addNode(kind: .agent, title: "Right", at: CGPoint(x: 300, y: 0))
        state.addNode(kind: .agent, title: "Left", at: CGPoint(x: 100, y: 0))
        state.addNode(kind: .agent, title: "Middle", at: CGPoint(x: 200, y: 0))

        let sorted = state.sortedNodes
        XCTAssertEqual(sorted[0].title, "Left")
        XCTAssertEqual(sorted[1].title, "Middle")
        XCTAssertEqual(sorted[2].title, "Right")
    }

    @MainActor
    func testNodesInRect() throws {
        let state = ProjectState()
        // Node at (100, 100) with size 560x680 -> rect is (100-280, 100-340, 560, 680) = (-180, -240, 560, 680)
        let n1 = state.addNode(kind: .agent, title: "Inside", at: CGPoint(x: 100, y: 100))
        // Node at (2000, 2000) -> far away
        state.addNode(kind: .agent, title: "Outside", at: CGPoint(x: 2000, y: 2000))

        let searchRect = CGRect(x: -200, y: -250, width: 600, height: 700)
        let found = state.nodesInRect(searchRect)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].id, n1.id)
    }
}

// MARK: - CanvasState Tests

final class CanvasStateTests: XCTestCase {

    @MainActor
    func testCanvasToScreenDefaultZoom() throws {
        let canvas = CanvasState()
        // Default zoom=1, offset=(0,0)
        let result = canvas.canvasToScreen(CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.x, 100)
        XCTAssertEqual(result.y, 200)
    }

    @MainActor
    func testCanvasToScreenWithZoom() throws {
        let canvas = CanvasState()
        canvas.zoom = 2.0
        canvas.offset = .zero
        let result = canvas.canvasToScreen(CGPoint(x: 100, y: 50))
        XCTAssertEqual(result.x, 200) // 100 * 2
        XCTAssertEqual(result.y, 100) // 50 * 2
    }

    @MainActor
    func testCanvasToScreenWithOffset() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.0
        canvas.offset = CGPoint(x: 50, y: -30)
        let result = canvas.canvasToScreen(CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.x, 150) // 100 * 1 + 50
        XCTAssertEqual(result.y, 170) // 200 * 1 + (-30)
    }

    @MainActor
    func testCanvasToScreenWithZoomAndOffset() throws {
        let canvas = CanvasState()
        canvas.zoom = 0.5
        canvas.offset = CGPoint(x: 20, y: 10)
        let result = canvas.canvasToScreen(CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.x, 70)  // 100 * 0.5 + 20
        XCTAssertEqual(result.y, 110) // 200 * 0.5 + 10
    }

    @MainActor
    func testScreenToCanvasDefaultZoom() throws {
        let canvas = CanvasState()
        let result = canvas.screenToCanvas(CGPoint(x: 100, y: 200))
        XCTAssertEqual(result.x, 100)
        XCTAssertEqual(result.y, 200)
    }

    @MainActor
    func testScreenToCanvasWithZoom() throws {
        let canvas = CanvasState()
        canvas.zoom = 2.0
        canvas.offset = .zero
        let result = canvas.screenToCanvas(CGPoint(x: 200, y: 100))
        XCTAssertEqual(result.x, 100) // 200 / 2
        XCTAssertEqual(result.y, 50)  // 100 / 2
    }

    @MainActor
    func testScreenToCanvasWithOffset() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.0
        canvas.offset = CGPoint(x: 50, y: -30)
        let result = canvas.screenToCanvas(CGPoint(x: 150, y: 170))
        XCTAssertEqual(result.x, 100) // (150 - 50) / 1
        XCTAssertEqual(result.y, 200) // (170 - (-30)) / 1
    }

    @MainActor
    func testScreenToCanvasRoundTrip() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.5
        canvas.offset = CGPoint(x: 30, y: -20)

        let original = CGPoint(x: 150, y: 250)
        let screen = canvas.canvasToScreen(original)
        let recovered = canvas.screenToCanvas(screen)
        XCTAssertEqual(recovered.x, original.x, accuracy: 0.001)
        XCTAssertEqual(recovered.y, original.y, accuracy: 0.001)
    }

    @MainActor
    func testCenterOnCanvasPointPreservesCurrentZoom() throws {
        let canvas = CanvasState()
        canvas.zoom = 2.0

        canvas.center(on: CGPoint(x: 100, y: 50), in: CGSize(width: 800, height: 600))

        XCTAssertEqual(canvas.zoom, 2.0)
        XCTAssertEqual(canvas.offset.x, 200)
        XCTAssertEqual(canvas.offset.y, 200)
    }

    @MainActor
    func testCenterOnCanvasPointWithTargetZoom() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.0

        canvas.center(on: CGPoint(x: 120, y: 80), in: CGSize(width: 1000, height: 700), zoom: 1.5)

        XCTAssertEqual(canvas.zoom, 1.5)
        XCTAssertEqual(canvas.offset.x, 320)
        XCTAssertEqual(canvas.offset.y, 230)
    }

    @MainActor
    func testVisibleRect() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.0
        canvas.offset = .zero

        let rect = canvas.visibleRect(in: CGSize(width: 800, height: 600))
        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.origin.y, 0)
        XCTAssertEqual(rect.size.width, 800)
        XCTAssertEqual(rect.size.height, 600)
    }

    @MainActor
    func testVisibleRectWithZoom() throws {
        let canvas = CanvasState()
        canvas.zoom = 2.0
        canvas.offset = .zero

        let rect = canvas.visibleRect(in: CGSize(width: 800, height: 600))
        XCTAssertEqual(rect.origin.x, 0)
        XCTAssertEqual(rect.origin.y, 0)
        XCTAssertEqual(rect.size.width, 400)  // 800/2
        XCTAssertEqual(rect.size.height, 300) // 600/2
    }

    @MainActor
    func testVisibleRectWithOffset() throws {
        let canvas = CanvasState()
        canvas.zoom = 1.0
        canvas.offset = CGPoint(x: -100, y: -50)

        let rect = canvas.visibleRect(in: CGSize(width: 800, height: 600))
        // origin = screenToCanvas(.zero) = (0 - (-100))/1, (0 - (-50))/1 = (100, 50)
        XCTAssertEqual(rect.origin.x, 100)
        XCTAssertEqual(rect.origin.y, 50)
        XCTAssertEqual(rect.size.width, 800)
        XCTAssertEqual(rect.size.height, 600)
    }

    @MainActor
    func testVisibleRectWithZoomAndOffset() throws {
        let canvas = CanvasState()
        canvas.zoom = 2.0
        canvas.offset = CGPoint(x: -200, y: -100)

        let rect = canvas.visibleRect(in: CGSize(width: 800, height: 600))
        // origin = screenToCanvas(.zero) = (0 - (-200))/2, (0 - (-100))/2 = (100, 50)
        XCTAssertEqual(rect.origin.x, 100)
        XCTAssertEqual(rect.origin.y, 50)
        // extent = screenToCanvas(800, 600) = (800 - (-200))/2, (600 - (-100))/2 = (500, 350)
        // width = 500 - 100 = 400, height = 350 - 50 = 300
        XCTAssertEqual(rect.size.width, 400)
        XCTAssertEqual(rect.size.height, 300)
    }

    @MainActor
    func testCanvasStateDefaults() throws {
        let canvas = CanvasState()
        XCTAssertEqual(canvas.offset, .zero)
        XCTAssertEqual(canvas.zoom, 1.0)
        XCTAssertEqual(canvas.gridSize, 20.0)
        XCTAssertFalse(canvas.isDragging)
        XCTAssertNil(canvas.draggedNodeID)
        XCTAssertFalse(canvas.isDrawingConnection)
        XCTAssertNil(canvas.connectionDraftSource)
        XCTAssertNil(canvas.connectionDraftEndPoint)
        XCTAssertNil(canvas.marqueeOrigin)
        XCTAssertNil(canvas.marqueeRect)
    }
}

// MARK: - AppState Tests

final class AppStateTests: XCTestCase {

    @MainActor
    func testAppStateInitiallyEmpty() throws {
        let app = AppState()
        XCTAssertTrue(app.openProjects.isEmpty)
        XCTAssertNil(app.activeProjectID)
        XCTAssertFalse(app.hasProjects)
        XCTAssertNil(app.activeProject)
    }

    @MainActor
    func testCreateProject() throws {
        let app = AppState()
        let projectState = app.createProject(name: "Test Project", rootPath: "/tmp/test")
        XCTAssertEqual(app.openProjects.count, 1)
        XCTAssertEqual(projectState.project.name, "Test Project")
        XCTAssertEqual(projectState.project.rootPath, "/tmp/test")
        XCTAssertEqual(app.activeProjectID, projectState.project.id)
        XCTAssertTrue(app.hasProjects)
    }

    @MainActor
    func testCreateMultipleProjects() throws {
        let app = AppState()
        let p1 = app.createProject(name: "Project 1", rootPath: "/tmp/p1")
        let p2 = app.createProject(name: "Project 2", rootPath: "/tmp/p2")
        XCTAssertEqual(app.openProjects.count, 2)
        // Active should be the last created
        XCTAssertEqual(app.activeProjectID, p2.project.id)
        XCTAssertNotEqual(p1.project.id, p2.project.id)
    }

    @MainActor
    func testActiveProject() throws {
        let app = AppState()
        let p1 = app.createProject(name: "P1", rootPath: "/tmp/p1")
        let _ = app.createProject(name: "P2", rootPath: "/tmp/p2")

        // Active is P2 (last created)
        app.activeProjectID = p1.project.id
        XCTAssertEqual(app.activeProject?.project.id, p1.project.id)
    }

    @MainActor
    func testDeleteProject() throws {
        let app = AppState()
        let p1 = app.createProject(name: "P1", rootPath: "/tmp/p1")
        let p2 = app.createProject(name: "P2", rootPath: "/tmp/p2")

        app.deleteProject(p2.project.id)
        XCTAssertEqual(app.openProjects.count, 1)
        // Active should switch to first remaining
        XCTAssertEqual(app.activeProjectID, p1.project.id)
    }

    @MainActor
    func testDeleteActiveProjectSwitchesToFirst() throws {
        let app = AppState()
        let p1 = app.createProject(name: "P1", rootPath: "/tmp/p1")
        let p2 = app.createProject(name: "P2", rootPath: "/tmp/p2")

        // p2 is active
        XCTAssertEqual(app.activeProjectID, p2.project.id)
        app.deleteProject(p2.project.id)
        XCTAssertEqual(app.activeProjectID, p1.project.id)
    }

    @MainActor
    func testDeleteLastProject() throws {
        let app = AppState()
        let p = app.createProject(name: "Only", rootPath: "/tmp/only")
        app.deleteProject(p.project.id)
        XCTAssertTrue(app.openProjects.isEmpty)
        XCTAssertNil(app.activeProjectID)
        XCTAssertFalse(app.hasProjects)
    }

    @MainActor
    func testDeleteNonActiveProject() throws {
        let app = AppState()
        let p1 = app.createProject(name: "P1", rootPath: "/tmp/p1")
        let p2 = app.createProject(name: "P2", rootPath: "/tmp/p2")

        // p2 is active, delete p1
        app.deleteProject(p1.project.id)
        XCTAssertEqual(app.openProjects.count, 1)
        // Active stays as p2
        XCTAssertEqual(app.activeProjectID, p2.project.id)
    }

    @MainActor
    func testDeleteNonExistentProject() throws {
        let app = AppState()
        app.createProject(name: "P1", rootPath: "/tmp/p1")
        app.deleteProject(UUID()) // should not crash
        XCTAssertEqual(app.openProjects.count, 1)
    }

    @MainActor
    func testCreateProjectSetsOnChange() throws {
        let app = AppState()
        let projectState = app.createProject(name: "P", rootPath: "/tmp")
        XCTAssertNotNil(projectState.onChange)
    }
}

// MARK: - ConnectionDraft Tests

final class ConnectionDraftTests: XCTestCase {
    func testConnectionDraftCreation() throws {
        let nodeID = UUID()
        let draft = ConnectionDraft(nodeID: nodeID, portID: "output")
        XCTAssertEqual(draft.nodeID, nodeID)
        XCTAssertEqual(draft.portID, "output")
        XCTAssertFalse(draft.isInput)
    }

    func testConnectionDraftInput() throws {
        let nodeID = UUID()
        let draft = ConnectionDraft(nodeID: nodeID, portID: "input", isInput: true)
        XCTAssertTrue(draft.isInput)
    }
}

// MARK: - SidebarItem Tests

final class SidebarItemTests: XCTestCase {
    func testSidebarItemProject() throws {
        let id = UUID()
        let item = SidebarItem.project(id)
        if case .project(let itemID) = item {
            XCTAssertEqual(itemID, id)
        } else {
            XCTFail("Expected .project case")
        }
    }

    func testSidebarItemSessions() throws {
        let item = SidebarItem.sessions
        if case .sessions = item {} else {
            XCTFail("Expected .sessions case")
        }
    }

    func testSidebarItemSettings() throws {
        let item = SidebarItem.settings
        if case .settings = item {} else {
            XCTFail("Expected .settings case")
        }
    }

    func testSidebarItemHashable() throws {
        let id = UUID()
        let a = SidebarItem.project(id)
        let b = SidebarItem.project(id)
        XCTAssertEqual(a, b)

        let set: Set<SidebarItem> = [.sessions, .settings, .project(id)]
        XCTAssertEqual(set.count, 3)
    }
}
