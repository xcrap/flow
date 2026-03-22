import XCTest
import CoreGraphics
@testable import AFAgent
@testable import AFCore

// MARK: - ClaudeCodeProvider.parseStreamEvent Tests

final class ClaudeCodeProviderParseTests: XCTestCase {

    // MARK: - System Event

    func testParseSystemEvent() throws {
        let json = """
        {"type":"system","session_id":"sess-123","model":"claude-sonnet-4-20250514"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .initialized(let sessionID, let model) = event {
            XCTAssertEqual(sessionID, "sess-123")
            XCTAssertEqual(model, "claude-sonnet-4-20250514")
        } else {
            XCTFail("Expected .initialized, got \(String(describing: event))")
        }
    }

    func testParseSystemEventMissingFields() throws {
        let json = """
        {"type":"system"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .initialized(let sessionID, let model) = event {
            XCTAssertEqual(sessionID, "")
            XCTAssertEqual(model, "")
        } else {
            XCTFail("Expected .initialized with empty defaults")
        }
    }

    // MARK: - Stream Event: content_block_delta

    func testParseContentBlockDelta() throws {
        let json = """
        {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello world"}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .textDelta(let text) = event {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .textDelta, got \(String(describing: event))")
        }
    }

    func testParseContentBlockDeltaWithSpecialChars() throws {
        let json = """
        {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Line 1\\nLine 2"}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .textDelta(let text) = event {
            XCTAssertEqual(text, "Line 1\nLine 2")
        } else {
            XCTFail("Expected .textDelta")
        }
    }

    func testParseContentBlockDeltaNonTextDelta() throws {
        // delta type is not text_delta -- should return nil
        let json = """
        {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    func testParseContentBlockDeltaMissingDelta() throws {
        let json = """
        {"type":"stream_event","event":{"type":"content_block_delta"}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    // MARK: - Stream Event: message_delta

    func testParseMessageDelta() throws {
        let json = """
        {"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .done(let reason) = event {
            XCTAssertEqual(reason, "end_turn")
        } else {
            XCTFail("Expected .done, got \(String(describing: event))")
        }
    }

    func testParseMessageDeltaMissingStopReason() throws {
        let json = """
        {"type":"stream_event","event":{"type":"message_delta","delta":{}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    // MARK: - Stream Event: unknown event type

    func testParseStreamEventUnknownEventType() throws {
        let json = """
        {"type":"stream_event","event":{"type":"content_block_start","content_block":{"type":"text"}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    func testParseStreamEventMissingEventField() throws {
        let json = """
        {"type":"stream_event"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    // MARK: - Assistant Event

    func testParseAssistantToolUse() throws {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-abc","name":"read_file","input":{"path":"/tmp/test.txt"}}]}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .toolUse(let id, let name, let input) = event {
            XCTAssertEqual(id, "tool-abc")
            XCTAssertEqual(name, "read_file")
            // The input is JSON-serialized; verify it contains the key and value
            XCTAssertTrue(input.contains("path"), "Input should contain key 'path', got: \(input)")
            XCTAssertTrue(input.contains("test.txt"), "Input should contain 'test.txt', got: \(input)")
        } else {
            XCTFail("Expected .toolUse, got \(String(describing: event))")
        }
    }

    func testParseAssistantToolUseEmptyInput() throws {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-1","name":"list_files"}]}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .toolUse(let id, let name, let input) = event {
            XCTAssertEqual(id, "tool-1")
            XCTAssertEqual(name, "list_files")
            XCTAssertEqual(input, "{}")
        } else {
            XCTFail("Expected .toolUse with empty input")
        }
    }

    func testParseAssistantTextOnly() throws {
        // Assistant message with only text content -- no tool_use block
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Some response"}]}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        // Should return nil because text blocks in assistant messages are skipped
        XCTAssertNil(event)
    }

    func testParseAssistantMissingMessage() throws {
        let json = """
        {"type":"assistant"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    func testParseAssistantEmptyContent() throws {
        let json = """
        {"type":"assistant","message":{"content":[]}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    // MARK: - Result Event

    func testParseResultWithModelUsage() throws {
        let json = """
        {"type":"result","total_cost_usd":0.05,"modelUsage":{"claude-sonnet":{"inputTokens":1000,"outputTokens":500}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .usage(let inputTokens, let outputTokens, let costUSD) = event {
            XCTAssertEqual(inputTokens, 1000)
            XCTAssertEqual(outputTokens, 500)
            XCTAssertEqual(costUSD, 0.05)
        } else {
            XCTFail("Expected .usage, got \(String(describing: event))")
        }
    }

    func testParseResultWithoutModelUsage() throws {
        let json = """
        {"type":"result","total_cost_usd":0.02}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .usage(let inputTokens, let outputTokens, let costUSD) = event {
            XCTAssertEqual(inputTokens, 0)
            XCTAssertEqual(outputTokens, 0)
            XCTAssertEqual(costUSD, 0.02)
        } else {
            XCTFail("Expected .usage with zero tokens")
        }
    }

    func testParseResultNoCost() throws {
        let json = """
        {"type":"result","modelUsage":{"model-x":{"inputTokens":200,"outputTokens":100}}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .usage(let inputTokens, let outputTokens, let costUSD) = event {
            XCTAssertEqual(inputTokens, 200)
            XCTAssertEqual(outputTokens, 100)
            XCTAssertNil(costUSD)
        } else {
            XCTFail("Expected .usage")
        }
    }

    func testParseResultEmptyModelUsage() throws {
        let json = """
        {"type":"result","total_cost_usd":0.01,"modelUsage":{}}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .usage(let inputTokens, let outputTokens, let costUSD) = event {
            XCTAssertEqual(inputTokens, 0)
            XCTAssertEqual(outputTokens, 0)
            XCTAssertEqual(costUSD, 0.01)
        } else {
            XCTFail("Expected .usage with zero tokens")
        }
    }

    // MARK: - Unknown / Invalid

    func testParseUnknownType() throws {
        let json = """
        {"type":"heartbeat"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }

    func testParseInvalidJSON() throws {
        let event = ClaudeCodeProvider.parseStreamEvent("not json at all")
        XCTAssertNil(event)
    }

    func testParseEmptyString() throws {
        let event = ClaudeCodeProvider.parseStreamEvent("")
        XCTAssertNil(event)
    }

    func testParseMissingType() throws {
        let json = """
        {"data":"something"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        XCTAssertNil(event)
    }
}

// MARK: - ConversationState Tests

final class ConversationStateTests: XCTestCase {

    @MainActor
    func testInitialState() throws {
        let nodeID = UUID()
        let state = ConversationState(nodeID: nodeID)
        XCTAssertEqual(state.nodeID, nodeID)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.inputText, "")
        XCTAssertNil(state.error)
        XCTAssertNil(state.sessionID)
        XCTAssertEqual(state.totalCostUSD, 0)
        XCTAssertEqual(state.totalInputTokens, 0)
        XCTAssertEqual(state.totalOutputTokens, 0)
    }

    // MARK: - appendUserMessage

    @MainActor
    func testAppendUserMessage() throws {
        let state = ConversationState(nodeID: UUID())
        state.appendUserMessage("Hello")
        XCTAssertEqual(state.messages.count, 1)
        XCTAssertEqual(state.messages[0].role, .user)
        XCTAssertEqual(state.messages[0].textContent, "Hello")
    }

    @MainActor
    func testAppendMultipleUserMessages() throws {
        let state = ConversationState(nodeID: UUID())
        state.appendUserMessage("First")
        state.appendUserMessage("Second")
        XCTAssertEqual(state.messages.count, 2)
        XCTAssertEqual(state.messages[0].textContent, "First")
        XCTAssertEqual(state.messages[1].textContent, "Second")
    }

    @MainActor
    func testAppendUserMessageContent() throws {
        let state = ConversationState(nodeID: UUID())
        state.appendUserMessage("Test")
        XCTAssertEqual(state.messages[0].content.count, 1)
        if case .text(let t) = state.messages[0].content[0] {
            XCTAssertEqual(t, "Test")
        } else {
            XCTFail("Expected .text content")
        }
    }

    // MARK: - startStreaming

    @MainActor
    func testStartStreaming() throws {
        let state = ConversationState(nodeID: UUID())
        state.error = "old error"
        state.streamingText = "old text"

        state.startStreaming()
        XCTAssertTrue(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertNil(state.error)
    }

    // MARK: - appendStreamDelta

    @MainActor
    func testAppendStreamDelta() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.appendStreamDelta("Hello")
        XCTAssertEqual(state.streamingText, "Hello")

        state.appendStreamDelta(" World")
        XCTAssertEqual(state.streamingText, "Hello World")
    }

    @MainActor
    func testAppendStreamDeltaAccumulates() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.appendStreamDelta("A")
        state.appendStreamDelta("B")
        state.appendStreamDelta("C")
        XCTAssertEqual(state.streamingText, "ABC")
    }

    // MARK: - finishStreaming

    @MainActor
    func testFinishStreamingCreatesMessage() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.appendStreamDelta("Response text")
        state.finishStreaming()

        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.messages.count, 1)
        XCTAssertEqual(state.messages[0].role, .assistant)
        XCTAssertEqual(state.messages[0].textContent, "Response text")
    }

    @MainActor
    func testFinishStreamingEmptyTextNoMessage() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        // Don't append any deltas
        state.finishStreaming()

        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertTrue(state.messages.isEmpty) // No message created for empty streaming text
    }

    @MainActor
    func testFinishStreamingFullConversation() throws {
        let state = ConversationState(nodeID: UUID())

        state.appendUserMessage("Hello")
        state.startStreaming()
        state.appendStreamDelta("Hi there!")
        state.finishStreaming()

        XCTAssertEqual(state.messages.count, 2)
        XCTAssertEqual(state.messages[0].role, .user)
        XCTAssertEqual(state.messages[1].role, .assistant)
    }

    // MARK: - setError

    @MainActor
    func testSetError() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.appendStreamDelta("partial")

        state.setError("Network error")
        XCTAssertEqual(state.error, "Network error")
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
    }

    @MainActor
    func testSetErrorClearsStreamingState() throws {
        let state = ConversationState(nodeID: UUID())
        state.isStreaming = true
        state.streamingText = "some accumulated text"

        state.setError("Something went wrong")
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.error, "Something went wrong")
    }

    // MARK: - updateUsage

    @MainActor
    func testUpdateUsage() throws {
        let state = ConversationState(nodeID: UUID())
        state.updateUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01)
        XCTAssertEqual(state.totalInputTokens, 100)
        XCTAssertEqual(state.totalOutputTokens, 50)
        XCTAssertEqual(state.totalCostUSD, 0.01)
    }

    @MainActor
    func testUpdateUsageAccumulates() throws {
        let state = ConversationState(nodeID: UUID())
        state.updateUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01)
        state.updateUsage(inputTokens: 200, outputTokens: 75, costUSD: 0.02)
        XCTAssertEqual(state.totalInputTokens, 300)
        XCTAssertEqual(state.totalOutputTokens, 125)
        XCTAssertEqual(state.totalCostUSD, 0.03, accuracy: 0.0001)
    }

