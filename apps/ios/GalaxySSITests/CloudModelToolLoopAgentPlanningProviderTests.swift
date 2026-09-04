import Foundation
import XCTest
@testable import GalaxySSI

final class CloudModelToolLoopAgentPlanningProviderTests: XCTestCase {
  func testToolLoopPlanningProviderFallsBackWhenNoSafeNativeToolsAreAvailable() async throws {
    let fallback = RecordingPlanningProvider(raw: #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    let provider = try CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: fallback,
      toolRegistry: AgentNativeToolRegistry(),
      requestIdFactory: { "turn-1" },
      memoryTelemetryCapture: { _ in XCTFail("Fallback planning should not emit tool-loop memory telemetry.") }
    ) { _, _ in
      XCTFail("No tool loop should be created without safe native tools.")
      return RecordingPlanningToolLoopRunner(.completedPlan())
    }

    let raw = try await provider.rawPlan(invocation: invocation(nativeTools: []))

    XCTAssertEqual(raw, #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    XCTAssertEqual(fallback.invocations.count, 1)
  }

  func testToolLoopPlanningProviderRunsSafeNativeToolsWithAndroidPlannerBudget() async throws {
    let descriptor = try nativeToolDescriptor(
      id: Self.echoToolId,
      permissions: [AgentNativePermissionRequirement(id: "galaxyssi.scope.test")]
    )
    let registry = try executableRegistry(descriptor: descriptor)
    let runner = RecordingPlanningToolLoopRunner(.completedPlan(#"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#))
    let fallback = RecordingPlanningProvider(raw: "fallback")
    var capturedCatalog: [AgentNativeToolDescriptor] = []
    var capturedRegistry: AgentNativeToolRegistry?
    var telemetry: [AgentWorkspace?] = []
    let provider = CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: fallback,
      toolRegistry: registry,
      requestIdFactory: { "turn-1" },
      memoryTelemetryCapture: { telemetry.append($0) }
    ) { catalog, registry in
      capturedCatalog = catalog
      capturedRegistry = registry
      return runner
    }

    let raw = try await provider.rawPlan(invocation: invocation(
      nativeTools: [descriptor],
      conversationId: "conversation-1",
      systemPrompt: "system",
      prompt: "planner prompt"
    ))

    let request = try runner.requests.singleValue()
    XCTAssertEqual(raw, #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    XCTAssertTrue(fallback.invocations.isEmpty)
    XCTAssertEqual(capturedCatalog.map(\.id), [Self.echoToolId])
    XCTAssertNotNil(capturedRegistry?.executable(Self.echoToolId))
    XCTAssertEqual(request.sessionId, "conversation-1")
    XCTAssertEqual(request.conversationId, "conversation-1")
    XCTAssertEqual(request.turnId, "turn-1")
    XCTAssertEqual(request.taskId, "turn-1")
    XCTAssertEqual(request.workspaceId, "turn-1")
    XCTAssertEqual(request.callerId, "galaxyssi.ios_model_planner_tool_loop")
    XCTAssertEqual(request.messages.map(\.role), [.system, .user])
    XCTAssertEqual(request.messages[0].text, "system")
    XCTAssertEqual(request.messages[1].text, "planner prompt")
    XCTAssertEqual(request.budget.maxRounds, 4)
    XCTAssertEqual(request.budget.maxToolCalls, 8)
    XCTAssertEqual(request.budget.maxDepth, 2)
    XCTAssertEqual(request.budget.maxTokens, 12_000)
    XCTAssertEqual(request.budget.maxDurationMillis, 45_000)
    XCTAssertEqual(request.grantedPermissions, ["galaxyssi.scope.test"])
    XCTAssertEqual(telemetry.count, 2)
    let workspace = try XCTUnwrap(telemetry[0])
    XCTAssertNil(telemetry[1])
    XCTAssertEqual(workspace.workspaceId, "turn-1")
    XCTAssertEqual(workspace.sessionId, "conversation-1")
    XCTAssertEqual(workspace.conversationId, "conversation-1")
    XCTAssertEqual(workspace.taskId, "turn-1")
    XCTAssertEqual(workspace.agentId, "galaxyssi.ios_model_planner_tool_loop")
    XCTAssertEqual(workspace.status, .running)
  }

  func testToolLoopPlanningProviderRejectsRuntimeToolsUnlessRequestAllowsThem() async throws {
    let runtime = try nativeToolDescriptor(id: AgentIOSOnDeviceRuntimeNativeToolCatalog.status)
    let registry = try executableRegistry(descriptor: runtime)
    let runner = RecordingPlanningToolLoopRunner(.completedPlan())
    let fallback = RecordingPlanningProvider(raw: "fallback")
    let provider = CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: fallback,
      toolRegistry: registry,
      requestIdFactory: { "turn-1" }
    ) { _, _ in runner }

    let fallbackRaw = try await provider.rawPlan(invocation: invocation(
      nativeTools: [runtime],
      allowsPhoneRuntimeTools: false
    ))
    let toolLoopRaw = try await provider.rawPlan(invocation: invocation(
      nativeTools: [runtime],
      allowsPhoneRuntimeTools: true
    ))

    XCTAssertEqual(fallbackRaw, "fallback")
    XCTAssertEqual(toolLoopRaw, #"{"actions":[]}"#)
    XCTAssertEqual(fallback.invocations.count, 1)
    XCTAssertEqual(runner.requests.count, 1)
  }

  func testToolLoopPlanningProviderThrowsWhenToolLoopDoesNotComplete() async throws {
    let descriptor = try nativeToolDescriptor(id: Self.echoToolId)
    let registry = try executableRegistry(descriptor: descriptor)
    let runner = RecordingPlanningToolLoopRunner(AgentModelToolLoopOutcome(
      status: .budgetExceeded,
      assistantText: "",
      messages: [],
      events: [],
      usage: AgentModelToolLoopUsage(
        rounds: 4,
        toolCallAttempts: 8,
        retries: 0,
        inputTokens: 1,
        outputTokens: 2,
        durationMillis: 45_000
      ),
      toolManifestJson: "{}",
      toolManifestSha256: "hash",
      approval: nil,
      error: AgentModelToolLoopError(code: "max_tool_calls", message: "Tool budget exhausted")
    ))
    let provider = CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: RecordingPlanningProvider(raw: "fallback"),
      toolRegistry: registry,
      requestIdFactory: { "turn-1" }
    ) { _, _ in runner }

    do {
      _ = try await provider.rawPlan(invocation: invocation(nativeTools: [descriptor]))
      XCTFail("Expected incomplete tool loop outcome to throw.")
    } catch let error as AgentModelPlanningProviderError {
      XCTAssertEqual(error, .unavailable("Tool budget exhausted"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAgentNativeToolRegistrySubsetPreservesExecutableDefinitions() throws {
    let descriptor = try nativeToolDescriptor(id: Self.echoToolId)
    let registry = try executableRegistry(descriptor: descriptor)

    let subset = try registry.subset { $0.id == Self.echoToolId }
    let result = subset.invoke(
      Self.echoToolId,
      input: ["value": .string("hello")],
      context: AgentNativeToolInvocationContext(grantedPermissions: ["galaxyssi.scope.test"])
    )

    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.output["echo"], .string("hello"))
    XCTAssertNotNil(subset.executable(Self.echoToolId))
  }

  private func invocation(
    nativeTools: [AgentNativeToolDescriptor],
    allowsPhoneRuntimeTools: Bool = false,
    conversationId: String = "",
    systemPrompt: String = "system",
    prompt: String = "prompt"
  ) -> AgentModelPlanningInvocation {
    AgentModelPlanningInvocation(
      systemPrompt: systemPrompt,
      prompt: prompt,
      nativeTools: nativeTools,
      request: AgentModelPlanningPromptRequest(
        planRequest: AgentPlanRequest(
          goal: "Plan this task",
          screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
          targets: [],
          nativeTools: nativeTools,
          contextDigest: "tool-loop-planning-provider-test"
        ),
        conversationContext: AgentConversationContext(
          conversationId: conversationId,
          summary: "",
          turns: [],
          privateMode: false
        ),
        allowsPhoneRuntimeTools: allowsPhoneRuntimeTools
      )
    )
  }

  private func executableRegistry(
    descriptor: AgentNativeToolDescriptor
  ) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutable(
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.tool_loop_planner"
        ),
        executor: { invocation in
          .success(output: ["echo": invocation.input["value"] ?? .null])
        }
      )
    )
  }

  private func nativeToolDescriptor(
    id: String,
    risk: AgentNativeToolRisk = .low,
    permissions: [AgentNativePermissionRequirement] = []
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Tool loop planning provider test tool.",
      location: .phone,
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])])
      ],
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: risk,
      requiredPermissions: permissions,
      requiredConsents: [],
      availability: .available
    )
  }

  private static let echoToolId = "phone.test.echo"
}

