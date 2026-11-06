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
    ) { _, _, _ in
      XCTFail("No tool loop should be created without safe native tools.")
      return RecordingPlanningToolLoopRunner(.completedPlan())
    }

    let raw = try await provider.rawPlan(invocation: invocation(nativeTools: []))

    XCTAssertEqual(raw, #"{"actions":[{"kind":"READ_SCREEN","parameters":{}}]}"#)
    XCTAssertEqual(fallback.invocations.count, 1)
  }

  func testToolLoopPlanningProviderDoesNotFallbackAcrossDurableRecovery() async throws {
    let source = invocation(nativeTools: [])
    let identity = AgentModelLoopRecoveryIdentity.sha256([
      "goal": source.request.planRequest.goal,
      "conversation_id": source.request.conversationContext.conversationId,
      "execution_turn_id": source.request.executionTurnId,
      "replan_reason": source.request.parsingContext.replanReason,
      "completion_requirements": AgentModelLoopRecoveryIdentity.sha256(
        source.request.planRequest.completionRequirements
      ),
      "execution_history": AgentModelLoopRecoveryIdentity.sha256(source.request.executionHistory)
    ])
    let loopId = "planner-\(identity)"
    let recoveryRequest = AgentModelToolLoopRequest(
      sessionId: loopId,
      conversationId: loopId,
      turnId: loopId,
      taskId: loopId,
      workspaceId: AgentWorkspaceScope.id(conversationId: loopId, sessionId: loopId),
      loopId: loopId,
      messages: [.system(source.systemPrompt), .user(source.prompt)],
      budget: CloudModelToolLoopAgentPlanningProvider.androidPlannerBudget,
      callerId: CloudModelToolLoopAgentPlanningProvider.toolLoopCallerId,
      recoveryInputIdentity: identity
    )
    let journal = InMemoryAgentModelLoopJournal()
    try await journal.withLease(scope: AgentModelLoopScope(request: recoveryRequest)) { records in
      _ = try AgentModelLoopCheckpoint(records: records).initial(
        request: recoveryRequest,
        manifestSha256: "retained-manifest"
      )
    }
    let fallback = RecordingPlanningProvider(raw: "fallback")
    let provider = try CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: fallback,
      toolRegistry: AgentNativeToolRegistry(),
      recoveryJournal: journal
    ) { _, _, _ in
      XCTFail("A missing live catalog must not replace a durable loop.")
      return RecordingPlanningToolLoopRunner(.completedPlan())
    }

    do {
      _ = try await provider.rawPlan(invocation: source)
      XCTFail("Expected durable recovery to block fallback planning.")
    } catch let error as AgentModelPlanningProviderError {
      XCTAssertEqual(error, .recoveryRequired("model_loop_requires_recovery_not_fallback"))
    }
    XCTAssertTrue(fallback.invocations.isEmpty)
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
    ) { catalog, registry, _ in
      capturedCatalog = catalog
      capturedRegistry = registry
      return runner
    }

    let raw = try await provider.rawPlan(invocation: invocation(
      nativeTools: [descriptor],
      conversationId: "conversation-1",
      executionTurnId: "execution-turn-1",
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
    XCTAssertEqual(request.turnId, "execution-turn-1")
    XCTAssertEqual(request.taskId, "execution-turn-1")
    XCTAssertEqual(
      request.workspaceId,
      AgentWorkspaceScope.id(conversationId: "conversation-1", sessionId: "conversation-1")
    )
    XCTAssertTrue(request.loopId.hasPrefix("planner-"))
    XCTAssertEqual(request.recoveryInputIdentity.count, 64)
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
    XCTAssertEqual(workspace.workspaceId, request.workspaceId)
    XCTAssertEqual(workspace.sessionId, "conversation-1")
    XCTAssertEqual(workspace.conversationId, "conversation-1")
    XCTAssertEqual(workspace.taskId, "execution-turn-1")
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
    ) { _, _, _ in runner }

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

  func testPlanRepairDoesNotRestartTheNativeToolLoop() async throws {
    let descriptor = try nativeToolDescriptor(id: Self.echoToolId)
    let registry = try executableRegistry(descriptor: descriptor)
    let runner = RecordingPlanningToolLoopRunner(.completedPlan())
    let textProvider = RecordingPlanningProvider(raw: "repaired plan")
    let provider = CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: textProvider, toolRegistry: registry, requestIdFactory: { "fixture" }
    ) { _, _, _ in runner }
    let source = invocation(nativeTools: [descriptor])
    _ = try await provider.rawPlan(invocation: source)
    let repair = try await provider.repairPlan(invocation: source)
    XCTAssertEqual(repair, "repaired plan")
    XCTAssertEqual(runner.requests.count, 1)
    XCTAssertEqual(textProvider.invocations, [source])
  }

  func testPlanningAttemptsReuseStableDurableLoopIdentity() async throws {
    let descriptor = try nativeToolDescriptor(id: Self.echoToolId)
    let registry = try executableRegistry(descriptor: descriptor)
    let runner = RecordingPlanningToolLoopRunner(.completedPlan())
    var ids = ["loop-a", "loop-b"]
    let provider = CloudModelToolLoopAgentPlanningProvider(
      fallbackProvider: RecordingPlanningProvider(raw: "fallback"),
      toolRegistry: registry,
      requestIdFactory: { ids.removeFirst() }
    ) { _, _, _ in runner }
    let source = invocation(
      nativeTools: [descriptor],
      conversationId: "conversation-1",
      executionTurnId: "execution-turn"
    )

    _ = try await provider.rawPlan(invocation: source)
    _ = try await provider.rawPlan(invocation: source)

    XCTAssertEqual(Set(runner.requests.map(\.workspaceId)).count, 1)
    XCTAssertEqual(runner.requests.map(\.turnId), ["execution-turn", "execution-turn"])
    XCTAssertEqual(Set(runner.requests.map(\.loopId)).count, 1)
    XCTAssertTrue(runner.requests.allSatisfy { $0.loopId.hasPrefix("planner-") })
    XCTAssertEqual(Set(runner.requests.map(\.recoveryInputIdentity)).count, 1)
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
    ) { _, _, _ in runner }

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

  func testPlannerRefreshesRepairedToolsAndResumesCommittedSetupWithoutRepeatingIt() async throws {
    let domain = "planner-catalog-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let contact = try store.addCloudModelContact(displayName: "Planner", provider: "OpenAI",
      modelId: "fixture-model", endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-fixture", apiStyle: .openAICompatible)
    let setup = try nativeToolDescriptor(id: "phone.test.setup")
    var read = try nativeToolDescriptor(id: Self.echoToolId)
    read.effect = .readOnly
    read.idempotency = .idempotent
    var installed = false
    var setupCalls = 0
    var reads = 0
    var probes = 0
    let registry = try AgentNativeToolRegistry(nowMillis: { 100 })
    try registry.registerExecutable(AgentNativeToolExecutableDefinition(
      definition: .init(descriptor: setup, executorId: "setup"), executor: { _ in
        installed = true
        setupCalls += 1
        return .success()
      }))
    try registry.registerExecutable(AgentNativeToolExecutableDefinition(
      definition: .init(descriptor: read, executorId: "read", availabilityProvider: .init { _ in
        probes += 1
        return installed ? .available : .init(status: .unavailable, reason: "Missing dependency")
      }), executor: { _ in
        reads += 1
        return .success()
      }))
    var original = invocation(nativeTools: [setup], conversationId: "catalog-owner", executionTurnId: "turn")
    original.registeredNativeTools = [setup, read]
    let firstSender = PlannerCatalogFixtureSender { request, catalog in
      let ids = Set(catalog.map(\.id))
      if request.round == 1 {
        XCTAssertTrue(ids.contains(setup.id))
        XCTAssertFalse(ids.contains(read.id))
        return AgentModelResponse(toolCalls: [.init(callId: "install", toolId: setup.id)])
      }
      XCTAssertTrue(ids.contains(read.id))
      throw AgentModelToolProtocolError(code: "interrupted", message: "Simulated interruption after setup.")
    }
    let first = CloudModelToolLoopAgentPlanningProvider(contact: contact, store: store, toolRegistry: registry,
      nativeToolSender: firstSender, disclosureStore: InMemoryAgentDataDisclosureStore(),
      journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets), memoryTelemetryCapture: { _ in })
    do {
      _ = try await first.rawPlan(invocation: original)
      XCTFail("Expected interruption.")
    } catch let error as AgentModelPlanningProviderError {
      guard case .recoveryRequired = error else { return XCTFail("Expected recovery, got \(error)") }
    }
    XCTAssertEqual(setupCalls, 1)
    var resumedProbeCount = 0
    let resumedSender = PlannerCatalogFixtureSender { request, catalog in
      XCTAssertTrue(catalog.contains { $0.id == read.id })
      if request.round == 2 {
        resumedProbeCount = probes
        return AgentModelResponse(toolCalls: [.init(callId: "read", toolId: read.id)])
      }
      XCTAssertEqual(request.round, 3)
      XCTAssertEqual(probes, resumedProbeCount + 1, "Only execution should recheck this read-only tool.")
      return AgentModelResponse(assistantText: #"{"actions":[]}"#)
    }
    let resumed = CloudModelToolLoopAgentPlanningProvider(contact: contact, store: store, toolRegistry: registry,
      nativeToolSender: resumedSender, disclosureStore: InMemoryAgentDataDisclosureStore(),
      journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets), memoryTelemetryCapture: { _ in })
    let result = try await resumed.rawPlan(invocation: original)
    XCTAssertEqual(result, #"{"actions":[]}"#)
    XCTAssertEqual(setupCalls, 1)
    XCTAssertEqual(reads, 1)
    var changed = original
    changed.registeredNativeTools = [setup]
    do {
      _ = try await resumed.rawPlan(invocation: changed)
      XCTFail("Changed registered tools must not replace a durable loop.")
    } catch let error as AgentModelPlanningProviderError {
      XCTAssertEqual(error, .recoveryRequired("planner_tool_contracts_changed"))
    }
  }

  func testPreparedBindingCountsAsDurableAndLegacyInitialIsNotPromoted() async throws {
    let journal = InMemoryAgentModelLoopJournal()
    func request(_ id: String) -> AgentModelToolLoopRequest {
      AgentModelToolLoopRequest(sessionId: "session", conversationId: "conversation", turnId: "turn",
        taskId: "task", workspaceId: "workspace", loopId: id, messages: [.user("Goal")])
    }
    let prepared = request("prepared")
    let owner = AgentModelLoopScope(request: prepared)
    try await journal.withLease(scope: owner) { records in
      let checkpoint = AgentModelLoopCheckpoint(records: records)
      XCTAssertTrue(try checkpoint.plannerCatalogUsesContracts(scope: owner, fingerprint: "contract"))
      XCTAssertNil(try records.read("initial"))
      XCTAssertThrowsError(try checkpoint.plannerCatalogUsesContracts(scope: owner, fingerprint: "changed"))
    }
    XCTAssertTrue(try journal.hasRecords(scope: owner))

    let legacy = request("legacy")
    let legacyOwner = AgentModelLoopScope(request: legacy)
    try await journal.withLease(scope: legacyOwner) { records in
      let checkpoint = AgentModelLoopCheckpoint(records: records)
      _ = try checkpoint.initial(request: legacy, manifestSha256: "old-available-only")
      XCTAssertFalse(try checkpoint.plannerCatalogUsesContracts(scope: legacyOwner, fingerprint: "contract"))
      XCTAssertNil(try records.read(AgentPlannerToolCatalogSession.operation))
    }
  }

  private func invocation(
    nativeTools: [AgentNativeToolDescriptor],
    allowsPhoneRuntimeTools: Bool = false,
    conversationId: String = "",
    executionTurnId: String = "",
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
        executionTurnId: executionTurnId,
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

private struct PlannerCatalogFixtureSender: CloudModelNativeToolSending {
  let respond: (AgentModelRequest, [AgentNativeToolDescriptor]) throws -> AgentModelResponse

  func sendNativeToolTurn(contact: GalaxySSIContact, store: GalaxySSIStore,
                          request: AgentModelRequest, catalog: [AgentNativeToolDescriptor]) async throws -> AgentModelResponse {
    try respond(request, catalog)
  }
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