    @MainActor
    func testUpdateUsageNilCost() throws {
        let state = ConversationState(nodeID: UUID())
        state.updateUsage(inputTokens: 100, outputTokens: 50, costUSD: nil)
        XCTAssertEqual(state.totalInputTokens, 100)
        XCTAssertEqual(state.totalOutputTokens, 50)
        XCTAssertEqual(state.totalCostUSD, 0)
    }

    @MainActor
    func testUpdateUsageNilCostDoesNotResetExisting() throws {
        let state = ConversationState(nodeID: UUID())
        state.updateUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.05)
        state.updateUsage(inputTokens: 50, outputTokens: 25, costUSD: nil)
        XCTAssertEqual(state.totalCostUSD, 0.05) // unchanged
        XCTAssertEqual(state.totalInputTokens, 150)
        XCTAssertEqual(state.totalOutputTokens, 75)
    }
}

// MARK: - TerminalLine Tests

final class TerminalLineTests: XCTestCase {

    func testTerminalLinePrompt() throws {
        let line = TerminalLine(text: "$ ", type: .prompt)
        XCTAssertEqual(line.text, "$ ")
        if case .prompt = line.type {} else {
            XCTFail("Expected .prompt type")
        }
    }

    func testTerminalLineCommand() throws {
        let line = TerminalLine(text: "$ ls -la", type: .command)
        XCTAssertEqual(line.text, "$ ls -la")
        if case .command = line.type {} else {
            XCTFail("Expected .command type")
        }
    }

