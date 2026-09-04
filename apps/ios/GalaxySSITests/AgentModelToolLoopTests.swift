import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelToolLoopTests: XCTestCase {
  func testAgentModelToolLoopCompletesIterativeToolCallWithManifestAndEvents() async throws {
    var capturedContexts: [AgentNativeToolInvocationContext] = []
    let registry = try registry(idempotency: .idempotent) { invocation in
      capturedContexts.append(invocation.context)
      return .success(output: ["echo": invocation.input["value"] ?? .null], message: "Echoed")
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(
        toolCalls: [call("call-1", arguments: ["value": .string("hello")])],
        usage: AgentModelUsage(inputTokens: 4, outputTokens: 2)
      ),
      AgentModelResponse(assistantText: "The phone echoed hello.", usage: AgentModelUsage(inputTokens: 3, outputTokens: 5))
    )
    var streamedEvents: [AgentModelToolLoopEvent] = []
    let loop = loop(adapter: adapter, registry: registry)

    let outcome = await loop.run(request(eventSink: AgentModelToolLoopEventSink { streamedEvents.append($0) }))

    XCTAssertEqual(outcome.status, .completed)
    XCTAssertEqual(outcome.assistantText, "The phone echoed hello.")
    XCTAssertEqual(outcome.usage.rounds, 2)
    XCTAssertEqual(outcome.usage.toolCallAttempts, 1)
    XCTAssertEqual(outcome.usage.totalTokens, 14)
    XCTAssertEqual(outcome.toolManifestSha256.count, 64)
    XCTAssertEqual(outcome.events, streamedEvents)
    XCTAssertEqual(outcome.events.map(\.sequence), (1...Int64(outcome.events.count)).map { $0 })
    XCTAssertTrue(outcome.events.allSatisfy { $0.sessionId == "session-1" && $0.turnId == "turn-1" })
    XCTAssertTrue(outcome.events.allSatisfy { $0.toolManifestSha256 == outcome.toolManifestSha256 })
    XCTAssertEqual(outcome.toolManifestSha256, adapter.singleManifestHash())

    let context = try capturedContexts.singleValue()
    XCTAssertEqual(context.sessionId, "session-1")
    XCTAssertEqual(context.conversationId, "conversation-1")
    XCTAssertEqual(context.turnId, "turn-1")
    XCTAssertEqual(context.attributes["task_id"], "task-1")
    XCTAssertEqual(context.attributes["workspace_id"], "workspace-1")
    XCTAssertEqual(context.attributes["tool_call_id"], "call-1")
    XCTAssertEqual(context.attributes["tool_manifest_sha256"], outcome.toolManifestSha256)
    XCTAssertNotNil(context.idempotencyKey)
    let toolResult = try outcome.messages.filter { $0.role == .tool }.singleValue().toolResult
    XCTAssertEqual(toolResult?.output["echo"], .string("hello"))
    XCTAssertEqual(toolResult?.nativeResult?.provenance.toolId, Self.toolId)
  }

  func testAgentModelToolLoopPausesForConsentAndResumesWithSingleUseApproval() async throws {
    var executions = 0
    var invocationContext: AgentNativeToolInvocationContext?
    let clock = MutableClock(now: 1_000)
    let registry = try registry(
      consents: [AgentNativeConsentRequirement(id: "contacts.lookup", title: "Look up contacts")]
    ) { invocation in
      executions += 1
      invocationContext = invocation.context
      return .success(output: ["echo": .string("Alice")])
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("consent-call")]),
      AgentModelResponse(assistantText: "Alice was found on the phone.")
    )
    let loop = loop(adapter: adapter, registry: registry, clock: clock)

    let paused = await loop.run(request())

    XCTAssertEqual(paused.status, .waitingForApproval)
    XCTAssertFalse(paused.isTerminal)
    XCTAssertEqual(executions, 0)
    let handle = try XCTUnwrap(paused.approval)
    XCTAssertEqual(handle.sessionId, "session-1")
    XCTAssertEqual(handle.turnId, "turn-1")
    XCTAssertEqual(handle.toolCallId, "consent-call")
    XCTAssertEqual(handle.requiredConsentIds, ["contacts.lookup"])
    XCTAssertEqual(handle.toolManifestSha256, paused.toolManifestSha256)

    let completed = try await loop.resume(handle, decision: .approved)

    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(executions, 1)
    XCTAssertTrue(try XCTUnwrap(invocationContext).grantedConsents.contains("contacts.lookup"))
    XCTAssertEqual(invocationContext?.attributes["confirmation_id"], handle.confirmationId)
    XCTAssertTrue(completed.events.contains { $0.type == .approvalDecided })
    XCTAssertTrue(completed.events.contains { $0.type == .loopResumed })
    do {
      _ = try await loop.resume(handle, decision: .approved)
      XCTFail("Expected approval handle to be single-use.")
    } catch {
      XCTAssertTrue(true)
    }
  }

  func testAgentModelToolLoopStopsBeforeExecutionWhenTokenBudgetIsExceeded() async throws {
    var executions = 0
    let registry = try registry { _ in
      executions += 1
      return .success()
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(
        assistantText: "I will call the tool.",
        toolCalls: [call("over-budget")],
        usage: AgentModelUsage(inputTokens: 6, outputTokens: 5)
      )
    )
    let loop = loop(adapter: adapter, registry: registry)

    let outcome = await loop.run(request(budget: AgentModelToolLoopBudget(maxTokens: 10)))

    XCTAssertEqual(outcome.status, .budgetExceeded)
    XCTAssertEqual(outcome.error?.code, "max_tokens")
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(outcome.usage.totalTokens, 11)
    XCTAssertEqual(outcome.events.last?.type, .budgetExceeded)
  }

  func testAgentModelToolLoopReturnsInvalidCallToModelWithoutInvokingUnknownTool() async throws {
    let registry = try AgentNativeToolRegistry()
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [
        AgentModelToolCall(callId: "invalid-call", toolId: "phone.unknown.tool")
      ]),
      AgentModelResponse(assistantText: "That phone tool is unavailable.")
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .completed)
    let result = try outcome.messages.filter { $0.role == .tool }.singleValue().toolResult
    XCTAssertEqual(result?.error?.code, "unknown_tool")
    XCTAssertEqual(adapter.requests[1].messages.last?.toolResult?.error?.code, "unknown_tool")
    XCTAssertTrue(outcome.events.contains { $0.type == .toolCallRejected })
  }

  func testAgentModelToolLoopDetectsRepeatedCallSignatureBeforeSecondExecution() async throws {
    var executions = 0
    let registry = try registry { _ in
      executions += 1
      return .success(output: ["echo": .string("same")])
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("repeat-1", arguments: ["value": .string("same")])]),
      AgentModelResponse(toolCalls: [call("repeat-2", arguments: ["value": .string("same")])])
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .loopDetected)
    XCTAssertEqual(outcome.error?.code, "repeated_tool_call")
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(outcome.events.last?.type, .loopDetected)
  }

  func testAgentModelToolLoopRetriesOnlyRetryableIdempotentToolFailures() async throws {
    var executions = 0
    let registry = try registry(idempotency: .idempotent) { _ in
      executions += 1
      if executions == 1 {
        return .failure(code: "temporary", message: "Try again", retryable: true)
      }
      return .success(output: ["echo": .string("recovered")])
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("retry-call")]),
      AgentModelResponse(assistantText: "Recovered after a safe retry.")
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .completed)
    XCTAssertEqual(executions, 2)
    XCTAssertEqual(outcome.usage.retries, 1)
    XCTAssertEqual(outcome.usage.toolCallAttempts, 2)
    let result = try outcome.messages.filter { $0.role == .tool }.singleValue().toolResult
    XCTAssertEqual(result?.retryCount, 1)
    XCTAssertTrue(outcome.events.contains { $0.type == .toolRetryScheduled })
  }

  func testAgentModelToolLoopPropagatesCancellationIntoActiveNativeTool() async throws {
    let cancellation = AgentModelToolLoopCancellationSource()
    var executions = 0
    let registry = try registry { invocation in
      executions += 1
      cancellation.cancel()
      try invocation.checkpoint()
      return .success()
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("cancel-call")]),
      AgentModelResponse(assistantText: "This response must not be requested.")
    )

    let outcome = await loop(adapter: adapter, registry: registry)
      .run(request(cancellationToken: cancellation.token))

    XCTAssertEqual(outcome.status, .cancelled)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(adapter.requests.count, 1)
    XCTAssertEqual(outcome.messages.last?.toolResult?.status, AgentNativeToolResultStatus.cancelled.rawValue)
    XCTAssertEqual(outcome.events.last?.type, .loopCancelled)
  }

  func testAgentModelToolLoopBindsWorkspaceToolCallsToCurrentWorkspace() async throws {
    var receivedWorkspace = ""
    let toolId = "galaxyssi.workspace.file.read.text"
    let registry = try AgentNativeToolRegistry().registerExecutable(
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: try descriptor(
            id: toolId,
            inputSchema: [
              "type": .string("object"),
              "properties": .object([
                "workspace_id": .object(["type": .string("string")]),
                "path": .object(["type": .string("string")])
              ]),
              "required": .array([.string("workspace_id"), .string("path")]),
              "additionalProperties": .bool(false)
            ]
          ),
          executorId: "test.workspace_scope"
        ),
        executor: { invocation in
          receivedWorkspace = invocation.input["workspace_id"]?.strictStringValue ?? ""
          return .success(output: ["text": .string("ok")])
        }
      )
    )
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [
        AgentModelToolCall(
          callId: "workspace-call",
          toolId: toolId,
          arguments: ["workspace_id": .string("foreign-workspace"), "path": .string("notes.txt")],
          toolVersion: "1.0.0"
        )
      ]),
      AgentModelResponse(assistantText: "Read the project file.")
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .completed)
    let toolResult = try outcome.messages.filter { $0.role == .tool }.singleValue().toolResult
    XCTAssertEqual(toolResult?.status, AgentNativeToolResultStatus.succeeded.rawValue)
    XCTAssertEqual(receivedWorkspace, "workspace-1")
    XCTAssertEqual(toolResult?.output["text"], .string("ok"))
  }

  func testAgentModelToolLoopRunsDisjointWorkspaceReadsConcurrentlyInOrder() async throws {
    let toolIds = ["galaxyssi.workspace.file.read.one", "galaxyssi.workspace.file.read.two"]
    let lock = NSLock()
    var active = 0
    var maximumActive = 0
    let executables = try toolIds.map { toolId in
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: try descriptor(
            id: toolId,
            inputSchema: [
              "type": .string("object"),
              "properties": .object([
                "workspace_id": .object(["type": .string("string")]),
                "path": .object(["type": .string("string")])
              ]),
              "required": .array([.string("workspace_id"), .string("path")]),
              "additionalProperties": .bool(false)
            ],
            idempotency: .idempotent,
            concurrency: .parallelReadOnly,
            capabilities: ["workspace.file.read"]
          ),
          executorId: "test.parallel_workspace_read"
        ),
        executor: { invocation in
          lock.lock()
          active += 1
          maximumActive = max(maximumActive, active)
          lock.unlock()
          Thread.sleep(forTimeInterval: 0.05)
          lock.lock()
          active -= 1
          lock.unlock()
          return .success(output: ["path": invocation.input["path"] ?? .null])
        }
      )
    }
    let registry = try AgentNativeToolRegistry().registerExecutables(executables)
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [
        AgentModelToolCall(
          callId: "read-one",
          toolId: toolIds[0],
          arguments: ["workspace_id": .string("other"), "path": .string("Sources/One.swift")]
        ),
        AgentModelToolCall(
          callId: "read-two",
          toolId: toolIds[1],
          arguments: ["workspace_id": .string("other"), "path": .string("Sources/Two.swift")]
        )
      ]),
      AgentModelResponse(assistantText: "Both project files were read.")
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .completed)
    XCTAssertEqual(maximumActive, 2)
    XCTAssertEqual(
      outcome.messages.compactMap(\.toolResult?.callId),
      ["read-one", "read-two"]
    )
  }

  func testAgentModelToolLoopModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentModelToolLoopBudget.self,
      from: Data(
        #"""
        {
          "max_rounds": 3,
          "max_tool_calls": 4,
          "max_depth": 2,
          "max_tokens": 100,
          "max_duration_millis": 2000,
          "max_retries_per_call": 1,
          "max_repeated_call_signatures": 1,
          "approval_ttl_millis": 500
        }
        """#.utf8
      )
    )
    let event = AgentModelToolLoopEvent(
      sequence: 1,
      type: .toolStarted,
      occurredAtEpochMillis: 123,
      sessionId: "session",
      turnId: "turn",
      taskId: "task",
      toolManifestSha256: "hash",
      round: 1,
      toolCallId: "call",
      invocationId: "invoke",
      details: ["tool_version": .string("1.0.0")]
    )
    let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
    let callJSON = String(decoding: try JSONEncoder().encode(
      AgentModelToolCall(
        callId: "call",
        toolId: Self.toolId,
        toolVersion: "1.0.0",
        idempotencyKey: "idem",
        depth: 2
      )
    ), as: UTF8.self)

    XCTAssertEqual(decoded.maxRounds, 3)
    XCTAssertEqual(decoded.maxToolCalls, 4)
    XCTAssertTrue(encoded.contains(#""tool_manifest_sha256":"hash""#))
    XCTAssertTrue(encoded.contains(#""invocation_id":"invoke""#))
    XCTAssertTrue(callJSON.contains(#""idempotency_key":"idem""#))
    XCTAssertTrue(callJSON.contains(#""depth":2"#))
  }

  private func loop(
    adapter: AgentModelAdapter,
    registry: AgentNativeToolRegistry,
    clock: MutableClock = MutableClock(now: 100)
  ) -> AgentModelToolLoop {
    AgentModelToolLoop(
      modelAdapter: adapter,
      toolRegistry: registry,
      clock: AgentModelToolLoopClock { clock.now },
      idFactory: countingIds()
    )
  }

  private func request(
    budget: AgentModelToolLoopBudget = AgentModelToolLoopBudget(),
    cancellationToken: AgentModelToolLoopCancellationToken = .none,
    eventSink: AgentModelToolLoopEventSink = .none
  ) -> AgentModelToolLoopRequest {
    .forUserMessage(
      sessionId: "session-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      workspaceId: "workspace-1",
      userMessage: "Use the phone tool.",
      budget: budget,
      cancellationToken: cancellationToken,
      eventSink: eventSink
    )
  }

  private func call(
    _ id: String,
    arguments: AgentMcpJSONObject = ["value": .string("Alice")]
  ) -> AgentModelToolCall {
    AgentModelToolCall(
      callId: id,
      toolId: Self.toolId,
      arguments: arguments,
      toolVersion: "1.0.0"
    )
  }

  private func registry(
    idempotency: AgentNativeToolIdempotency = .nonIdempotent,
    consents: [AgentNativeConsentRequirement] = [],
    executor: @escaping (AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult
  ) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutable(
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: try descriptor(
            id: Self.toolId,
            inputSchema: [
              "type": .string("object"),
              "properties": .object(["value": .object(["type": .string("string")])]),
              "required": .array([.string("value")]),
              "additionalProperties": .bool(false)
            ],
            idempotency: idempotency,
            consents: consents
          ),
          executorId: "test.model_tool_loop"
        ),
        executor: executor
      )
    )
  }

  private func descriptor(
    id: String,
    inputSchema: AgentMcpJSONObject,
    idempotency: AgentNativeToolIdempotency = .nonIdempotent,
    consents: [AgentNativeConsentRequirement] = [],
    concurrency: AgentNativeToolConcurrency = .serial,
    capabilities: Set<String> = []
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: "Echo value",
      description: "Returns a value for model tool loop tests.",
      location: .phone,
      inputSchema: inputSchema,
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: .low,
      capabilities: capabilities,
      requiredConsents: consents,
      idempotency: idempotency,
      concurrency: concurrency
    )
  }

  private func countingIds() -> AgentModelToolLoopIdFactory {
    var next = 0
    return AgentModelToolLoopIdFactory { purpose in
      next += 1
      return "\(purpose)-\(next)"
    }
  }

  private static let toolId = "phone.test.echo"
}

private final class ScriptedModelAdapter: AgentModelAdapter {
  private var remaining: [AgentModelResponse]
  private(set) var requests: [AgentModelRequest] = []

  init(_ responses: AgentModelResponse...) {
    self.remaining = responses
  }

  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
    requests.append(request)
    return remaining.removeFirst()
  }

  func singleManifestHash(file: StaticString = #filePath, line: UInt = #line) -> String {
    let hashes = Set(requests.map(\.toolManifestSha256))
    let manifestJson = requests.first?.toolManifestJson ?? ""
    XCTAssertEqual(hashes.count, 1, file: file, line: line)
    XCTAssertTrue(requests.allSatisfy { $0.toolManifestJson == manifestJson }, file: file, line: line)
    return hashes.first ?? ""
  }
}

private final class MutableClock {
  var now: Int64

  init(now: Int64) {
    self.now = now
  }
}

private enum AgentModelToolLoopTestError: Error {
  case missingSingleValue
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) throws -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    guard count == 1 else {
      throw AgentModelToolLoopTestError.missingSingleValue
    }
    return self[0]
  }
}
