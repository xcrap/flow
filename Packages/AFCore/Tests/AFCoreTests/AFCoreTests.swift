import XCTest
import CoreGraphics
@testable import AFCore

final class AFCoreTests: XCTestCase {

    // MARK: - WorkflowNode Creation

    func testWorkflowNodeCreation() throws {
        let node = WorkflowNode(kind: .agent, title: "Test Agent")
        XCTAssertEqual(node.title, "Test Agent")
        XCTAssertEqual(node.kind, .agent)
        XCTAssertEqual(node.executionState, .idle)
        XCTAssertFalse(node.isCollapsed)
    }

    func testWorkflowNodeCreationTerminal() throws {
        let node = WorkflowNode(kind: .terminal, title: "Shell")
        XCTAssertEqual(node.title, "Shell")
        XCTAssertEqual(node.kind, .terminal)
        XCTAssertEqual(node.executionState, .idle)
    }

    func testWorkflowNodeCustomPosition() throws {
        let pos = NodePosition(x: 100, y: 200, width: 300, height: 400)
        let node = WorkflowNode(kind: .agent, title: "Positioned", position: pos)
        XCTAssertEqual(node.position.x, 100)
        XCTAssertEqual(node.position.y, 200)
        XCTAssertEqual(node.position.width, 300)
        XCTAssertEqual(node.position.height, 400)
    }

    func testWorkflowNodeCustomExecutionState() throws {
        let node = WorkflowNode(kind: .agent, title: "Running", executionState: .running)
        XCTAssertEqual(node.executionState, .running)
    }

    func testWorkflowNodeCollapsed() throws {
        let node = WorkflowNode(kind: .agent, title: "Collapsed", isCollapsed: true)
        XCTAssertTrue(node.isCollapsed)
    }

    func testWorkflowNodeUniqueIDs() throws {
        let node1 = WorkflowNode(kind: .agent, title: "A")
        let node2 = WorkflowNode(kind: .agent, title: "B")
        XCTAssertNotEqual(node1.id, node2.id)
    }

    func testWorkflowNodeExplicitID() throws {
        let id = UUID()
        let node = WorkflowNode(id: id, kind: .terminal, title: "Explicit")
        XCTAssertEqual(node.id, id)
    }

    // MARK: - Default Sizes

    func testDefaultSizeAgent() throws {
        let size = WorkflowNode.defaultSize(for: .agent)
        XCTAssertEqual(size.width, 560)
        XCTAssertEqual(size.height, 680)
    }

    func testDefaultSizeTerminal() throws {
        let size = WorkflowNode.defaultSize(for: .terminal)
        XCTAssertEqual(size.width, 560)
        XCTAssertEqual(size.height, 680)
    }

    // MARK: - Icon Names

    func testAgentIconName() throws {
        let agent = WorkflowNode(kind: .agent, title: "Agent")
        XCTAssertEqual(agent.iconName, "brain")
    }

    func testTerminalIconName() throws {
        let terminal = WorkflowNode(kind: .terminal, title: "Terminal")
        XCTAssertEqual(terminal.iconName, "terminal")
    }

    // MARK: - Accent Color Names

    func testAgentAccentColor() throws {
        let agent = WorkflowNode(kind: .agent, title: "Agent")
        XCTAssertEqual(agent.accentColorName, "purple")
    }

    func testTerminalAccentColor() throws {
        let terminal = WorkflowNode(kind: .terminal, title: "Terminal")
        XCTAssertEqual(terminal.accentColorName, "blue")
    }

    // MARK: - NodePosition

    func testNodePositionDefaults() throws {
        let pos = NodePosition()
        XCTAssertEqual(pos.x, 0)
        XCTAssertEqual(pos.y, 0)
        XCTAssertEqual(pos.width, 520)
        XCTAssertEqual(pos.height, 620)
    }

    func testNodePositionPoint() throws {
        let pos = NodePosition(x: 50, y: 75)
        let point = pos.point
        XCTAssertEqual(point.x, 50)
        XCTAssertEqual(point.y, 75)
    }

    func testNodePositionRect() throws {
        let pos = NodePosition(x: 100, y: 200, width: 40, height: 60)
        let rect = pos.rect
        // rect origin is center - half size
        XCTAssertEqual(rect.origin.x, 80)   // 100 - 40/2
        XCTAssertEqual(rect.origin.y, 170)   // 200 - 60/2
        XCTAssertEqual(rect.size.width, 40)
        XCTAssertEqual(rect.size.height, 60)
    }