    func testTerminalLineOutput() throws {
        let line = TerminalLine(text: "file.txt", type: .output)
        XCTAssertEqual(line.text, "file.txt")
        if case .output = line.type {} else {
            XCTFail("Expected .output type")
        }
    }

    func testTerminalLineError() throws {
        let line = TerminalLine(text: "exit 1", type: .error)
        XCTAssertEqual(line.text, "exit 1")
        if case .error = line.type {} else {
            XCTFail("Expected .error type")
        }
    }

    func testTerminalLineHasUniqueID() throws {
        let line1 = TerminalLine(text: "a", type: .output)
        let line2 = TerminalLine(text: "a", type: .output)
        XCTAssertNotEqual(line1.id, line2.id)
    }

    func testTerminalLineHasTimestamp() throws {
        let before = Date()
        let line = TerminalLine(text: "test", type: .output)
        let after = Date()
        XCTAssertGreaterThanOrEqual(line.timestamp, before)
        XCTAssertLessThanOrEqual(line.timestamp, after)
    }
}

// MARK: - AIModel Tests

final class AIModelTests: XCTestCase {

    func testAIModelCreation() throws {
        let model = AIModel(id: "test-model", name: "Test Model")
        XCTAssertEqual(model.id, "test-model")
        XCTAssertEqual(model.name, "Test Model")
        XCTAssertEqual(model.contextWindow, 200_000)
        XCTAssertTrue(model.supportsTools)
        XCTAssertTrue(model.supportsVision)
    }

