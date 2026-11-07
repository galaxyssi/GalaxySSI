import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelToolLoopTests: XCTestCase {
  func testHistorySnapshotFiltersAndUTF16Chunks() throws {
    var history = AgentModelObservationHistory(owner: "loop-a")
    func add(_ record: Int, _ tool: String, _ status: AgentNativeToolResultStatus, _ text: String,
             to reader: inout AgentModelObservationHistory) {
      reader.append(record: record, arguments: [:], result: AgentModelToolResultContent(
        callId: "call-\(record)", toolId: tool, status: status.rawValue, output: ["a/b~": .string(text)]))
    }
    let original = "A\u{1F642}B"
    add(3, "test.echo", .failed, original, to: &history)
    add(4, "test.other", .failed, "other", to: &history)
    add(5, "test.echo", .succeeded, "success", to: &history)
    add(6, "test.echo", .timedOut, "timed out", to: &history)
    add(7, AgentModelObservationHistory.toolID, .succeeded, "excluded", to: &history)
    var filters: AgentMcpJSONObject = ["limit": .int(1), "tool_id": .string("test.echo"), "failures_only": .bool(true)]
    let page = try history.read(filters)
    XCTAssertEqual(page["entries"]?.arrayValue?.first?.objectValue?["record"], .int(3))
    filters["cursor"] = try XCTUnwrap(page["next_cursor"])
    add(8, "test.echo", .failed, "new", to: &history)
    let next = try history.read(filters)
    XCTAssertEqual(next["snapshot_observations"], .int(4))
    XCTAssertEqual(next["entries"]?.arrayValue?.first?.objectValue?["record"], .int(6))
    XCTAssertNil(next["next_cursor"])
    var changedQuery = filters
    changedQuery["failures_only"] = .bool(false)
    XCTAssertThrowsError(try history.read(changedQuery))
    for owner in ["loop-a", "loop-b"] {
      var changed = AgentModelObservationHistory(owner: owner)
      add(3, "test.echo", .failed, owner == "loop-a" ? "changed" : original, to: &changed)
      add(4, "test.other", .failed, "other", to: &changed)
      add(5, "test.echo", .succeeded, "success", to: &changed)
      add(6, "test.echo", .timedOut, "timed out", to: &changed)
      XCTAssertThrowsError(try changed.read(filters))
    }
    var chunk: AgentMcpJSONObject = ["record": .int(3), "path": .string("/observation/output/a~1b~0"), "length": .int(2)]
    let first = try history.read(chunk)
    XCTAssertEqual(first["text"], .string("A"))
    chunk["offset"] = .int(2)
    XCTAssertThrowsError(try history.read(chunk))
    chunk["offset"] = first["next_offset"]
    let middle = try history.read(chunk)
    XCTAssertEqual(middle["text"], .string("\u{1F642}"))
    chunk["offset"] = middle["next_offset"]
    let end = try history.read(chunk)
    XCTAssertEqual(end["text"], .string("B"))
    XCTAssertEqual(end["sha256"], first["sha256"])
    XCTAssertEqual(end["total_characters"], .int(4))
    XCTAssertEqual(end["external_state_observed"], .bool(false))
    XCTAssertEqual(end["completion_verified"], .bool(false))
    XCTAssertNil(end["next_offset"])
  }

  func testEncryptedHistoryRestoresWithoutRunningNativeToolOrIndexingPriorMessages() async throws {
    let domain = "model-history-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    var executions = 0
    let registry = try registry(idempotency: .idempotent) { _ in
      executions += 1
      return .success(output: ["text": .string("original"), "number": .double(12)])
    }
    var input = request(loopId: "history-restored")
    input.observationHistoryEnabled = true
    input.observationHistorySource = "member-1"
    input.messages.append(.tool(AgentModelToolResultContent(
      callId: "earlier-call", toolId: Self.toolId, status: "succeeded", output: ["secret": .string("prior turn")])))
    let historyID = AgentModelObservationHistory.toolID
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("original"), AgentModelToolCall(callId: "history-page", toolId: historyID)]),
      AgentModelResponse(toolCalls: [AgentModelToolCall(callId: "history-detail", toolId: historyID, arguments: [
        "record": .int(3), "path": .string("/observation/output")
      ])]),
      AgentModelResponse(assistantText: "Done.")
    )
    let first = await loop(adapter: adapter, registry: registry,
                           journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    let history = first.messages.compactMap(\.toolResult).filter { $0.toolId == historyID }
    XCTAssertEqual(first.status, .completed)
    XCTAssertEqual(history.count, 2)
    XCTAssertEqual(history.first?.output["snapshot_observations"], .int(1))
    XCTAssertEqual(history.last?.output["text"], .string("{\"number\":12,\"text\":\"original\"}"))
    XCTAssertNil(history.last?.nativeResult)
    XCTAssertEqual(AgentModelObservationHistory.modelCatalog(registry.descriptors(), manifest: first.toolManifestJson)
      .last?.id, historyID)
    let unexpected = ScriptedModelAdapter(AgentModelResponse(assistantText: "Unexpected replay."))
    let reopened = EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)
    let restored = await loop(adapter: unexpected, registry: registry, journal: reopened).run(input)
    XCTAssertEqual(restored.status, .completed)
    XCTAssertEqual(restored.messages.compactMap(\.toolResult).filter { $0.toolId == historyID }, history)
    XCTAssertTrue(unexpected.requests.isEmpty)
    XCTAssertEqual(executions, 1)
    input.observationHistorySource = "different-member"
    let rejected = await loop(adapter: unexpected, registry: registry, journal: reopened).run(input)
    XCTAssertEqual(rejected.error?.code, "model_loop_history_catalog_changed")
  }

  func testHistoryKeepsLegacyCatalogAndDoesNotUnlockUncertainMutation() async throws {
    let journal = InMemoryAgentModelLoopJournal()
    var executions = 0
    let registry = try registry { _ in
      executions += 1
      return .failure(code: "effect_outcome_unknown", message: "Uncertain.")
    }
    var legacy = request(loopId: "legacy-catalog")
    let legacyResult = await loop(adapter: ScriptedModelAdapter(AgentModelResponse(assistantText: "Legacy.")),
                                  registry: registry, journal: journal).run(legacy)
    legacy.observationHistoryEnabled = true
    let unexpected = ScriptedModelAdapter(AgentModelResponse(assistantText: "Unexpected replay."))
    let replay = await loop(adapter: unexpected, registry: registry, journal: journal).run(legacy)
    XCTAssertEqual(replay.assistantText, "Legacy.")
    XCTAssertTrue(unexpected.requests.isEmpty)
    XCTAssertEqual(replay.toolManifestJson, legacyResult.toolManifestJson)
    XCTAssertEqual(AgentModelObservationHistory.modelCatalog(registry.descriptors(), manifest: replay.toolManifestJson),
                   registry.descriptors())

    var enabled = request(loopId: "new-catalog")
    enabled.observationHistoryEnabled = true
    let historyID = AgentModelObservationHistory.toolID
    let outcome = await loop(adapter: ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("mutation")]),
      AgentModelResponse(toolCalls: [AgentModelToolCall(callId: "history", toolId: historyID)]),
      AgentModelResponse(toolCalls: [call("repeat-mutation")]),
      AgentModelResponse(assistantText: "Needs verification.")
    ), registry: registry, journal: journal).run(enabled)
    let observations = outcome.messages.compactMap(\.toolResult)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(observations.first { $0.toolId == historyID }?.output["target_executed"], .bool(false))
    XCTAssertEqual(observations.last?.error?.code, "effect_outcome_unknown")
    XCTAssertNil(observations.last?.nativeResult)
  }

  func testBrowserReceiptAloneDoesNotUnlockUncertainMutation() async throws {
    var mutations = 0
    let registry = try registry { _ in
      mutations += 1
      return .failure(code: "effect_outcome_unknown", message: "Uncertain.")
    }
    let observerID = AgentIOSWebMediaNativeToolCatalog.browserSessionOperationStatus
    let observer = try descriptor(id: observerID, inputSchema: AgentNativeToolDescriptor.objectSchema(),
      idempotency: .idempotent, effect: .readOnly, concurrency: .parallelReadOnly)
    try registry.registerExecutable(.init(definition: .init(descriptor: observer, executorId: "test.browser_receipt"),
      executor: { _ in .success(output: ["state": .string("completed"), "business_success_verified": .bool(false)]) }))
    var input = request(loopId: "browser-receipt-is-not-verification")
    input.observationHistoryEnabled = true
    let outcome = await loop(adapter: ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("mutation")]),
      AgentModelResponse(toolCalls: [.init(callId: "browser-status", toolId: observerID)]),
      AgentModelResponse(toolCalls: [call("repeat-mutation")]),
      AgentModelResponse(assistantText: "Needs separate verification.")
    ), registry: registry).run(input)
    let results = outcome.messages.compactMap(\.toolResult)
    XCTAssertEqual(results.first(where: { $0.toolId == observerID })?.output.string("state"), "completed")
    XCTAssertEqual(results.last?.error?.code, "effect_outcome_unknown")
    XCTAssertNil(results.last?.nativeResult)
    XCTAssertEqual(mutations, 1)
  }

  func testNonIdempotentModelCallReceivesStableDerivedEffectKey() async throws {
    var capturedKeys: [String?] = []
    let registry = try registry(idempotency: .nonIdempotent) { invocation in
      capturedKeys.append(invocation.context.idempotencyKey)
      return .success()
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("non-idempotent-call")]),
      AgentModelResponse(assistantText: "Done.")
    )

    let first = await loop(adapter: adapter, registry: registry).run(request())
    let secondAdapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("non-idempotent-call")]),
      AgentModelResponse(assistantText: "Done.")
    )
    let second = await loop(adapter: secondAdapter, registry: registry).run(request())

    XCTAssertEqual(first.status, .completed)
    XCTAssertEqual(second.status, .completed)
    XCTAssertEqual(capturedKeys.count, 1)
    XCTAssertNotNil(capturedKeys[0])
    XCTAssertTrue(second.messages.contains { $0.toolResult?.nativeResult?.receipt.replayed == true })
  }

  func testDistinctPlannerLoopIdsScopeDerivedEffectKeysAndEvents() async throws {
    var capturedKeys: [String?] = []
    var capturedLoopIds: [String?] = []
    let registry = try registry(idempotency: .nonIdempotent) { invocation in
      capturedKeys.append(invocation.context.idempotencyKey)
      capturedLoopIds.append(invocation.context.attributes["model_loop_id"])
      return .success()
    }
    let first = await loop(
      adapter: ScriptedModelAdapter(
        AgentModelResponse(toolCalls: [call("same-call")]),
        AgentModelResponse(assistantText: "Done.")
      ),
      registry: registry
    ).run(request(loopId: "loop-a"))
    let second = await loop(
      adapter: ScriptedModelAdapter(
        AgentModelResponse(toolCalls: [call("same-call")]),
        AgentModelResponse(assistantText: "Done.")
      ),
      registry: registry
    ).run(request(loopId: "loop-b"))

    XCTAssertEqual(first.status, .completed)
    XCTAssertEqual(second.status, .completed)
    XCTAssertEqual(capturedKeys.count, 2)
    XCTAssertNotEqual(capturedKeys[0], capturedKeys[1])
    XCTAssertEqual(capturedLoopIds, ["loop-a", "loop-b"])
    XCTAssertTrue(first.events.allSatisfy { $0.details["model_loop_id"] == .string("loop-a") })
    XCTAssertTrue(second.events.allSatisfy { $0.details["model_loop_id"] == .string("loop-b") })
  }

  func testCollaborationOwnerSeparatesJournalsAndHostInvocationEvenWithSharedParentIDs() async throws {
    var owners: [AgentCollaborationToolEvidenceScope?] = []
    var effectKeys: [String] = []
    let registry = try registry { invocation in
      owners.append(invocation.context.collaborationOwner)
      effectKeys.append(invocation.context.idempotencyKey ?? "")
      return .success()
    }
    let journal = InMemoryAgentModelLoopJournal()
    let ordinary = request(loopId: "shared-loop")
    let encoder = JSONEncoder()
    let ordinaryJSON = try JSONDecoder().decode(AgentMcpJSONObject.self,
      from: encoder.encode(AgentModelLoopScope(request: ordinary)))
    XCTAssertNil(ordinaryJSON["collaboration_owner_digest"])
    var owned = ordinary
    owned.collaborationOwner = AgentCollaborationToolEvidenceScope(runId: "run",
      conversationId: ordinary.conversationId, turnId: ordinary.turnId,
      memberId: "member", sourceId: String(Int64.min))
    var other = owned
    other.collaborationOwner?.sourceId = String(Int64.max)
    XCTAssertEqual(Set([ordinary, owned, other].map { AgentModelLoopScope(request: $0).digest }).count, 3)

    for request in [ordinary, owned, other] {
      let adapter = ScriptedModelAdapter(AgentModelResponse(toolCalls: [call("same-call")]),
                                         AgentModelResponse(assistantText: "Done."))
      let result = await loop(adapter: adapter, registry: registry, journal: journal).run(request)
      XCTAssertEqual(result.status, .completed)
      XCTAssertEqual(adapter.requests.count, 2)
    }
    XCTAssertEqual(owners, [nil, owned.collaborationOwner, other.collaborationOwner])
    XCTAssertEqual(Set(effectKeys).count, 3)
  }

  func testDurableModelLoopRestoresCommittedResponsesAndToolObservations() async throws {
    var executions = 0
    let journal = InMemoryAgentModelLoopJournal()
    let firstRegistry = try registry(idempotency: .idempotencyKeyRequired) { _ in
      executions += 1
      return .success(output: ["echo": .string("durable")])
    }
    let firstAdapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("durable-call")]),
      AgentModelResponse(assistantText: "Durable result.")
    )
    var firstEvents: [AgentModelToolLoopEvent] = []
    let durableRequest = request(
      eventSink: AgentModelToolLoopEventSink { firstEvents.append($0) },
      loopId: "durable-loop"
    )

    let first = await loop(
      adapter: firstAdapter,
      registry: firstRegistry,
      journal: journal
    ).run(durableRequest)

    let restoredRegistry = try registry(idempotency: .idempotencyKeyRequired) { _ in
      executions += 1
      return .failure(code: "unexpected_execution", message: "Recovered tool ran again")
    }
    let restoredAdapter = ScriptedModelAdapter(AgentModelResponse(assistantText: "Unexpected model call."))
    var restoredEvents: [AgentModelToolLoopEvent] = []
    var restoredRequest = durableRequest
    restoredRequest.eventSink = AgentModelToolLoopEventSink { restoredEvents.append($0) }
    let restored = await loop(
      adapter: restoredAdapter,
      registry: restoredRegistry,
      journal: journal
    ).run(restoredRequest)

    XCTAssertEqual(first.status, .completed)
    XCTAssertEqual(restored.status, .completed)
    XCTAssertEqual(restored.assistantText, "Durable result.")
    XCTAssertEqual(AgentModelContextHandoff.executionMessages(restored.messages),
                   AgentModelContextHandoff.executionMessages(first.messages))
    XCTAssertEqual(firstAdapter.requests.count, 2)
    XCTAssertEqual(restoredAdapter.requests.count, 0)
    XCTAssertEqual(executions, 1)
    XCTAssertFalse(firstEvents.isEmpty)
    XCTAssertTrue(restoredEvents.isEmpty)
  }

  func testEncryptedLoopResumesAfterContextHandoffWithoutReexecutingCommittedCalls() async throws {
    let domain = "context-handoff-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    var executed: [String] = []
    let registry = try registry { invocation in
      executed.append(invocation.input["value"]?.strictStringValue ?? "")
      return .success(output: invocation.input)
    }
    let input = request(loopId: "handoff-loop")
    let budget = ConversationContextBudget(contextWindowTokens: 8_192, reservedOutputTokens: 512)
    let firstAdapter = ContextHandoffTestModelAdapter { request in
      switch request.round {
      case 1:
        return AgentModelResponse(toolCalls: [self.call("first")], providerRoute: "old")
      case 2:
        let projection = try AgentModelContextHandoffProjection.prepare(request.messages, budget: budget, route: "new")
        return AgentModelResponse(toolCalls: [self.call("second", arguments: ["value": .string("Bob")])],
          contextHandoff: try XCTUnwrap(projection.newHandoff), providerRoute: "new")
      default:
        throw AgentModelToolProtocolError(code: "interrupted", message: "Simulated process interruption.")
      }
    }
    let interrupted = await loop(adapter: firstAdapter, registry: registry,
      journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(interrupted.status, .modelFailed)
    XCTAssertEqual(executed, ["Alice", "Bob"])

    let resumedAdapter = ContextHandoffTestModelAdapter { request in
      XCTAssertEqual(request.round, 3)
      let projection = try AgentModelContextHandoffProjection.prepare(request.messages, budget: budget, route: "new")
      XCTAssertNil(projection.newHandoff)
      XCTAssertFalse(projection.messages.flatMap(\.toolCalls).contains { $0.callId == "first" })
      XCTAssertEqual(projection.messages.last?.toolResult?.callId, "second")
      return AgentModelResponse(assistantText: "Finished.", providerRoute: "new")
    }
    let resumed = await loop(adapter: resumedAdapter, registry: registry,
      journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(resumed.status, .completed)
    XCTAssertEqual(resumed.messages.compactMap(\.toolResult).map(\.callId), ["first", "second"])
    XCTAssertEqual(executed, ["Alice", "Bob"])
  }

  func testDurableModelLoopRejectsInputAndManifestDrift() async throws {
    let journal = InMemoryAgentModelLoopJournal()
    let registry = try registry { _ in .success() }
    let firstAdapter = ScriptedModelAdapter(AgentModelResponse(assistantText: "Stored."))
    let first = await loop(
      adapter: firstAdapter,
      registry: registry,
      journal: journal
    ).run(request(loopId: "drift-loop"))
    var changed = request(loopId: "drift-loop")
    changed.messages = [.user("Changed input must not reuse the old loop." )]
    let secondAdapter = ScriptedModelAdapter(AgentModelResponse(assistantText: "Unexpected."))
    let rejected = await loop(
      adapter: secondAdapter,
      registry: registry,
      journal: journal
    ).run(changed)

    XCTAssertEqual(first.status, .completed)
    XCTAssertEqual(rejected.status, .modelFailed)
    XCTAssertEqual(rejected.error?.code, "model_loop_checkpoint_binding_changed")
    XCTAssertEqual(secondAdapter.requests.count, 0)
  }

  func testEncryptedRecoveryResendsOpaqueAssistantStateWithoutRunningDuplicateCalls() async throws {
    let domain = "provider-continuation-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    var executions = 0
    let registry = try registry { _ in
      executions += 1
      return .success()
    }
    let adapter = AgentProviderRouteAdapter(base: OpenAiCompatibleAgentModelToolProtocolAdapter(), route: "same-account")
    let signed = try adapter.decodeResponse(#"""
      {"choices":[{"message":{"role":"assistant","content":"Working","reasoning_content":"private continuation",
        "tool_calls":[
          {"id":"wire-dup","type":"function","function":{"name":"\#(Self.toolId)","arguments":"{\"value\":\"one\"}"}},
          {"id":"wire-dup","type":"function","function":{"name":"\#(Self.toolId)","arguments":"{\"value\":\"two\"}"}}
        ]}}]}
      """#, catalog: registry.descriptors())
    let input = request(loopId: "signed-loop")
    let interrupted = await loop(adapter: ContinuationTestModelAdapter { turn in
      if turn.round == 1 { return signed }
      throw AgentModelToolProtocolError(code: "interrupted", message: "Simulated interruption.")
    }, registry: registry, journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(interrupted.status, .modelFailed)
    XCTAssertEqual(executions, 1)
    let resumed = await loop(adapter: ContinuationTestModelAdapter { turn in
      XCTAssertEqual(turn.round, 2)
      let wire = try adapter.encodeConversation(turn.messages)
      let items = try XCTUnwrap(wire["messages"]?.arrayValue)
      XCTAssertEqual(items[1].objectValue?["reasoning_content"], .string("private continuation"))
      XCTAssertEqual(items.suffix(2).compactMap { $0.objectValue?["tool_call_id"]?.strictStringValue },
                     ["wire-dup", "wire-dup"])
      XCTAssertEqual(turn.messages.last?.toolResult?.error?.code, "repeated_tool_call_id")
      return AgentModelResponse(assistantText: "Done.")
    }, registry: registry, journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(resumed.status, .completed)
    XCTAssertEqual(executions, 1)
    XCTAssertFalse(resumed.messages.contains { $0.providerContinuation != nil })
    XCTAssertEqual(resumed.messages.compactMap(\.toolResult).map(\.status), ["succeeded", "rejected"])
  }

  func testInitialPlanningJournalRestoresBoundEncryptedInput() async throws {
    let backing = InMemoryAgentModelLoopJournal()
    let journal = AgentInitialPlanningJournal(journal: backing)
    let input = AgentInitialPlanningInput(
      goal: "Read durable memory",
      conversation: AgentConversationContext(
        conversationId: "conversation-1",
        summary: "Original private context",
        turns: [],
        privateMode: true,
        globalContext: "Committed global context",
        trackingPaused: false
      ),
      turnId: "turn-1",
      executionMode: .autoComplete,
      hasAttachments: false,
      allowsDirectResponse: true,
      completionRequirements: nil,
      plannerConfigurationSha256: "configuration"
    )
    var retainedReference: AgentInitialPlanningReference?
    let value = try await journal.begin(sessionId: "session-1", input: input) { reference in
      retainedReference = reference
      return 42
    }
    let reference = try XCTUnwrap(retainedReference)
    let restored = try await journal.restore(reference) { $0 }

    XCTAssertEqual(value, 42)
    XCTAssertEqual(restored, input)
    XCTAssertEqual(reference.inputSha256.count, 64)

    var changed = reference
    changed.inputSha256 = String(repeating: "0", count: 64)
    do {
      _ = try await journal.restore(changed) { $0 }
      XCTFail("Expected changed initial planning input to be rejected.")
    } catch let error as AgentModelLoopRecoveryError {
      XCTAssertEqual(error.code, "initial_planning_input_changed")
    }
  }

  func testPlanningJournalRestoresBoundReplanningIntent() async throws {
    let backing = InMemoryAgentModelLoopJournal()
    let journal = AgentInitialPlanningJournal(journal: backing)
    let intent = AgentReplanningIntent(
      planId: "plan-1",
      revision: 7,
      planSha256: String(repeating: "a", count: 64),
      reason: "rolling_batch_completed:revision=7"
    )
    let input = AgentInitialPlanningInput(
      goal: "Continue from committed observations",
      conversation: AgentConversationContext(
        conversationId: "conversation-1",
        summary: "Original private context",
        turns: [],
        privateMode: true,
        globalContext: "Committed global context",
        trackingPaused: false
      ),
      turnId: "turn-1",
      executionMode: .autoComplete,
      hasAttachments: false,
      allowsDirectResponse: false,
      completionRequirements: nil,
      plannerConfigurationSha256: "configuration",
      replanning: intent
    )
    var retainedReference: AgentInitialPlanningReference?
    _ = try await journal.begin(sessionId: "session-1", input: input) { reference in
      retainedReference = reference
    }
    let reference = try XCTUnwrap(retainedReference)
    let restored = try await journal.restore(reference) { $0 }

    XCTAssertTrue(reference.isReplanning)
    XCTAssertEqual(reference.basePlanId, intent.planId)
    XCTAssertEqual(reference.baseRevision, intent.revision)
    XCTAssertEqual(restored, input)
    XCTAssertEqual(restored.replanning, intent)

    var changed = reference
    changed.basePlanId = "different-plan"
    do {
      _ = try await journal.restore(changed) { $0 }
      XCTFail("Expected changed replanning base scope to be rejected.")
    } catch let error as AgentModelLoopRecoveryError {
      XCTAssertEqual(error.code, "planning_base_scope_changed")
    }
  }

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

  func testAgentModelToolLoopDoesNotRetryIdempotentMutationFailures() async throws {
    var executions = 0
    let registry = try registry(idempotency: .idempotent, effect: .mutation) { _ in
      executions += 1
      return .failure(code: "write_uncertain", message: "Write outcome is uncertain", retryable: true)
    }
    let adapter = ScriptedModelAdapter(
      AgentModelResponse(toolCalls: [call("mutation-call")]),
      AgentModelResponse(assistantText: "The write must be reconciled before another attempt.")
    )

    let outcome = await loop(adapter: adapter, registry: registry).run(request())

    XCTAssertEqual(outcome.status, .completed)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(outcome.usage.retries, 0)
    XCTAssertFalse(outcome.events.contains { $0.type == .toolRetryScheduled })
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

  func testCanonicalJournalReopensThroughProviderWireAliasesWithoutExecutingAgain() async throws {
    let domain = "provider-wire-names-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    var executions = 0
    let registry = try registry { invocation in
      executions += 1
      return .success(output: invocation.input)
    }
    let input = request(loopId: "legacy-wire-journal")
    let original = await loop(adapter: WireNameRecoveryModelAdapter { turn in
      if turn.round == 1 {
        return AgentModelResponse(toolCalls: [self.call("canonical-call", arguments: ["value": .string(Self.toolId)])])
      }
      throw AgentModelToolProtocolError(code: "interrupted", message: "Simulated interruption.")
    }, registry: registry, journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(original.status, .modelFailed)
    XCTAssertEqual(executions, 1)
    let resumed = await loop(adapter: WireNameRecoveryModelAdapter { turn in
      XCTAssertEqual(turn.round, 2)
      XCTAssertEqual(turn.messages.last?.toolResult?.toolId, Self.toolId)
      XCTAssertEqual(turn.messages.last?.toolResult?.output["value"], .string(Self.toolId))
      for provider in AgentModelToolProvider.allCases {
        let protocolAdapter = AgentModelToolProtocolAdapters.adapter(for: provider)
        let wire = AgentMcpJSONCodec.stringify(try protocolAdapter.encodeConversation(turn.messages))
        XCTAssertTrue(wire.contains("phone__test__echo"))
        XCTAssertTrue(wire.contains("canonical-call"))
      }
      return AgentModelResponse(assistantText: "Done.")
    }, registry: registry, journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets)).run(input)
    XCTAssertEqual(resumed.status, .completed)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(resumed.messages.compactMap(\.toolResult).map(\.toolId), [Self.toolId])
  }

  func testManagedBrowserControlIntentAndStopSurviveRestart() async throws {
    let domain = "managed-browser-control-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    let original = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
    let owner = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "conversation",
      turnId: "turn", memberId: "member", sourceId: "source")
    let member = AgentTeamMemberSnapshot(agentId: "local-model", status: .running, instanceId: owner.memberId,
      sourceMessageId: owner.sourceId, dispatchCheckpoint: .accepted)
    let team = AgentTeamExecutionSnapshot(supervisorRunId: owner.runId, teamId: "team",
      conversationId: owner.conversationId, taskId: owner.turnId, primaryAgentId: "other",
      state: .running, members: [member])
    let binding = try XCTUnwrap(AgentManagedBrowserDispatchBinding(owner: owner, team: team,
      profileID: "profile", modelID: "model", hostContextDigest: "context"))
    let scope = AgentManagedBrowserContinuationStore.RunScope(binding)
    let foreign = AgentManagedBrowserContinuationStore.RunScope(profileID: "foreign", team: team,
      hostContextDigest: "context")
    let input = AgentManagedBrowserLoopInput(loopID: "loop", inputIdentity: "immutable",
      toolManifestHash: "pinned", systemPrompt: "", prompt: "Original member input", hasAttachments: false)
    try original.enroll(binding, input: input, legacyLoopExists: false)
    let ticket = try await original.withLease(binding: binding, mode: .initial, control: .run) { lease, _ in
      try original.requestControl(lease: lease, binding: binding, callID: "call",
        invocationID: "invocation", address: "https://example.test/").ticket
    }
    XCTAssertTrue(try original.writeControl(.pause, scope: scope))
    let restarted = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
    XCTAssertEqual(try restarted.control(scope: scope), .pause)
    XCTAssertNil(try restarted.control(scope: foreign))
    XCTAssertEqual(restarted.indexedBindings(scope: scope), [binding])
    XCTAssertTrue(restarted.indexedBindings(scope: foreign).isEmpty)
    let observation = AgentManagedBrowserHandoff.Observation(address: "https://example.test/",
      title: "Example", text: "Read only")
    XCTAssertThrowsError(try restarted.returnControl(ticket, binding: binding, observation: observation))
    XCTAssertTrue(try restarted.writeControl(.run, scope: scope))
    do {
      _ = try await restarted.withLease(binding: binding, mode: .recovery, control: .run) { _, _ in
        XCTFail("RUN must not take an active human handoff")
      }
    } catch let failure as AgentManagedBrowserContinuationStore.Failure {
      XCTAssertEqual(failure, .notReady)
    }
    XCTAssertTrue(try restarted.writeControl(.stop, scope: scope))
    XCTAssertFalse(try restarted.writeControl(.run, scope: scope))
    let stopped = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
    try stopped.retireStoppedBinding(binding)
    XCTAssertEqual(try stopped.handoff(ticket, binding: binding).state, .stopped)
    XCTAssertThrowsError(try stopped.returnControl(ticket, binding: binding, observation: observation))
    try await stopped.withLease(binding: binding, mode: .recovery, control: .run) { lease, work in
      guard case .settleCancellation = work else { return XCTFail("STOP must not resume inference") }
      let receipt = try stopped.commit(.cancelled, text: "Stopped", lease: lease, binding: binding)
      try stopped.acknowledge(receipt, lease: lease, binding: binding)
    }
    try stopped.backfillWakeIndex(binding)
    XCTAssertTrue(stopped.indexedBindings(scope: scope).isEmpty)
    XCTAssertTrue(stopped.pendingBindings(profileID: "profile").isEmpty)
  }

  func testManagedBrowserReturnReopensOriginalLoopAndDoesNotRepeatHandoff() async throws {
    let domain = "managed-browser-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    let dispatch = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
    var request = self.request(loopId: "member-loop")
    let owner = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: request.conversationId,
      turnId: request.turnId, memberId: "member", sourceId: "original-source")
    request.collaborationOwner = owner
    let member = AgentTeamMemberSnapshot(agentId: "local-model", status: .running, instanceId: owner.memberId,
      sourceMessageId: owner.sourceId, dispatchCheckpoint: .accepted)
    let team = AgentTeamExecutionSnapshot(supervisorRunId: owner.runId, teamId: "team",
      conversationId: owner.conversationId, taskId: owner.turnId, primaryAgentId: "other",
      state: .running, members: [member])
    let binding = try XCTUnwrap(AgentManagedBrowserDispatchBinding(owner: owner, team: team,
      profileID: "profile", modelID: "model", hostContextDigest: "context"))
    let input = AgentManagedBrowserLoopInput(loopID: request.loopId, inputIdentity: "immutable",
      toolManifestHash: "pinned", systemPrompt: "", prompt: "Original member input", hasAttachments: false)
    XCTAssertThrowsError(try dispatch.enroll(binding, input: input, legacyLoopExists: true))
    try dispatch.enroll(binding, input: input, legacyLoopExists: false)
    let call = AgentModelToolCall(callId: "handoff", toolId: AgentManagedBrowserToolExecution.toolID,
      arguments: ["url": .string("https://example.test/")])
    let initialAdapter = ScriptedModelAdapter(AgentModelResponse(toolCalls: [call]))
    let ticket = try await dispatch.withLease(binding: binding, mode: .initial, control: .run) { lease, work in
      guard case .continueLoop(let original) = work else { throw AgentManagedBrowserContinuationStore.Failure.notReady }
      XCTAssertEqual(original, input)
      let control = AgentManagedBrowserToolExecution(store: dispatch, binding: binding, lease: lease)
      let registry = try AgentNativeToolRegistry().registerExecutable(control.executable())
      let outcome = await AgentModelToolLoop(modelAdapter: initialAdapter, toolRegistry: registry,
        journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets), browserHandoff: control).run(request)
      XCTAssertEqual(outcome.status, .waitingForBrowserControl)
      XCTAssertFalse(outcome.isTerminal)
      XCTAssertEqual(initialAdapter.requests.count, 1)
      let ticket = try XCTUnwrap(dispatch.awaitingHandoff(binding: binding)?.ticket)
      let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "private", .domain: "example.test",
        .path: "/", .secure: "TRUE"]))
      let foreign = try XCTUnwrap(HTTPCookie(properties: [.name: "foreign", .value: "private", .domain: "elsewhere.test",
        .path: "/", .secure: "TRUE"]))
      try dispatch.saveCookies([cookie, foreign], ticket: ticket, binding: binding)
      let cookieReload = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
      XCTAssertEqual(try cookieReload.cookies(ticket, binding: binding).map(\.name), ["session"])
      let observation = AgentManagedBrowserHandoff.Observation(address: "https://example.test/returned",
        title: "Returned page", text: "User-reviewed observation")
      let stale = AgentManagedBrowserHandoff.Ticket(dispatchKey: ticket.dispatchKey, callID: ticket.callID, generation: UUID())
      XCTAssertThrowsError(try dispatch.returnControl(stale, binding: binding, observation: observation))
      try dispatch.returnControl(ticket, binding: binding, observation: observation)
      do {
        try await dispatch.withLease(binding: binding, mode: .recovery, control: .run) { _, _ in
          XCTFail("Fast return cannot acquire the original process lease.")
        }
      } catch let error as AgentManagedBrowserContinuationStore.Failure {
        XCTAssertEqual(error, .busy)
      }
      return ticket
    }
    let reopened = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain)
    XCTAssertEqual(try reopened.handoff(ticket, binding: binding).state, .returned)
    let resumedAdapter = ScriptedModelAdapter(AgentModelResponse(assistantText: "Original member finished."))
    let receipt = try await reopened.withLease(binding: binding, mode: .recovery, control: .run) { lease, work in
      guard case .continueLoop = work else { throw AgentManagedBrowserContinuationStore.Failure.notReady }
      let control = AgentManagedBrowserToolExecution(store: reopened, binding: binding, lease: lease)
      let registry = try AgentNativeToolRegistry().registerExecutable(.init(
        definition: .init(descriptor: try AgentManagedBrowserToolExecution.descriptor(),
                          executorId: "ios.managed_browser_handoff"), executor: { _ in
          XCTFail("Durable recovery must not invoke the handoff again.")
          return .failure(code: "unexpected", message: "Handoff replayed")
        }))
      let outcome = await AgentModelToolLoop(modelAdapter: resumedAdapter, toolRegistry: registry,
        journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets), browserHandoff: control).run(request)
      XCTAssertEqual(outcome.status, .completed)
      XCTAssertEqual(resumedAdapter.requests.map(\.round), [2])
      XCTAssertEqual(resumedAdapter.requests.first?.messages.last?.toolResult?.output["business_success_verified"], .bool(false))
      XCTAssertEqual(resumedAdapter.requests.first?.messages.last?.toolResult?.output["state"], .string("returned"))
      XCTAssertNil(resumedAdapter.requests.first?.messages.last?.toolResult?.output["cookies"])
      return try reopened.commit(.completed, text: outcome.assistantText, lease: lease, binding: binding)
    }
    try await dispatch.withLease(binding: binding, mode: .recovery, control: .run) { lease, work in
      guard case .deliver(let pending) = work else { return XCTFail("A committed result must be delivered without inference.") }
      XCTAssertEqual(pending, receipt)
      try dispatch.acknowledge(pending, lease: lease, binding: binding)
    }
    try await dispatch.withLease(binding: binding, mode: .recovery, control: .run) { _, work in
      guard case .alreadyDelivered = work else { return XCTFail("Acknowledged receipt must not be delivered twice.") }
    }
  }

  private func loop(
    adapter: AgentModelAdapter,
    registry: AgentNativeToolRegistry,
    clock: MutableClock = MutableClock(now: 100),
    journal: AgentModelLoopJournal? = nil
  ) -> AgentModelToolLoop {
    AgentModelToolLoop(
      modelAdapter: adapter,
      toolRegistry: registry,
      clock: AgentModelToolLoopClock { clock.now },
      idFactory: countingIds(),
      journal: journal
    )
  }

  private func request(
    budget: AgentModelToolLoopBudget = AgentModelToolLoopBudget(),
    cancellationToken: AgentModelToolLoopCancellationToken = .none,
    eventSink: AgentModelToolLoopEventSink = .none,
    loopId: String = ""
  ) -> AgentModelToolLoopRequest {
    AgentModelToolLoopRequest(
      sessionId: "session-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      workspaceId: "workspace-1",
      loopId: loopId,
      messages: [.user("Use the phone tool.")],
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
    effect: AgentNativeToolEffect? = nil,
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
            effect: effect ?? (idempotency == .idempotent ? .readOnly : nil),
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
    effect: AgentNativeToolEffect? = nil,
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
      concurrency: concurrency,
      effect: effect
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

private struct ContextHandoffTestModelAdapter: AgentModelAdapter {
  let respond: (AgentModelRequest) throws -> AgentModelResponse

  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
    try respond(request)
  }
}

private struct WireNameRecoveryModelAdapter: AgentModelAdapter {
  let respond: (AgentModelRequest) throws -> AgentModelResponse

  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
    try respond(request)
  }
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

private struct ContinuationTestModelAdapter: AgentModelAdapter {
  let respond: (AgentModelRequest) throws -> AgentModelResponse

  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
    try respond(request)
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
