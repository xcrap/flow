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

    func testParseSystemStatusCompacting() throws {
        let json = """
        {"type":"system","subtype":"status","status":"compacting"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .lifecycle(.phaseChanged(let phase)) = event {
            XCTAssertEqual(phase, .compacting)
        } else {
            XCTFail("Expected .lifecycle phaseChanged(.compacting), got \(String(describing: event))")
        }
    }

    func testParseSystemCompactBoundary() throws {
        let json = """
        {"type":"system","subtype":"compact_boundary","session_id":"sess-123"}
        """
        let event = ClaudeCodeProvider.parseStreamEvent(json)
        if case .lifecycle(.phaseChanged(let phase)) = event {
            XCTAssertEqual(phase, .compacted)
        } else {
            XCTFail("Expected .lifecycle phaseChanged(.compacted), got \(String(describing: event))")
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
        XCTAssertEqual(state.runtimePhase, .idle)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.inputText, "")
        XCTAssertNil(state.error)
        XCTAssertNil(state.sessionID)
        XCTAssertEqual(state.totalCostUSD, 0)
        XCTAssertEqual(state.totalInputTokens, 0)
        XCTAssertEqual(state.totalOutputTokens, 0)
        XCTAssertTrue(state.queuedPromptPreviews.isEmpty)
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
        XCTAssertEqual(state.runtimePhase, .preparing)
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
        XCTAssertEqual(state.runtimePhase, .responding)

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

    @MainActor
    func testAppendStreamDeltaAfterCompactionResumesResponding() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.applyLifecyclePhase(.compacting)
        XCTAssertEqual(state.runtimePhase, .compacting)

        state.appendStreamDelta("After compact")
        XCTAssertEqual(state.runtimePhase, .responding)
        XCTAssertEqual(state.streamingText, "After compact")
    }

    // MARK: - finishStreaming

    @MainActor
    func testFinishStreamingCreatesMessage() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.appendStreamDelta("Response text")
        state.finishStreaming()

        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.runtimePhase, .idle)
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
        XCTAssertEqual(state.runtimePhase, .idle)
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
        XCTAssertEqual(state.runtimePhase, .failed)
        XCTAssertEqual(state.streamingText, "")
    }

    @MainActor
    func testSetErrorClearsStreamingState() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()
        state.streamingText = "some accumulated text"

        state.setError("Something went wrong")
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.runtimePhase, .failed)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertEqual(state.error, "Something went wrong")
    }

    @MainActor
    func testApplyLifecyclePhaseCompacted() throws {
        let state = ConversationState(nodeID: UUID())
        state.startStreaming()

        state.applyLifecyclePhase(.compacted)

        XCTAssertTrue(state.isStreaming)
        XCTAssertEqual(state.runtimePhase, .compacted)
        XCTAssertEqual(state.statusLabel, "Compacted")
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

    @MainActor
    func testQueuedPromptPreviewLifecycle() throws {
        let state = ConversationState(nodeID: UUID())

        state.enqueuePrompt(" second prompt  ")
        state.enqueuePrompt("third\nprompt")

        XCTAssertEqual(state.queuedPromptCount, 2)
        XCTAssertEqual(state.nextQueuedPromptPreview, "second prompt")
        XCTAssertEqual(state.visibleQueuedPromptPreviews, ["second prompt", "third prompt"])

        let startedPrompt = state.beginQueuedPrompt()
        XCTAssertEqual(startedPrompt, "second prompt")
        XCTAssertEqual(state.queuedPromptCount, 1)
        XCTAssertEqual(state.visibleQueuedPromptPreviews, ["third prompt"])

        state.clearQueuedPrompts()
        XCTAssertEqual(state.queuedPromptCount, 0)
        XCTAssertTrue(state.queuedPromptPreviews.isEmpty)
    }

    @MainActor
    func testRecordRuntimeActivityCoalescesDuplicates() throws {
        let state = ConversationState(nodeID: UUID())

        state.recordRuntimeActivity(
            kind: .contextCompaction,
            tone: .working,
            summary: "Context compacting",
            detail: "14K of 200K",
            state: "compacting"
        )
        state.recordRuntimeActivity(
            kind: .contextCompaction,
            tone: .working,
            summary: "Context compacting",
            detail: "14K of 200K",
            state: "compacting"
        )

        XCTAssertEqual(state.runtimeActivities.count, 1)
        XCTAssertEqual(state.latestRuntimeActivity?.summary, "Context compacting")
    }
}

private final class MockProvider: AIProvider, @unchecked Sendable {
    let id = "mock"
    let displayName = "Mock"
    let availableModels = [AIModel(id: "mock-model", name: "Mock Model")]

    private(set) var prompts: [String] = []
    private(set) var cancelCount = 0
    private var continuations: [AsyncThrowingStream<StreamEvent, Error>.Continuation] = []

    func sendMessage(
        prompt: String,
        attachments: [Attachment],
        messages: [ConversationMessage],
        model: String,
        effort: String?,
        systemPrompt: String?,
        permissionMode: String?,
        workingDirectory: URL?,
        resumeSessionID: String?
    ) -> ProviderStreamHandle {
        prompts.append(prompt)

        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuations.append(continuation)
        }

        return ProviderStreamHandle(stream: stream) { [weak self] in
            self?.cancelCount += 1
        }
    }

    func yield(_ event: StreamEvent, at index: Int) {
        continuations[index].yield(event)
    }

    func finish(at index: Int) {
        continuations[index].finish()
    }
}

private func waitForCondition(
    timeoutMS: Int = 1_000,
    pollMS: Int = 10,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let iterations = max(1, timeoutMS / pollMS)
    for _ in 0..<iterations {
        if await MainActor.run(body: condition) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(pollMS))
    }
    return await MainActor.run(body: condition)
}

final class ConversationServiceTests: XCTestCase {

    @MainActor
    func testSendQueuesPromptWhileStreaming() async throws {
        let provider = MockProvider()
        let registry = ProviderRegistry()
        registry.register(provider)

        let service = ConversationService(registry: registry)
        let state = ConversationState(nodeID: UUID())

        var completionCount = 0

        service.send(
            prompt: "first",
            to: state,
            providerID: provider.id,
            model: "mock-model",
            onComplete: { completionCount += 1 }
        )

        XCTAssertEqual(provider.prompts, ["first"])
        XCTAssertTrue(state.isStreaming)
        XCTAssertEqual(state.runtimePhase, .preparing)

        service.send(
            prompt: "second",
            to: state,
            providerID: provider.id,
            model: "mock-model",
            onComplete: { completionCount += 1 }
        )

        XCTAssertEqual(provider.prompts, ["first"])
        XCTAssertEqual(state.queuedPromptCount, 1)
        XCTAssertEqual(state.queuedPromptPreviews, ["second"])
        XCTAssertEqual(state.messages.map(\.textContent), ["first"])

        provider.yield(.initialized(sessionID: "session-1", model: "mock-model"), at: 0)
        provider.yield(.lifecycle(.turnStarted(turnID: "turn-1")), at: 0)
        provider.yield(.textDelta("reply"), at: 0)
        provider.finish(at: 0)

        let didStartQueuedRequest = await waitForCondition {
            provider.prompts.count == 2 &&
            state.queuedPromptCount == 0 &&
            state.messages.map(\.textContent) == ["first", "reply", "second"]
        }
        XCTAssertTrue(didStartQueuedRequest)

        XCTAssertEqual(provider.prompts, ["first", "second"])
        XCTAssertEqual(state.queuedPromptCount, 0)
        XCTAssertTrue(state.queuedPromptPreviews.isEmpty)
        XCTAssertEqual(state.messages.map(\.textContent), ["first", "reply", "second"])

        provider.yield(.initialized(sessionID: "session-1", model: "mock-model"), at: 1)
        provider.yield(.lifecycle(.turnStarted(turnID: "turn-2")), at: 1)
        provider.yield(.textDelta("second reply"), at: 1)
        provider.finish(at: 1)

        let didDrainQueue = await waitForCondition {
            completionCount == 2 &&
            !state.isStreaming &&
            state.messages.map(\.textContent) == ["first", "reply", "second", "second reply"]
        }
        XCTAssertTrue(didDrainQueue)

        XCTAssertEqual(completionCount, 2)
        XCTAssertFalse(state.isStreaming)
        XCTAssertEqual(state.runtimePhase, .idle)
    }

    @MainActor
    func testCancelStreamingCallsProviderCancellation() async throws {
        let provider = MockProvider()
        let registry = ProviderRegistry()
        registry.register(provider)

        let service = ConversationService(registry: registry)
        let state = ConversationState(nodeID: UUID())

        service.send(
            prompt: "cancel me",
            to: state,
            providerID: provider.id,
            model: "mock-model"
        )

        service.cancelStreaming(for: state.nodeID)
        let didCancel = await waitForCondition {
            provider.cancelCount == 1 &&
            state.runtimePhase == .idle &&
            state.lastStopReason == "cancelled"
        }
        XCTAssertTrue(didCancel)

        XCTAssertEqual(provider.cancelCount, 1)
        XCTAssertEqual(state.runtimePhase, .idle)
        XCTAssertEqual(state.lastStopReason, "cancelled")
    }

    @MainActor
    func testUsageEventSeedsContextPercentageFromModelMetadata() async throws {
        let provider = MockProvider()
        let registry = ProviderRegistry()
        registry.register(provider)

        let service = ConversationService(registry: registry)
        let state = ConversationState(nodeID: UUID())

        service.send(
            prompt: "hello",
            to: state,
            providerID: provider.id,
            model: "mock-model"
        )

        provider.yield(.initialized(sessionID: "session-1", model: "mock-model"), at: 0)
        provider.yield(.usage(inputTokens: 120, outputTokens: 30, costUSD: 1.23), at: 0)
        provider.finish(at: 0)

        let didCaptureUsage = await waitForCondition {
            state.reportedContextWindow == 200_000 &&
            state.currentContextTokens == 150 &&
            state.totalTokens == 150
        }
        XCTAssertTrue(didCaptureUsage)
        XCTAssertEqual(state.reportedContextWindow, 200_000)
        XCTAssertEqual(state.currentContextTokens, 150)
        XCTAssertEqual(state.totalTokens, 150)
    }

    @MainActor
    func testLifecycleCompactionPhaseUpdatesConversationState() async throws {
        let provider = MockProvider()
        let registry = ProviderRegistry()
        registry.register(provider)

        let service = ConversationService(registry: registry)
        let state = ConversationState(nodeID: UUID())

        service.send(
            prompt: "compact me",
            to: state,
            providerID: provider.id,
            model: "mock-model"
        )

        provider.yield(.lifecycle(.phaseChanged(.compacting)), at: 0)
        let didEnterCompacting = await waitForCondition {
            state.runtimePhase == .compacting
        }
        XCTAssertTrue(didEnterCompacting)

        provider.yield(.lifecycle(.phaseChanged(.compacted)), at: 0)
        let didEnterCompacted = await waitForCondition {
            state.runtimePhase == .compacted
        }
        XCTAssertTrue(didEnterCompacted)

        provider.finish(at: 0)
    }

    @MainActor
    func testToolEventsAppendRuntimeActivities() async throws {
        let provider = MockProvider()
        let registry = ProviderRegistry()
        registry.register(provider)

        let service = ConversationService(registry: registry)
        let state = ConversationState(nodeID: UUID())

        service.send(
            prompt: "run a tool",
            to: state,
            providerID: provider.id,
            model: "mock-model"
        )

        provider.yield(.initialized(sessionID: "session-1", model: "mock-model"), at: 0)
        provider.yield(.lifecycle(.turnStarted(turnID: "turn-1")), at: 0)
        provider.yield(.toolUse(id: "tool-1", name: "Read", input: "{\"path\":\"README.md\"}"), at: 0)
        provider.yield(.toolResult(id: "tool-1", content: "Done", isError: false), at: 0)
        provider.finish(at: 0)

        let didRecordActivities = await waitForCondition {
            state.runtimeActivities.contains(where: { $0.kind == .tool && $0.state == "started" && $0.summary == "Read" }) &&
            state.runtimeActivities.contains(where: { $0.kind == .tool && $0.state == "completed" && $0.summary == "Tool completed" })
        }
        XCTAssertTrue(didRecordActivities)
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

    func testStreamEventLifecycle() throws {
        let event = StreamEvent.lifecycle(.turnStarted(turnID: "turn-123"))
        if case .lifecycle(.turnStarted(let turnID)) = event {
            XCTAssertEqual(turnID, "turn-123")
        } else {
            XCTFail("Expected .lifecycle turnStarted")
        }
    }

    func testStreamEventLifecyclePhaseChanged() throws {
        let event = StreamEvent.lifecycle(.phaseChanged(.compacting))
        if case .lifecycle(.phaseChanged(let phase)) = event {
            XCTAssertEqual(phase, .compacting)
        } else {
            XCTFail("Expected .lifecycle phaseChanged")
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

    func testClaudeModelsUseSharedEffectiveContextWindow() throws {
        let provider = ClaudeCodeProvider()
        let opus = provider.availableModels.first { $0.id == "opus" }
        let sonnet = provider.availableModels.first { $0.id == "sonnet" }
        XCTAssertNotNil(opus)
        XCTAssertNotNil(sonnet)
        XCTAssertEqual(opus?.contextWindow, 200_000)
        XCTAssertEqual(sonnet?.contextWindow, 200_000)
    }
}