    func testAIModelCustomParams() throws {
        let model = AIModel(
            id: "custom",
            name: "Custom",
            contextWindow: 100_000,
            supportsTools: false,
            supportsVision: false
        )
        XCTAssertEqual(model.contextWindow, 100_000)
        XCTAssertFalse(model.supportsTools)
        XCTAssertFalse(model.supportsVision)
    }

    func testAIModelCodable() throws {
        let model = AIModel(id: "sonnet", name: "Sonnet", contextWindow: 200_000)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AIModel.self, from: data)
        XCTAssertEqual(decoded, model)
    }
}

// MARK: - StreamEvent Tests

final class StreamEventTests: XCTestCase {

    func testStreamEventInitialized() throws {
        let event = StreamEvent.initialized(sessionID: "s1", model: "m1")
        if case .initialized(let sid, let model) = event {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(model, "m1")
        } else {
            XCTFail("Expected .initialized")
        }
    }

    func testStreamEventTextDelta() throws {
        let event = StreamEvent.textDelta("chunk")
        if case .textDelta(let t) = event {
            XCTAssertEqual(t, "chunk")
        } else {
            XCTFail("Expected .textDelta")
        }
    }

    func testStreamEventText() throws {
        let event = StreamEvent.text("full text")
        if case .text(let t) = event {
            XCTAssertEqual(t, "full text")
        } else {
            XCTFail("Expected .text")
        }
    }

    func testStreamEventToolUse() throws {
        let event = StreamEvent.toolUse(id: "t1", name: "bash", input: "{}")
        if case .toolUse(let id, let name, let input) = event {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(name, "bash")
            XCTAssertEqual(input, "{}")
        } else {
            XCTFail("Expected .toolUse")
        }
    }

    func testStreamEventToolResult() throws {
        let event = StreamEvent.toolResult(id: "t1", content: "output", isError: false)
        if case .toolResult(let id, let content, let isError) = event {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(content, "output")
            XCTAssertFalse(isError)
        } else {
            XCTFail("Expected .toolResult")
        }
    }

    func testStreamEventUsage() throws {
        let event = StreamEvent.usage(inputTokens: 100, outputTokens: 50, costUSD: 0.01)
        if case .usage(let input, let output, let cost) = event {
            XCTAssertEqual(input, 100)
            XCTAssertEqual(output, 50)
            XCTAssertEqual(cost, 0.01)
        } else {
            XCTFail("Expected .usage")
        }
    }

    func testStreamEventDone() throws {
        let event = StreamEvent.done(stopReason: "end_turn")
        if case .done(let reason) = event {
            XCTAssertEqual(reason, "end_turn")
        } else {
            XCTFail("Expected .done")
        }
    }

    func testStreamEventError() throws {
        let event = StreamEvent.error("something broke")
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "something broke")
        } else {
            XCTFail("Expected .error")
        }
    }
}

// MARK: - ClaudeCodeProvider Properties Tests

final class ClaudeCodeProviderTests: XCTestCase {

    func testProviderID() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertEqual(provider.id, "claude")
    }

    func testProviderDisplayName() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertEqual(provider.displayName, "Claude (via Claude Code)")
    }

    func testAvailableModelsNotEmpty() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertFalse(provider.availableModels.isEmpty)
    }

    func testAvailableModelsContainsSonnet() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertTrue(provider.availableModels.contains { $0.id == "sonnet" })
    }

    func testAvailableModelsContainsOpus() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertTrue(provider.availableModels.contains { $0.id == "opus" })
    }

    func testAvailableModelsContainsHaiku() throws {
        let provider = ClaudeCodeProvider()
        XCTAssertTrue(provider.availableModels.contains { $0.id == "haiku" })
    }

    func testOpusHasLargerContextWindow() throws {
        let provider = ClaudeCodeProvider()
        let opus = provider.availableModels.first { $0.id == "opus" }
        let sonnet = provider.availableModels.first { $0.id == "sonnet" }
        XCTAssertNotNil(opus)
        XCTAssertNotNil(sonnet)
        XCTAssertGreaterThan(opus!.contextWindow, sonnet!.contextWindow)
    }
}