    func testNodePositionCodable() throws {
        let pos = NodePosition(x: 42, y: 99, width: 200, height: 300)
        let data = try JSONEncoder().encode(pos)
        let decoded = try JSONDecoder().decode(NodePosition.self, from: data)
        XCTAssertEqual(decoded, pos)
    }

    // MARK: - NodeExecutionState

    func testNodeExecutionStateAllCases() throws {
        let idle = NodeExecutionState.idle
        let running = NodeExecutionState.running
        let success = NodeExecutionState.success
        let failure = NodeExecutionState.failure
        let waiting = NodeExecutionState.waitingForApproval

        XCTAssertEqual(idle.rawValue, "idle")
        XCTAssertEqual(running.rawValue, "running")
        XCTAssertEqual(success.rawValue, "success")
        XCTAssertEqual(failure.rawValue, "failure")
        XCTAssertEqual(waiting.rawValue, "waitingForApproval")
    }

    // MARK: - Project

    func testProjectCreationDefaults() throws {
        let project = Project()
        XCTAssertEqual(project.name, "Untitled Project")
        XCTAssertEqual(project.rootPath, NSHomeDirectory())
        XCTAssertEqual(project.description, "")
        XCTAssertEqual(project.canvasZoom, 1.0)
        XCTAssertEqual(project.canvasOffset, CanvasOffset.zero)
    }

    func testProjectCreationWithRootPath() throws {
        let project = Project(name: "My Project", rootPath: "/tmp/testproject")
        XCTAssertEqual(project.name, "My Project")
        XCTAssertEqual(project.rootPath, "/tmp/testproject")
        XCTAssertEqual(project.rootURL, URL(fileURLWithPath: "/tmp/testproject"))
    }

