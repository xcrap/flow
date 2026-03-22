import XCTest
@testable import AFCore

final class AFCoreTests: XCTestCase {
    func testWorkflowNodeCreation() throws {
        let node = WorkflowNode(kind: .agent, title: "Test Agent")
        XCTAssertEqual(node.title, "Test Agent")
        XCTAssertEqual(node.kind, .agent)
        XCTAssertEqual(node.executionState, .idle)
    }

    func testNodeTypes() throws {
        let agent = WorkflowNode(kind: .agent, title: "Agent")
        XCTAssertEqual(agent.iconName, "brain")

        let terminal = WorkflowNode(kind: .terminal, title: "Terminal")
        XCTAssertEqual(terminal.iconName, "terminal")
    }

    func testProjectCodable() throws {
        let project = Project(name: "Test Flow")
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.name, "Test Flow")
        XCTAssertEqual(decoded.id, project.id)
    }
}