private final class RecordingPlanningProvider: AgentModelPlanningProviding {
  var raw: String
  var invocations: [AgentModelPlanningInvocation] = []

  init(raw: String) {
    self.raw = raw
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    invocations.append(invocation)
    return raw
  }
}

private final class RecordingPlanningToolLoopRunner: AgentModelPlanningToolLoopRunning {
  var outcome: AgentModelToolLoopOutcome
  var requests: [AgentModelToolLoopRequest] = []

  init(_ outcome: AgentModelToolLoopOutcome) {
    self.outcome = outcome
  }

  func run(_ request: AgentModelToolLoopRequest) async -> AgentModelToolLoopOutcome {
    requests.append(request)
    return outcome
  }
}

private extension AgentModelToolLoopOutcome {
  static func completedPlan(_ text: String = #"{"actions":[]}"#) -> AgentModelToolLoopOutcome {
    AgentModelToolLoopOutcome(
      status: .completed,
      assistantText: text,
      messages: [.assistant(text)],
      events: [],
      usage: AgentModelToolLoopUsage(
        rounds: 1,
        toolCallAttempts: 0,
        retries: 0,
        inputTokens: 1,
        outputTokens: 1,
        durationMillis: 1
      ),
      toolManifestJson: "{}",
      toolManifestSha256: "hash",
      approval: nil,
      error: nil
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) throws -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    guard count == 1 else {
      throw CloudModelToolLoopAgentPlanningProviderTestError.missingSingleValue
    }
    return self[0]
  }
}

private enum CloudModelToolLoopAgentPlanningProviderTestError: Error {
  case missingSingleValue
}