    func testProjectCodable() throws {
        let project = Project(name: "Test Flow", rootPath: "/Users/test/project")
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.name, "Test Flow")
        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.rootPath, "/Users/test/project")
        XCTAssertEqual(decoded.canvasZoom, project.canvasZoom)
        XCTAssertEqual(decoded.canvasOffset, project.canvasOffset)
        XCTAssertEqual(decoded.description, project.description)
    }

    func testProjectCodableWithCustomCanvasState() throws {
        let offset = CanvasOffset(x: 150, y: -200)
        let project = Project(
            name: "Canvas Project",
            rootPath: "/tmp",
            canvasOffset: offset,
            canvasZoom: 2.5
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.canvasOffset.x, 150)
        XCTAssertEqual(decoded.canvasOffset.y, -200)
        XCTAssertEqual(decoded.canvasZoom, 2.5)
    }

    func testProjectEquatable() throws {
        let id = UUID()
        let date = Date()
        let p1 = Project(id: id, name: "A", rootPath: "/a", createdAt: date, updatedAt: date)
        let p2 = Project(id: id, name: "A", rootPath: "/a", createdAt: date, updatedAt: date)
        XCTAssertEqual(p1, p2)
    }

    func testProjectRootURL() throws {
        let project = Project(rootPath: "/Users/developer/code")
        XCTAssertEqual(project.rootURL, URL(fileURLWithPath: "/Users/developer/code"))
    }

    // MARK: - NodeConnection

    func testNodeConnectionCreation() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let conn = NodeConnection(sourceNodeID: sourceID, targetNodeID: targetID)
        XCTAssertEqual(conn.sourceNodeID, sourceID)
        XCTAssertEqual(conn.targetNodeID, targetID)
        XCTAssertEqual(conn.sourcePortID, "output")
        XCTAssertEqual(conn.targetPortID, "input")
        XCTAssertNil(conn.label)
    }

    func testNodeConnectionCustomPorts() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let conn = NodeConnection(
            sourceNodeID: sourceID,
            sourcePortID: "data_out",
            targetNodeID: targetID,
            targetPortID: "data_in",
            label: "Data Flow"
        )
        XCTAssertEqual(conn.sourcePortID, "data_out")
        XCTAssertEqual(conn.targetPortID, "data_in")
        XCTAssertEqual(conn.label, "Data Flow")
    }

    func testNodeConnectionCodable() throws {
        let sourceID = UUID()
        let targetID = UUID()
        let conn = NodeConnection(sourceNodeID: sourceID, targetNodeID: targetID, label: "Test")
        let data = try JSONEncoder().encode(conn)
        let decoded = try JSONDecoder().decode(NodeConnection.self, from: data)
        XCTAssertEqual(decoded.id, conn.id)
        XCTAssertEqual(decoded.sourceNodeID, sourceID)
        XCTAssertEqual(decoded.targetNodeID, targetID)
        XCTAssertEqual(decoded.label, "Test")
    }

    func testNodeConnectionEquatable() throws {
        let id = UUID()
        let src = UUID()
        let tgt = UUID()
        let c1 = NodeConnection(id: id, sourceNodeID: src, targetNodeID: tgt)
        let c2 = NodeConnection(id: id, sourceNodeID: src, targetNodeID: tgt)
        XCTAssertEqual(c1, c2)
    }

    // MARK: - NodeConfiguration

    func testNodeConfigurationDefaults() throws {
        let config = NodeConfiguration()
        XCTAssertNil(config.providerID)
        XCTAssertNil(config.modelID)
        XCTAssertNil(config.effort)
        XCTAssertNil(config.systemPrompt)
        XCTAssertNil(config.temperature)
        XCTAssertNil(config.maxTokens)
        XCTAssertNil(config.language)
        XCTAssertNil(config.script)
        XCTAssertNil(config.conditionExpression)
        XCTAssertNil(config.triggerType)
        XCTAssertNil(config.cronExpression)
        XCTAssertNil(config.transformExpression)
        XCTAssertNil(config.toolName)
        XCTAssertNil(config.toolParameters)
    }

    func testNodeConfigurationAllFields() throws {
        let config = NodeConfiguration(
            providerID: "claude",
            modelID: "sonnet",
            effort: "high",
            systemPrompt: "You are a helper.",
            temperature: 0.7,
            maxTokens: 4096,
            language: "python",
            script: "print('hello')",
            conditionExpression: "x > 5",
            triggerType: "manual",
            cronExpression: "0 * * * *",
            transformExpression: "$.data",
            toolName: "file_reader",
            toolParameters: ["path": "/tmp/test.txt"]
        )
        XCTAssertEqual(config.providerID, "claude")
        XCTAssertEqual(config.modelID, "sonnet")
        XCTAssertEqual(config.effort, "high")
        XCTAssertEqual(config.systemPrompt, "You are a helper.")
        XCTAssertEqual(config.temperature, 0.7)
        XCTAssertEqual(config.maxTokens, 4096)
        XCTAssertEqual(config.language, "python")
        XCTAssertEqual(config.script, "print('hello')")
        XCTAssertEqual(config.conditionExpression, "x > 5")
        XCTAssertEqual(config.triggerType, "manual")
        XCTAssertEqual(config.cronExpression, "0 * * * *")
        XCTAssertEqual(config.transformExpression, "$.data")
        XCTAssertEqual(config.toolName, "file_reader")
        XCTAssertEqual(config.toolParameters, ["path": "/tmp/test.txt"])
    }

    func testNodeConfigurationCodable() throws {
        let config = NodeConfiguration(
            providerID: "openai",
            modelID: "gpt-4",
            temperature: 0.5,
            maxTokens: 2048
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(NodeConfiguration.self, from: data)
        XCTAssertEqual(decoded.providerID, "openai")
        XCTAssertEqual(decoded.modelID, "gpt-4")
        XCTAssertEqual(decoded.temperature, 0.5)
        XCTAssertEqual(decoded.maxTokens, 2048)
        XCTAssertNil(decoded.language)
    }

    func testNodeConfigurationEquatable() throws {
        let c1 = NodeConfiguration(providerID: "claude", modelID: "sonnet")
        let c2 = NodeConfiguration(providerID: "claude", modelID: "sonnet")
        XCTAssertEqual(c1, c2)

        let c3 = NodeConfiguration(providerID: "claude", modelID: "opus")
        XCTAssertNotEqual(c1, c3)
    }

    // MARK: - ConversationMessage

    func testConversationMessageCreation() throws {
        let msg = ConversationMessage(role: .user, content: [.text("Hello")])
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content.count, 1)
        XCTAssertEqual(msg.textContent, "Hello")
    }

    func testConversationMessageTextContentMultiple() throws {
        let msg = ConversationMessage(
            role: .assistant,
            content: [.text("Part 1"), .text(" Part 2")]
        )
        XCTAssertEqual(msg.textContent, "Part 1 Part 2")
    }

    func testConversationMessageTextContentSkipsNonText() throws {
        let msg = ConversationMessage(
            role: .assistant,
            content: [
                .text("Hello"),
                .code(language: "swift", code: "let x = 1"),
                .text(" World"),
            ]
        )
        XCTAssertEqual(msg.textContent, "Hello World")
    }

    func testConversationMessageCodable() throws {
        let msg = ConversationMessage(
            role: .assistant,
            content: [.text("Response")]
        )
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ConversationMessage.self, from: data)
        XCTAssertEqual(decoded.id, msg.id)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.textContent, "Response")
    }

    // MARK: - MessageContent Encoding/Decoding

    func testMessageContentTextCodable() throws {
        let content = MessageContent.text("Hello world")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentCodeCodable() throws {
        let content = MessageContent.code(language: "swift", code: "let x = 42")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentImageCodable() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let content = MessageContent.image(data: imageData, mimeType: "image/jpeg")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentToolUseCodable() throws {
        let content = MessageContent.toolUse(id: "tool-1", name: "read_file", input: "{\"path\":\"/tmp\"}")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentToolResultCodable() throws {
        let content = MessageContent.toolResult(id: "tool-1", content: "file contents here", isError: false)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentToolResultErrorCodable() throws {
        let content = MessageContent.toolResult(id: "tool-2", content: "File not found", isError: true)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(MessageContent.self, from: data)
        XCTAssertEqual(decoded, content)
    }

    func testMessageContentUnknownTypeDecoding() throws {
        let json = #"{"type":"unknown","foo":"bar"}"#
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(MessageContent.self, from: data))
    }

    // MARK: - MessageRole

    func testMessageRoleRawValues() throws {
        XCTAssertEqual(MessageRole.system.rawValue, "system")
        XCTAssertEqual(MessageRole.user.rawValue, "user")
        XCTAssertEqual(MessageRole.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageRole.tool.rawValue, "tool")
    }

    // MARK: - Conversation

    func testConversationCreation() throws {
        let nodeID = UUID()
        let conv = Conversation(nodeID: nodeID)
        XCTAssertEqual(conv.nodeID, nodeID)
        XCTAssertTrue(conv.messages.isEmpty)
    }

    func testConversationWithMessages() throws {
        let nodeID = UUID()
        let msgs = [
            ConversationMessage(role: .user, content: [.text("Hello")]),
            ConversationMessage(role: .assistant, content: [.text("Hi!")]),
        ]
        let conv = Conversation(nodeID: nodeID, messages: msgs)
        XCTAssertEqual(conv.messages.count, 2)
    }

    func testConversationCodable() throws {
        let nodeID = UUID()
        let conv = Conversation(nodeID: nodeID, messages: [
            ConversationMessage(role: .user, content: [.text("Test")])
        ])
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.id, conv.id)
        XCTAssertEqual(decoded.nodeID, nodeID)
        XCTAssertEqual(decoded.messages.count, 1)
    }

    // MARK: - CanvasOffset

    func testCanvasOffsetZero() throws {
        let offset = CanvasOffset.zero
        XCTAssertEqual(offset.x, 0)
        XCTAssertEqual(offset.y, 0)
    }

    func testCanvasOffsetToCGPoint() throws {
        let offset = CanvasOffset(x: 10.5, y: -20.3)
        let point = offset.cgPoint
        XCTAssertEqual(point.x, 10.5)
        XCTAssertEqual(point.y, -20.3)
    }

    func testCanvasOffsetFromCGPoint() throws {
        let point = CGPoint(x: 42.0, y: -17.5)
        let offset = CanvasOffset(point)
        XCTAssertEqual(offset.x, 42.0)
        XCTAssertEqual(offset.y, -17.5)
    }

    func testCanvasOffsetRoundTrip() throws {
        let original = CGPoint(x: 123.456, y: -789.012)
        let offset = CanvasOffset(original)
        let recovered = offset.cgPoint
        XCTAssertEqual(recovered.x, original.x, accuracy: 0.001)
        XCTAssertEqual(recovered.y, original.y, accuracy: 0.001)
    }

    func testCanvasOffsetCodable() throws {
        let offset = CanvasOffset(x: 55, y: -33)
        let data = try JSONEncoder().encode(offset)
        let decoded = try JSONDecoder().decode(CanvasOffset.self, from: data)
        XCTAssertEqual(decoded, offset)
    }

    func testCanvasOffsetEquatable() throws {
        let a = CanvasOffset(x: 1, y: 2)
        let b = CanvasOffset(x: 1, y: 2)
        let c = CanvasOffset(x: 3, y: 4)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - NodeKind

    func testNodeKindRawValues() throws {
        XCTAssertEqual(NodeKind.agent.rawValue, "agent")
        XCTAssertEqual(NodeKind.terminal.rawValue, "terminal")
    }

    func testNodeKindAllCases() throws {
        XCTAssertEqual(NodeKind.allCases.count, 2)
        XCTAssertTrue(NodeKind.allCases.contains(.agent))
        XCTAssertTrue(NodeKind.allCases.contains(.terminal))
    }

    // MARK: - WorkflowNode Codable

    func testWorkflowNodeCodable() throws {
        let config = NodeConfiguration(providerID: "claude", modelID: "sonnet")
        let node = WorkflowNode(
            kind: .agent,
            title: "My Agent",
            position: NodePosition(x: 10, y: 20),
            isCollapsed: true,
            configuration: config,
            executionState: .success
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(WorkflowNode.self, from: data)
        XCTAssertEqual(decoded.id, node.id)
        XCTAssertEqual(decoded.kind, .agent)
        XCTAssertEqual(decoded.title, "My Agent")
        XCTAssertEqual(decoded.position.x, 10)
        XCTAssertEqual(decoded.position.y, 20)
        XCTAssertTrue(decoded.isCollapsed)
        XCTAssertEqual(decoded.configuration.providerID, "claude")
        XCTAssertEqual(decoded.executionState, .success)
    }

    // MARK: - ToolApproval

    func testToolApprovalRequestCreation() throws {
        let nodeID = UUID()
        let req = ToolApprovalRequest(
            toolName: "bash",
            description: "Run a command",
            parameters: ["cmd": "ls"],
            riskLevel: .dangerous,
            nodeID: nodeID
        )
        XCTAssertEqual(req.toolName, "bash")
        XCTAssertEqual(req.description, "Run a command")
        XCTAssertEqual(req.riskLevel, .dangerous)
        XCTAssertEqual(req.status, .pending)
        XCTAssertEqual(req.nodeID, nodeID)
        XCTAssertEqual(req.parameters["cmd"], "ls")
    }

    func testToolRiskLevelRawValues() throws {
        XCTAssertEqual(ToolRiskLevel.safe.rawValue, "safe")
        XCTAssertEqual(ToolRiskLevel.moderate.rawValue, "moderate")
        XCTAssertEqual(ToolRiskLevel.dangerous.rawValue, "dangerous")
    }

    func testApprovalStatusRawValues() throws {
        XCTAssertEqual(ApprovalStatus.pending.rawValue, "pending")
        XCTAssertEqual(ApprovalStatus.approved.rawValue, "approved")
        XCTAssertEqual(ApprovalStatus.denied.rawValue, "denied")
    }

    // MARK: - ProjectSession

    func testProjectSessionCreation() throws {
        let projectID = UUID()
        let session = ProjectSession(projectID: projectID)
        XCTAssertEqual(session.projectID, projectID)
        XCTAssertEqual(session.status, .active)
        XCTAssertNil(session.endedAt)
        XCTAssertTrue(session.executionLog.isEmpty)
    }

    func testSessionStatusRawValues() throws {
        XCTAssertEqual(SessionStatus.active.rawValue, "active")
        XCTAssertEqual(SessionStatus.paused.rawValue, "paused")
        XCTAssertEqual(SessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(SessionStatus.failed.rawValue, "failed")
    }

    func testExecutionLogEntry() throws {
        let nodeID = UUID()
        let entry = ExecutionLogEntry(nodeID: nodeID, event: "started", data: "{\"key\":\"value\"}")
        XCTAssertEqual(entry.nodeID, nodeID)
        XCTAssertEqual(entry.event, "started")
        XCTAssertEqual(entry.data, "{\"key\":\"value\"}")
    }

    // MARK: - Checkpoint

    func testCheckpointCreation() throws {
        let projectID = UUID()
        let snapshot = Data("snapshot".utf8)
        let cp = Checkpoint(projectID: projectID, label: "Before refactor", snapshotData: snapshot)
        XCTAssertEqual(cp.projectID, projectID)
        XCTAssertEqual(cp.label, "Before refactor")
        XCTAssertEqual(cp.snapshotData, snapshot)
    }

    func testCheckpointDefaultSnapshotData() throws {
        let projectID = UUID()
        let cp = Checkpoint(projectID: projectID, label: "Empty")
        XCTAssertEqual(cp.snapshotData, Data())
    }
}
