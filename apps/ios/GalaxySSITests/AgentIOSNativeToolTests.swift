import UIKit
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testDeviceStateEvidenceRequiresTypedReadbackForTheExactRequest() {
    let tool = AgentIOSSystemNativeToolCatalog.audioVolumeSet
    let input: AgentMcpJSONObject = ["stream": .string("media"), "percent": .int(50)]
    let readback: AgentMcpJSONObject = [
      "stream": .string("music"), "requested_percent": .int(50), "target_volume": .int(8),
      "min": .int(0), "max": .int(15), "volume": .int(8), "state_verified": .bool(true),
      "request_accepted": .bool(false), "dispatch_attempted": .bool(true), "observed_at_epoch_ms": .int(12),
      "observation_scope": .string("native_audio_stream")
    ]
    func verifies(_ output: AgentMcpJSONObject) -> Bool {
      AgentIOSDeviceStateEvidence.verified(tool, output: output, input: input)
    }
    XCTAssertTrue(verifies(readback), "Actual readback can verify a state even when dispatch raised an error.")
    let invalidFields: [(String, AgentMcpJSONValue)] = [
      ("volume", .int(3)), ("volume", .string("8")), ("volume", .null), ("min", .int(9)),
      ("max", .int(30)), ("target_volume", .int(7)), ("requested_percent", .int(53)),
      ("observed_at_epoch_ms", .int(0)), ("stream", .string("ring")),
      ("state_verified", .bool(false)), ("global_volume_supported", .bool(false))
    ]
    for (field, falseEvidence) in invalidFields {
      var changed = readback
      changed[field] = falseEvidence
      XCTAssertFalse(verifies(changed), field)
    }
    let legacy = AgentAction(id: "legacy", kind: .callNativeTool, target: tool, risk: .medium,
      status: .completed, description: "Set media volume", parameters: ["tool_id": tool],
      evidence: #"{"request_accepted":true,"requested_percent":50}"#)
    XCTAssertTrue(AgentCompletionEvidencePolicy.hasUnverifiedOutcome(legacy))
    var observed = legacy
    observed.evidence = AgentMcpJSONCodec.stringify(readback)
    XCTAssertFalse(AgentCompletionEvidencePolicy.hasUnverifiedOutcome(observed))
    observed.parameters["input_json"] = #"{"stream":"media","percent":75}"#
    XCTAssertTrue(AgentCompletionEvidencePolicy.hasUnverifiedOutcome(observed))
  }

  func testTorchReadbackSkipsSatisfiedStateAndNeverRetriesADispatch() {
    let tool = AgentIOSHardwareNativeToolCatalog.flashlightSet
    var current = true
    var reads = 0
    var writes = 0
    func request(_ enabled: Bool, applied: Bool, throwsAfterDispatch: Bool = false) -> AgentMcpJSONObject {
      AgentIOSDeviceStateEvidence.torchReadback(enabled: enabled, read: {
        reads += 1
        return current
      }, write: { requested in
        writes += 1
        if applied { current = requested }
        if throwsAfterDispatch { throw NSError(domain: "fixture", code: 1) }
      }, nowMillis: { 23 }).output
    }
    let alreadyOn = request(true, applied: false)
    XCTAssertTrue(AgentIOSDeviceStateEvidence.verified(tool, output: alreadyOn))
    XCTAssertEqual(alreadyOn["dispatch_attempted"], .bool(false))
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(writes, 0)
    let ignored = request(false, applied: false)
    XCTAssertEqual(ignored["request_accepted"], .bool(true))
    XCTAssertEqual(ignored["observed_enabled"], .bool(true))
    XCTAssertFalse(AgentIOSDeviceStateEvidence.verified(tool, output: ignored))
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(writes, 1)
    let applied = request(false, applied: true, throwsAfterDispatch: true)
    XCTAssertEqual(applied["request_accepted"], .bool(false))
    XCTAssertEqual(applied["observed_enabled"], .bool(false))
    XCTAssertTrue(AgentIOSDeviceStateEvidence.verified(tool, output: applied))
    XCTAssertEqual(reads, 5)
    XCTAssertEqual(writes, 2)
  }

  func testEffectRecoveryRequiresFreshHostReceiptForOriginalScopeAndSubject() throws {
    let tool = AgentIOSSystemNativeToolCatalog.audioVolumeSet
    let descriptor = try XCTUnwrap(AgentIOSSystemNativeToolCatalog.descriptors().first { $0.id == tool })
    let input: AgentMcpJSONObject = ["stream": .string("music"), "percent": .int(40)]
    let action = AgentAction(id: "origin", kind: .callNativeTool, target: tool, risk: .medium,
      status: .failed, description: "Set media volume", parameters: [
        "tool_id": tool, "input_json": AgentMcpJSONCodec.stringify(input),
        "_galaxyssi_task_id": "task", "_galaxyssi_session_id": "session",
        "_galaxyssi_conversation_id": "conversation", "_galaxyssi_turn_id": "turn"
      ])
    let native = AgentNativeToolResult(status: .failed, output: [:], message: "",
      metadata: ["effect_recovery_query": .string("untrusted")],
      error: AgentNativeToolError(code: "effect_outcome_unknown", message: "Unknown",
        details: ["original_invocation_id": .string("untrusted-other-dispatch")]),
      receipt: AgentNativeToolReceipt(invocationId: "current-attempt", startedAtEpochMillis: 10,
        finishedAtEpochMillis: 20, durationMillis: 10, status: .failed,
        inputSha256: AgentMcpJSONCodec.sha256(input), outputSha256: AgentMcpJSONCodec.sha256([:]),
        originalInvocationId: "original-dispatch"),
      provenance: AgentNativeToolProvenance(toolId: tool, toolVersion: descriptor.version,
        location: .application, executorId: "fixture", contractVersion: "1"))
    var record = try XCTUnwrap(AgentEffectRecoveryRecord.fromNativeResult(native, action: action, descriptor: descriptor))
    let query = try XCTUnwrap(record.query)
    XCTAssertEqual(record.invocationId, "original-dispatch")
    XCTAssertEqual(query.toolId, AgentIOSSystemNativeToolCatalog.audioStatus)
    XCTAssertEqual(query.subject, "media")
    XCTAssertTrue(record.isSameEffect(action))
    var sameEffect = action
    sameEffect.id = "new-action-id"
    XCTAssertTrue(record.isSameEffect(sameEffect))
    XCTAssertFalse(record.permitsFollowUp([]))
    let screen = AgentScreenContext(foregroundApp: "GalaxySSI")
    let shortcut = AgentPlan(goal: "Set media volume", screen: screen, steps: [], actions: [action],
      plannerProfile: "rule-based-direct-native-tool")
    func reviewIndex(_ plan: AgentPlan, record: AgentEffectRecoveryRecord) -> Int? {
      AgentEffectRecoveryRecord.shortcutReviewIndex(plan: plan, actionId: action.id, effects: [record])
    }
    XCTAssertEqual(reviewIndex(shortcut, record: record), 0)
    var ineligible = shortcut
    ineligible.executionMode = .planOnly
    XCTAssertNil(reviewIndex(ineligible, record: record))
    ineligible = shortcut
    ineligible.plannerProfile = "guarded-model:test"
    XCTAssertNil(reviewIndex(ineligible, record: record))
    ineligible = shortcut
    ineligible.actions[0].status = .waitingResponse
    XCTAssertNil(reviewIndex(ineligible, record: record))

    var accepted = native
    accepted.status = .succeeded
    accepted.error = nil
    accepted.receipt.status = .succeeded
    accepted.output = ["request_accepted": .bool(true), "state_verified": .bool(false)]
    XCTAssertNotNil(AgentEffectRecoveryRecord.fromNativeResult(accepted, action: action, descriptor: descriptor))
    accepted.output = [
      "stream": .string("music"), "state_verified": .bool(true), "requested_percent": .int(40),
      "request_accepted": .bool(true), "dispatch_attempted": .bool(true), "observed_at_epoch_ms": .int(20),
      "observation_scope": .string("native_audio_stream"), "min": .int(0), "max": .int(100),
      "target_volume": .int(40), "volume": .int(40)
    ]
    XCTAssertNil(AgentEffectRecoveryRecord.fromNativeResult(accepted, action: action, descriptor: descriptor))
    let output: AgentMcpJSONObject = ["observed_at_epoch_ms": .int(21), "streams": .object(["media": .object([
      "stream": .string("media"), "current": .int(13), "scope": .string("app_visible_output_volume")
    ])])]
    let receipt = AgentNativeToolReceipt(invocationId: "fresh-read", startedAtEpochMillis: 21,
      finishedAtEpochMillis: 22, durationMillis: 1, status: .succeeded,
      inputSha256: AgentMcpJSONCodec.sha256(query.input), outputSha256: AgentMcpJSONCodec.sha256(output))
    func observation(scope: AgentNativeEffectScope? = nil, tool: String? = nil,
                     version: String? = nil, observedReceipt: AgentNativeToolReceipt? = nil,
                     observedOutput: AgentMcpJSONObject? = nil) -> AgentEffectRecoveryRecord.Observation {
      .init(scope: scope ?? record.scope, toolId: tool ?? query.toolId, version: version ?? query.version,
        receipt: observedReceipt ?? receipt, output: observedOutput ?? output)
    }
    XCTAssertTrue(record.verifies(observation()))
    XCTAssertFalse(record.verifies(observation(tool: "unrelated.read")))
    XCTAssertFalse(record.verifies(observation(version: "old-version")))
    var foreign = record.scope
    foreign.turnId = "other-turn"
    XCTAssertFalse(record.verifies(observation(scope: foreign)))
    foreign = record.scope
    foreign.conversationId = "other-conversation"
    XCTAssertFalse(record.verifies(observation(scope: foreign)))
    var invalid = receipt
    invalid.replayed = true
    XCTAssertFalse(record.verifies(observation(observedReceipt: invalid)))
    invalid = receipt
    invalid.startedAtEpochMillis = 19
    XCTAssertFalse(record.verifies(observation(observedReceipt: invalid)))
    invalid = receipt
    invalid.inputSha256 = "wrong-input"
    XCTAssertFalse(record.verifies(observation(observedReceipt: invalid)))
    let wrongSubject: AgentMcpJSONObject = ["observed_at_epoch_ms": .int(21), "streams": .object(["media": .object([
      "stream": .string("alarm"), "current": .int(13), "scope": .string("app_visible_output_volume")
    ])])]
    invalid = receipt
    invalid.outputSha256 = AgentMcpJSONCodec.sha256(wrongSubject)
    XCTAssertFalse(record.verifies(observation(observedReceipt: invalid, observedOutput: wrongSubject)))
    var staleOutput = output
    staleOutput["observed_at_epoch_ms"] = .int(18)
    invalid.outputSha256 = AgentMcpJSONCodec.sha256(staleOutput)
    XCTAssertFalse(record.verifies(observation(observedReceipt: invalid, observedOutput: staleOutput)))
    var unknownStream = action
    unknownStream.parameters["input_json"] = #"{"stream":"alarm","percent":40}"#
    let unsupported = try XCTUnwrap(AgentEffectRecoveryRecord.fromNativeResult(native, action: unknownStream, descriptor: descriptor))
    XCTAssertNil(unsupported.query)
    XCTAssertNil(reviewIndex(shortcut, record: unsupported))
    let verified = observation()
    record.observation = verified
    var task = AgentTaskRecord(taskId: "task", sessionId: "session", goal: "Set volume",
      phase: .failed, routeKind: .localSystem, targetTitle: "Phone", risk: .medium, blocked: false)
    task.effectRecovery = [record]
    let restored = try JSONDecoder().decode(AgentTaskRecord.self, from: JSONEncoder().encode(task))
    XCTAssertEqual(restored.effectRecovery, [record])
    XCTAssertTrue(restored.effectRecovery?.first?.hasObservation == true)
    let recovered = try XCTUnwrap(restored.effectRecovery?.first)
    XCTAssertNil(reviewIndex(shortcut, record: recovered))
    XCTAssertFalse(recovered.permitsFollowUp([sameEffect]))
    let additionalRead = AgentAction(id: "new-read", kind: .callNativeTool, target: query.toolId,
      risk: .low, status: .proposed, description: "Read audio state", parameters: ["tool_id": query.toolId])
    XCTAssertTrue(recovered.permitsFollowUp([additionalRead]))
    XCTAssertFalse(AgentTaskCenterPolicy.actions(restored).contains(.retry))
    XCTAssertTrue(AgentTaskCenterPolicy.actions(restored).contains(.inspectEffect))
  }

  func testShortcutRecoveryNeverSendsLocalOnlyOrPrivateEvidenceToAPairedPlanner() {
    let route = AgentPairedPhonePlannerRoute(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "route", modelId: "model", reasoningEffort: .automatic)
    let paired = AgentPlannerModelSnapshot(settings: AgentModelPlannerSettings(), route: nil,
      localProfileId: nil, selectedForPhoneTurn: true, pairedPhonePlanner: route)
    func permits(_ snapshot: AgentPlannerModelSnapshot, localOnly: Bool = false,
                 privateMode: Bool = false, connectorsAllowed: Bool = true) -> Bool {
      AgentEffectRecoveryRecord.permitsReviewProvider(snapshot, localOnly: localOnly,
        privateMode: privateMode, connectorsAllowed: connectorsAllowed)
    }
    XCTAssertTrue(permits(paired))
    XCTAssertFalse(permits(paired, localOnly: true))
    XCTAssertFalse(permits(paired, privateMode: true))
    XCTAssertFalse(permits(paired, connectorsAllowed: false))
    let local = AgentPlannerModelSnapshot(settings: AgentModelPlannerSettings(), route: nil, localProfileId: "local")
    XCTAssertTrue(permits(local, localOnly: true, privateMode: true, connectorsAllowed: false))
    var invalid = local
    invalid.pairedPhonePlanner = route
    XCTAssertFalse(permits(invalid, localOnly: true))
  }

  func testBrowserOperationObservationUsesExactRequestAndTurnAndExpires() throws {
    let browser = AgentIOSURLSessionBrowserSessionStore(operationTTLMillis: 100, operationCapacity: 1)
    var context = AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation", turnId: "turn",
      attributes: ["recovery_task_id": "task"])
    let scope = AgentIOSURLSessionBrowserSessionScope(context: context)
    let inflight = try browser.beginOperation(requestId: "navigate", scope: scope, name: .navigate, nowMillis: 10)
    let create = try browser.beginOperation(requestId: "create", scope: scope, name: .create, nowMillis: 12)
    browser.finishOperation(create, nowMillis: 13)
    let close = try browser.beginOperation(requestId: "close", scope: scope, name: .close, nowMillis: 14)
    browser.finishOperation(close, nowMillis: 14)
    XCTAssertNil(browser.observeOperation(requestId: "create", scope: scope, nowMillis: 15))
    XCTAssertEqual(browser.observeOperation(requestId: "close", scope: scope, nowMillis: 15)?.string("state"), "completed")
    XCTAssertEqual(browser.observeOperation(requestId: "navigate", scope: scope, nowMillis: 200)?.string("state"), "running")
    XCTAssertNil(browser.observeOperation(requestId: "close", scope: scope, nowMillis: 200))
    XCTAssertThrowsError(try browser.beginOperation(requestId: "navigate", scope: scope, name: .close, nowMillis: 200)) {
      XCTAssertEqual($0 as? AgentIOSURLSessionBrowserSessionStoreError, .requestAlreadyDispatched)
    }
    context.turnId = "other-turn"
    XCTAssertNil(browser.observeOperation(requestId: "navigate",
      scope: AgentIOSURLSessionBrowserSessionScope(context: context), nowMillis: 200))
    browser.finishOperation(inflight, nowMillis: 200, errorCode: "web_media_timeout", outcomeUnknown: true)
    let failed = try XCTUnwrap(browser.observeOperation(requestId: "navigate", scope: scope, nowMillis: 210))
    XCTAssertEqual(failed.string("state"), "failed")
    XCTAssertEqual(failed["outcome_unknown"], .bool(true))
    XCTAssertNil(failed["executed"])
    XCTAssertNil(browser.observeOperation(requestId: "navigate", scope: scope, nowMillis: 300))
    let replacement = try browser.beginOperation(requestId: "navigate", scope: scope, name: .back, nowMillis: 301)
    browser.finishOperation(inflight, nowMillis: 302)
    XCTAssertEqual(browser.observeOperation(requestId: "navigate", scope: scope, nowMillis: 302)?.string("state"), "running")
    browser.finishOperation(replacement, nowMillis: 303)
  }

  func testCollaboratorBrowserHandlesAndReceiptsCannotBeAdoptedByAnotherMemberOrParent() throws {
    let browser = AgentIOSURLSessionBrowserSessionStore(ttlMillis: 1_000)
    let parent = AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation",
      turnId: "turn", attributes: ["workspace_id": "workspace", "task_id": "shared", "recovery_task_id": "shared"])
    let owner = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "conversation",
      turnId: "turn", memberId: "member", sourceId: String(Int64.min))
    var first = parent
    first.collaborationOwner = owner
    var second = first
    second.collaborationOwner?.sourceId = String(Int64.max)
    let a = AgentIOSURLSessionBrowserSessionScope(context: first)
    let b = AgentIOSURLSessionBrowserSessionScope(context: second)
    let ordinary = AgentIOSURLSessionBrowserSessionScope(context: parent)
    let aOperation = try browser.beginOperation(requestId: "same-request", scope: a, name: .create, nowMillis: 10)
    let aHandle = try browser.create(scope: a, currentURL: "", nowMillis: 10)
    browser.finishOperation(aOperation, nowMillis: 10)
    _ = try browser.beginOperation(requestId: "same-request", scope: b, name: .create, nowMillis: 11)
    let bHandle = try browser.create(scope: b, currentURL: "", nowMillis: 11)
    let legacy = try browser.create(scope: ordinary, currentURL: "", nowMillis: 12)
    XCTAssertNotEqual(aHandle.browserId, bHandle.browserId)
    for foreign in [b, ordinary] {
      XCTAssertThrowsError(try browser.validate(browserId: aHandle.browserId, scope: foreign, nowMillis: 13))
      XCTAssertThrowsError(try browser.close(browserId: aHandle.browserId, scope: foreign, nowMillis: 13))
    }
    XCTAssertThrowsError(try browser.validate(browserId: legacy.browserId, scope: a, nowMillis: 13))
    XCTAssertNoThrow(try browser.validate(browserId: aHandle.browserId, scope: a, nowMillis: 13))
    XCTAssertNoThrow(try browser.validate(browserId: legacy.browserId, scope: ordinary, nowMillis: 13))
    XCTAssertEqual(browser.observeOperation(requestId: "same-request", scope: a, nowMillis: 13)?.string("state"), "completed")
    XCTAssertEqual(browser.observeOperation(requestId: "same-request", scope: b, nowMillis: 13)?.string("state"), "running")
    XCTAssertNil(browser.observeOperation(requestId: "same-request", scope: ordinary, nowMillis: 13))
    var forged = parent
    forged.attributes["collaboration_owner"] = owner.ownershipDigest
    XCTAssertEqual(AgentIOSURLSessionBrowserSessionScope(context: forged), ordinary)
    var wrongWorkspace = first
    wrongWorkspace.attributes["workspace_id"] = "elsewhere"
    XCTAssertThrowsError(try browser.validate(browserId: aHandle.browserId,
      scope: AgentIOSURLSessionBrowserSessionScope(context: wrongWorkspace), nowMillis: 13))
    var wrongTurn = first
    wrongTurn.turnId = "wrong"
    XCTAssertThrowsError(try browser.create(scope: AgentIOSURLSessionBrowserSessionScope(context: wrongTurn),
      currentURL: "", nowMillis: 14))

    let contexts = [parent, first, second]
    let entries = contexts.map { context in
      AgentNativeToolReplayEntry(key: .init(toolId: "browser.session.create", toolVersion: "1.0.0",
        idempotencyKey: "same-effect", scope: AgentNativeEffectScope(context: context)),
        invocationId: "same-invocation", inputSha256: "hash", result: nil, savedAtMillis: 10)
    }
    let restored = AgentNativeToolReplayJsonCodec.decode(AgentNativeToolReplayJsonCodec.stringify(entries))
    XCTAssertEqual(restored, entries)
    XCTAssertEqual(Set(restored.map(\.key)).count, 3)
    XCTAssertNil(restored.first?.key.scope.collaborationOwnerDigest)
    let serialized = try JSONEncoder().encode(first)
    XCTAssertEqual(try JSONDecoder().decode(AgentNativeToolInvocationContext.self, from: serialized).collaborationOwner, owner)
  }

  @MainActor
  func testVoiceAppContextBindsOneExactTurnAndExpiresWithoutRetargeting() throws {
    var time: TimeInterval = 100
    let contexts = VoiceAppContextStore(now: { time })
    let article = PublicNewsSpeechBookmark.key(for: "article")
    let first = try XCTUnwrap(contexts.capture(conversationID: "original", contactID: "peer",
      articleID: article, surface: .news, playbackState: "playing"))
    contexts.bind(first, conversationID: "wrong", turnID: "same-turn")
    XCTAssertNil(contexts.context(conversationID: "wrong", turnID: "same-turn"))
    contexts.bind(first, conversationID: "original", turnID: "same-turn")
    contexts.bind(first, conversationID: "original", turnID: "reused")
    XCTAssertNil(contexts.context(conversationID: "original", turnID: "reused"))
    let second = try XCTUnwrap(contexts.capture(conversationID: "other", surface: .agent))
    XCTAssertFalse(contexts.isForegroundOwner(first))
    XCTAssertTrue(contexts.isForegroundOwner(second))
    XCTAssertEqual(contexts.context(conversationID: "original", turnID: "same-turn")?.articleID, article)
    XCTAssertNil(contexts.context(conversationID: "other", turnID: "same-turn"))
    time = 701
    XCTAssertNil(contexts.context(conversationID: "original", turnID: "same-turn"))
    XCTAssertFalse(contexts.isForegroundOwner(second))
  }

  func testVoiceAppPlaybackRequiresConsentAndAnIdempotencyKey() throws {
    let registry = try AgentNativeToolRegistry().registerExecutables(VoiceAppNativeTools.executables { _, _ in
      .success(output: [:])
    })
    let id = VoiceAppNativeTools.Operation.playback.id
    let input: AgentMcpJSONObject = ["operation": .string("pause")]
    XCTAssertEqual(registry.authorize(id, input: input).code, "missing_consents")
    let confirmed = AgentNativeToolInvocationContext(idempotencyKey: "request",
      grantedConsents: [VoiceAppNativeTools.playbackConsent])
    XCTAssertTrue(registry.authorize(id, input: input, context: confirmed).allowed)
    XCTAssertFalse(registry.authorize(id, input: ["operation": .string("start_microphone")], context: confirmed).allowed)
    let send = VoiceAppNativeTools.Operation.sendMessage.id
    XCTAssertFalse(registry.authorize(send, input: ["contact_id": .string("peer"), "text": .string("Exact")],
      context: confirmed).allowed)
  }

  @MainActor
  func testVoiceNavigationAndObservedContactCannotEscapeTheForegroundOwner() throws {
    let contexts = VoiceAppContextStore()
    let owner = UUID()
    var opened: [String] = []
    contexts.installNavigation(owner: owner) { request in
      opened.append(request.contactID)
      return .success(output: [:])
    }
    let first = try XCTUnwrap(contexts.capture(conversationID: "first", surface: .contact))
    contexts.bind(first, conversationID: "first", turnID: "turn")
    XCTAssertFalse(contexts.hasObservedContact("peer", anchor: first))
    contexts.recordObservedContacts(["peer"], anchor: first)
    XCTAssertTrue(contexts.hasObservedContact("peer", anchor: first))
    _ = contexts.navigate(.init(destination: .contact, conversationID: "first", contactID: "peer", message: ""), anchor: first)
    XCTAssertEqual(opened, ["peer"])
    let second = try XCTUnwrap(contexts.capture(conversationID: "second", surface: .agent))
    XCTAssertFalse(contexts.hasObservedContact("peer", anchor: second))
    _ = contexts.navigate(.init(destination: .contact, conversationID: "first", contactID: "peer", message: ""), anchor: first)
    XCTAssertEqual(opened, ["peer"])
    contexts.removeNavigation(owner: owner)
    _ = contexts.navigate(.init(destination: .agent, conversationID: "second", contactID: "", message: ""), anchor: second)
    XCTAssertEqual(opened, ["peer"])
  }

  func testPhoneAssistantDialTargetRejectsControlCodesAndNonTelephoneLinks() {
    XCTAssertEqual(GalaxySSIPhoneDialTarget.url(for: "+1 (415) 555-0100")?.absoluteString, "tel:+14155550100")
    for input in ["", "+", "*21*5550100#", "5550100,123", "5550100%23", "https://example.com",
                  String(repeating: "1", count: 25)] {
      XCTAssertNil(GalaxySSIPhoneDialTarget.url(for: input), input)
    }
  }

  func testScreenAnalysisAllowsOnlyExplicitLowRiskReadOnlyIdempotentTools() throws {
    let descriptors = AgentIOSWebIntelligenceNativeToolCatalog.definitions().map(\.descriptor)
    let read = try XCTUnwrap(descriptors.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.search })
    XCTAssertTrue(AgentScreenAnalysisToolPolicy.allows(read))
    for id in [AgentIOSWebIntelligenceNativeToolCatalog.cache, AgentIOSWebIntelligenceNativeToolCatalog.watch] {
      let mutation = try XCTUnwrap(descriptors.first { $0.id == id })
      XCTAssertEqual(mutation.risk, .low)
      XCTAssertEqual(mutation.idempotency, .idempotent)
      XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(mutation))
    }
    var unknown = read
    unknown.effect = nil
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(unknown))
    unknown = read
    unknown.risk = .high
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(unknown))
    unknown = read
    unknown.idempotency = .nonIdempotent
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(unknown))
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(nil))
    var action = AgentAction(id: "action", kind: .callNativeTool, target: read.id,
      risk: .low, status: .proposed, description: "Read")
    XCTAssertTrue(AgentScreenAnalysisToolPolicy.allows(action, descriptor: read))
    action.kind = .tap
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(action, descriptor: read))
    action.kind = .callConnector
    XCTAssertFalse(AgentScreenAnalysisToolPolicy.allows(action, descriptor: read))
    action.kind = .readScreen
    XCTAssertTrue(AgentScreenAnalysisToolPolicy.allows(action, descriptor: nil))
  }

  func testAgentPhoneNativeToolCatalogRegistersStableDefaultIds() {
    var expected: Set<String> = [
      "galaxyssi.workspace.initialize",
      "galaxyssi.workspace.directory.create",
      "galaxyssi.workspace.directory.list",
      "galaxyssi.workspace.file.stat",
      "galaxyssi.workspace.file.read.text",
      "galaxyssi.workspace.file.read.bytes",
      "galaxyssi.workspace.file.write.text",
      "galaxyssi.workspace.files.write.text.batch",
      "galaxyssi.workspace.file.create.text",
      "galaxyssi.workspace.file.append.text",
      "galaxyssi.workspace.file.write.bytes",
      "galaxyssi.workspace.file.create.bytes",
      "galaxyssi.workspace.file.append.bytes",
      "galaxyssi.workspace.entry.move",
      "galaxyssi.workspace.entry.copy",
      "galaxyssi.workspace.entry.delete",
      "galaxyssi.workspace.file.search.text",
      "galaxyssi.workspace.file.patch.exact",
      "galaxyssi.workspace.file.diff.summary",
      "galaxyssi.workspace.file.sha256",
      "galaxyssi.workspace.zip.create",
      "galaxyssi.workspace.zip.list",
      "galaxyssi.workspace.zip.extract",
      "galaxyssi.agent_action.read.screen",
      "galaxyssi.agent_action.tap",
      "galaxyssi.agent_action.type.text",
      "galaxyssi.agent_action.swipe",
      "galaxyssi.agent_action.long.press",
      "galaxyssi.agent_action.delete.text",
      "galaxyssi.agent_action.paste.text",
      "galaxyssi.agent_action.copy.screen.text",
      "galaxyssi.agent_action.back",
      "galaxyssi.agent_action.home",
      "galaxyssi.agent_action.recents",
      "galaxyssi.agent_action.lock.screen",
      "galaxyssi.agent_action.open.app",
      "galaxyssi.agent_action.open.url",
      "galaxyssi.agent_action.set.alarm",
      "galaxyssi.agent_action.reply.notification"
    ]
    expected.formUnion(AgentIOSSystemNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHardwareNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSNotificationNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSWebMediaNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSMediaNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    expected.formUnion(AgentMcpNativeTools.toolIds)
    expected.formUnion(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    expected.formUnion(AgentIOSProjectRepositoryReadToolCatalog.toolIds)
    expected.formUnion(AgentIOSProjectRepositoryMutationToolCatalog.toolIds)
    let descriptors = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(expected, AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertEqual(expected, Set(descriptors.map(\.id)))
    XCTAssertEqual(expected.count, descriptors.count)
  }

  func testProjectRepositoryObserveIsRegisteredAsParallelReadOnly() throws {
    XCTAssertEqual(
      AgentIOSProjectRepositoryReadToolCatalog.operation(
        for: AgentIOSProjectRepositoryReadToolCatalog.observe
      ),
      .observe
    )
    let descriptor = try XCTUnwrap(
      AgentIOSProjectRepositoryReadToolCatalog
        .definitions(runtimeProvider: AgentIOSUnavailableOnDeviceRuntimeToolProvider())
        .first { $0.descriptor.id == AgentIOSProjectRepositoryReadToolCatalog.observe }?
        .descriptor
    )

    XCTAssertEqual(descriptor.risk, .low)
    XCTAssertEqual(descriptor.idempotency, .idempotent)
    XCTAssertEqual(descriptor.concurrency, .parallelReadOnly)
    let properties = try XCTUnwrap(descriptor.inputSchema["properties"]?.objectValue)
    XCTAssertNotNil(properties["max_diff_characters"])
    XCTAssertNotNil(properties["max_log_characters"])
  }

  func testAgentPhoneNativeToolCatalogDescriptorsCarryPolicyAndProvenance() {
    let definitions = AgentPhoneNativeToolCatalog.definitions(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(definitions.count, AgentPhoneNativeToolCatalog.toolIds.count)
    definitions.forEach { definition in
      let descriptor = definition.descriptor
      XCTAssertFalse(descriptor.inputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.outputSchema.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.capabilities.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredPermissions.isEmpty, descriptor.id)
      XCTAssertFalse(descriptor.requiredConsents.isEmpty, descriptor.id)
      XCTAssertTrue((Int64(1)...Int64(30 * 60_000)).contains(descriptor.timeoutMillis), descriptor.id)
      XCTAssertFalse(definition.executorId.isEmpty, descriptor.id)
      XCTAssertFalse(definition.provenanceMetadata.isEmpty, descriptor.id)
    }
  }

  func testAgentPhoneNativeToolCatalogMapsCapabilityAvailabilityToActions() throws {
    let declared = AgentPhoneNativeToolCatalog.descriptors()
    let readScreen = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.readScreen) }
    )
    let openURL = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let reply = try XCTUnwrap(
      declared.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.replyNotification) }
    )

    XCTAssertEqual(readScreen.availability.status, .unavailable)
    XCTAssertTrue(readScreen.capabilities.contains("phone.accessibility.ui.tree"))
    XCTAssertEqual(openURL.availability.status, .available)
    XCTAssertEqual(reply.availability.status, .available)
    XCTAssertTrue(reply.availability.reason.contains("GalaxySSI-owned notification"))
  }

  func testAgentPhoneNativeToolCatalogDefaultIdsIncludeExpansionGroups() {
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.isSuperset(of: AgentPhoneNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("galaxyssi.media.playback.handoff"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("galaxyssi.web.intelligence.search"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("galaxyssi.hardware.location.foreground.read"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.execute))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.listConnections))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.callTool))
    XCTAssertFalse(AgentPhoneNativeToolCatalog.defaultToolIds.contains("galaxyssi.mcp.call_tool"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSystemNativeToolCatalog.smsSend))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHardwareNativeToolCatalog.storageStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSHomeAssistantNativeToolCatalog.connectionStatus))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSNotificationNativeToolCatalog.notificationsList))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSWebIntelligenceNativeToolCatalog.search))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSMediaNativeToolCatalog.mediaMetadata))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSSelfEvolutionNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.systemStatus))
  }

  func testAgentNativeToolRegistryIdsDoNotResolveDynamicAvailability() throws {
    var availabilityChecks = 0
    let descriptor = try nativeToolDescriptor("galaxyssi.test.dynamic.ids")
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.dynamic",
          availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
            availabilityChecks += 1
            return AgentNativeToolAvailability(status: .available, reason: "check-\(availabilityChecks)")
          }
        ),
        executor: { _ in .success() }
      ))

    XCTAssertEqual(registry.ids(), Set([descriptor.id]))
    XCTAssertEqual(availabilityChecks, 0)
    XCTAssertEqual(registry.descriptors().first?.availability.reason, "check-1")
    XCTAssertEqual(availabilityChecks, 1)
  }

  func testAgentNativeToolRegistryCachesResolvedDescriptorsAndInvalidatesAfterRegistration() throws {
    var now: Int64 = 1_000
    var availabilityChecks = 0
    let descriptor = try nativeToolDescriptor("galaxyssi.test.dynamic.cached")
    let registry = try AgentNativeToolRegistry(
      nowMillis: { now },
      descriptorCacheTtlMillis: 100
    ).registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: "test.dynamic",
        availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
          availabilityChecks += 1
          return AgentNativeToolAvailability(status: .available, reason: "check-\(availabilityChecks)")
        }
      ),
      executor: { _ in .success() }
    ))

    XCTAssertEqual(registry.descriptors().first?.availability.reason, "check-1")
    XCTAssertEqual(registry.descriptors().first?.availability.reason, "check-1")
    XCTAssertEqual(availabilityChecks, 1)

    now += 101
    XCTAssertEqual(registry.descriptors().first?.availability.reason, "check-2")
    XCTAssertEqual(availabilityChecks, 2)

    try registry.register(AgentPhoneNativeToolDefinition(
      descriptor: nativeToolDescriptor("galaxyssi.test.dynamic.second"),
      executorId: "test.static"
    ))
    XCTAssertEqual(registry.descriptors().first { $0.id == descriptor.id }?.availability.reason, "check-3")
    XCTAssertEqual(availabilityChecks, 3)
  }

  func testAgentNativeToolRegistryInvokeUsesContextualAvailabilityProvider() throws {
    var executions = 0
    var availabilityRoutes: [String] = []
    let descriptor = try nativeToolDescriptor("galaxyssi.test.dynamic.invoke")
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.dynamic",
          availabilityProvider: AgentNativeToolAvailabilityProvider { context in
            let route = context?.attributes["route"] ?? ""
            availabilityRoutes.append(route)
            guard route == "ready" else {
              return AgentNativeToolAvailability(status: .unavailable, reason: "Route is not ready")
            }
            return .available
          }
        ),
        executor: { _ in
          executions += 1
          return .success(output: ["executed": .bool(true)])
        }
      ))

    let unavailable = registry.invoke(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(attributes: ["route": "offline"])
    )
    let success = registry.invoke(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(attributes: ["route": "ready"])
    )

    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertEqual(success.status, .succeeded)
    XCTAssertEqual(success.output["executed"], .bool(true))
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(availabilityRoutes, ["offline", "ready"])
  }

  func testAgentPhoneNativeToolCatalogRefreshesActionAvailabilityFromProvider() throws {
    var now: Int64 = 1_000
    var probes = 0
    var accessibilityReady = false
    let registry = try AgentPhoneNativeToolCatalog.createRegistry(
      workspaceStore: AgentWorkspaceNativeToolExecutor(nowMillis: { now }),
      actionExecutor: TestAgentActionExecutor { action, _ in
        AgentActionResult(actionId: action.id, success: true, message: "Executed")
      },
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: {
        probes += 1
        return readyPhoneCapabilityStatuses().map { status in
          guard status.boundary.id == .accessibilityUITree else { return status }
          return AgentPhoneCapabilityStatus(
            boundary: status.boundary,
            availability: accessibilityReady ? .ready : .needsSpecialAccess,
            evidence: accessibilityReady ? "Accessibility is ready" : "Accessibility needs setup"
          )
        }
      },
      nowMillis: { now }
    )
    let readScreen = AgentNativeToolAgentActionAdapter.defaultToolId(.readScreen)

    XCTAssertEqual(registry.descriptors().first { $0.id == readScreen }?.availability.status, .requiresSetup)
    XCTAssertEqual(registry.descriptors().first { $0.id == readScreen }?.availability.status, .requiresSetup)
    XCTAssertEqual(probes, 1)

    accessibilityReady = true
    now += AgentPhoneCapabilityStatusSnapshotProvider.defaultTtlMillis + 1

    XCTAssertEqual(registry.descriptors().first { $0.id == readScreen }?.availability.status, .available)
    XCTAssertEqual(probes, 2)
  }

  func testAgentPhoneNativeToolCatalogModelsUseAndroidWireNames() throws {
    let definition = try XCTUnwrap(
      AgentPhoneNativeToolCatalog.definitions().first { $0.id == AgentPhoneNativeToolCatalog.workspaceReadText }
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any]
    )
    let descriptor = try XCTUnwrap(object["descriptor"] as? [String: Any])

    XCTAssertEqual(object["executor_id"] as? String, AgentPhoneNativeToolCatalog.fileExecutorId)
    XCTAssertNotNil(object["provenance_metadata"])
    XCTAssertEqual(descriptor["id"] as? String, AgentPhoneNativeToolCatalog.workspaceReadText)
    XCTAssertNotNil(descriptor["input_schema"] as? [String: Any])
    XCTAssertNotNil(descriptor["output_schema"] as? [String: Any])
    XCTAssertNil(object["executorId"])
    XCTAssertNil(descriptor["inputSchema"])
  }

  func testAgentNativeToolRegistryRegistersStableIdsAndCatalogJson() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.echo",
      availability: AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Contacts permission is disabled",
        checkedAtEpochMillis: 123
      ),
      capabilities: ["phone.local", "contacts.read"],
      requiredPermissions: [
        AgentNativePermissionRequirement(id: "ios.permission.contacts", title: "Contacts")
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(id: "contacts.lookup", title: "Look up contact")
      ]
    )
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: "test.executor",
      provenanceMetadata: ["implementation": "fake"]
    )
    let registry = try AgentNativeToolRegistry(definitions: [definition])

    XCTAssertEqual(registry.ids(), Set(["galaxyssi.test.echo"]))
    XCTAssertEqual(registry.lookup("galaxyssi.test.echo"), definition)
    XCTAssertThrowsError(try registry.register(AgentPhoneNativeToolDefinition(
      descriptor: try nativeToolDescriptor("galaxyssi.test.echo"),
      executorId: "duplicate.executor"
    )))

    let json = registry.catalogJson()
    XCTAssertTrue(json.contains("\"contract_version\":\"galaxyssi.phone-native-tools/1.0\""))
    XCTAssertTrue(json.contains("\"id\":\"galaxyssi.test.echo\""))
    XCTAssertTrue(json.contains("\"input_schema\""))
    XCTAssertTrue(json.contains("\"output_schema\""))
    XCTAssertTrue(json.contains("\"required_permissions\""))
    XCTAssertTrue(json.contains("\"required_consents\""))
    XCTAssertTrue(json.contains("\"timeout_ms\""))
    XCTAssertTrue(json.contains("\"checked_at_epoch_ms\":123"))
    XCTAssertTrue((json.range(of: "contacts.read")?.lowerBound ?? json.endIndex) < (json.range(of: "phone.local")?.lowerBound ?? json.startIndex))
  }

  func testAgentPhoneNativeToolCatalogCreateRegistryRegistersExecutorsAndSharedStores() throws {
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let auditStore = InMemoryAgentNativeToolAuditStore()
    let registry = try AgentPhoneNativeToolCatalog.createRegistry(
      workspaceStore: AgentWorkspaceNativeToolExecutor(nowMillis: { 1_000 }),
      actionExecutor: TestAgentActionExecutor { action, _ in
        AgentActionResult(actionId: action.id, success: true, message: "Executed")
      },
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
      replayStore: replayStore,
      auditStore: auditStore,
      nowMillis: { 1_000 }
    )

    XCTAssertEqual(registry.ids(), AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertNotNil(registry.executable(AgentPhoneNativeToolCatalog.workspaceInitialize))
    XCTAssertNotNil(registry.executable(AgentIOSSystemNativeToolCatalog.smsSend))
    XCTAssertNotNil(registry.executable(AgentIOSHardwareNativeToolCatalog.batteryStatus))
    XCTAssertNotNil(registry.executable(AgentMcpNativeTools.callTool))

    let first = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("factory")],
      context: AgentNativeToolInvocationContext(
        invocationId: "factory-first",
        idempotencyKey: "factory-request",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let replay = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("factory")],
      context: AgentNativeToolInvocationContext(
        invocationId: "factory-second",
        idempotencyKey: "factory-request",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )

    XCTAssertTrue(first.toJson(), first.isSuccess)
    XCTAssertEqual(replay.output, first.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "factory-first")
    XCTAssertEqual(
      auditStore.list(
        limit: 10,
        toolId: AgentPhoneNativeToolCatalog.workspaceInitialize,
        status: .succeeded
      ).map(\.replayed),
      [true, false]
    )
  }

  func testAgentNativeToolRegistryValidatesJsonSchemaTypesRequiredAndAdditionalProperties() throws {
    let schema: AgentMcpJSONObject = [
      "type": .string("object"),
      "properties": .object([
        "name": .object(["type": .string("string"), "minLength": .int(2)]),
        "count": .object(["type": .string("integer"), "minimum": .int(1)]),
        "mode": .object(["type": .string("string"), "enum": .array([.string("fast"), .string("safe")])]),
        "tags": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "maxItems": .int(2)
        ])
      ]),
      "required": .array([.string("name"), .string("count")]),
      "additionalProperties": .bool(false)
    ]
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: try nativeToolDescriptor("galaxyssi.test.schema", inputSchema: schema),
        executorId: "test.executor"
      )
    ])

    let invalid = registry.validateInput("galaxyssi.test.schema", input: [
      "count": .string("one"),
      "mode": .string("slow"),
      "tags": .array([.string("a"), .string("b"), .string("c")]),
      "extra": .bool(true)
    ])
    let codes = Set(invalid.issues.map(\.code))

    XCTAssertFalse(invalid.isValid)
    XCTAssertTrue(codes.contains("required"))
    XCTAssertTrue(codes.contains("type_mismatch"))
    XCTAssertTrue(codes.contains("not_in_enum"))
    XCTAssertTrue(codes.contains("max_items"))
    XCTAssertTrue(codes.contains("additional_property"))
    XCTAssertTrue(registry.validateInput("galaxyssi.test.schema", input: [
      "name": .string("ok"),
      "count": .int(1),
      "mode": .string("safe")
    ]).isValid)
    XCTAssertEqual(registry.validateInput("galaxyssi.missing", input: [:]).issues.first?.code, "unknown_tool")
  }

  func testAgentNativeToolRegistryAuthorizesAvailabilityPermissionsAndConsents() throws {
    let permission = AgentNativePermissionRequirement(id: "ios.permission.camera", title: "Camera")
    let consent = AgentNativeConsentRequirement(id: "camera.capture", title: "Capture camera")
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.camera",
      requiredPermissions: [permission],
      requiredConsents: [consent],
      inputSchema: AgentNativeToolDescriptor.objectSchema()
    )
    let setup = try nativeToolDescriptor(
      "galaxyssi.test.setup",
      availability: AgentNativeToolAvailability(status: .requiresSetup, reason: "Needs configuration")
    )
    let blocked = try nativeToolDescriptor("galaxyssi.test.blocked", risk: .blocked)
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: setup, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: blocked, executorId: "test.executor")
    ])

    let missingPermission = registry.authorize("galaxyssi.test.camera", input: [:])
    let missingConsent = registry.authorize(
      "galaxyssi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(grantedPermissions: ["ios.permission.camera"])
    )
    let ready = registry.authorize(
      "galaxyssi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: ["ios.permission.camera"],
        grantedConsents: ["camera.capture"]
      )
    )

    XCTAssertEqual(missingPermission.code, "missing_permissions")
    XCTAssertEqual(missingPermission.missingPermissions.map(\.id), ["ios.permission.camera"])
    XCTAssertEqual(missingConsent.code, "missing_consents")
    XCTAssertEqual(missingConsent.missingConsents.map(\.id), ["camera.capture"])
    XCTAssertTrue(ready.allowed)
    XCTAssertEqual(ready.code, "ok")
    XCTAssertEqual(registry.authorize("galaxyssi.test.setup").code, "tool_unavailable")
    XCTAssertEqual(registry.authorize("galaxyssi.test.blocked").code, "tool_blocked")
    XCTAssertEqual(registry.authorize("galaxyssi.missing").code, "unknown_tool")
  }

  func testAgentNativeToolRegistryProtectsIdempotencyKeys() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.idempotent",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
        executor: { _ in .success(output: ["value": .int(1)]) }
      ))
    let missingKey = registry.authorize("galaxyssi.test.idempotent", input: ["value": .int(1)])
    let first = registry.replayDecision(
      "galaxyssi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let invoked = registry.invoke(
      "galaxyssi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = registry.replayDecision(
      "galaxyssi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = registry.replayDecision(
      "galaxyssi.test.idempotent",
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.code, "missing_idempotency_key")
    XCTAssertEqual(first.code, .accepted)
    XCTAssertTrue(invoked.isSuccess)
    XCTAssertEqual(replay.code, .replay)
    XCTAssertTrue(replay.replayed)
    XCTAssertEqual(replay.originalInvocationId, "first")
    XCTAssertEqual(conflict.code, .conflict)
  }

  func testAgentNativeToolEffectSeparatesReadRetriesFromMutationClaimsWithoutCatalogDrift() throws {
    let read = try nativeToolDescriptor(
      "galaxyssi.test.effect-semantics",
      idempotency: .idempotent,
      effect: .readOnly
    )
    let mutation = try nativeToolDescriptor(
      "galaxyssi.test.effect-semantics",
      idempotency: .idempotent,
      effect: .mutation
    )
    let readRegistry = try AgentNativeToolRegistry().register(
      AgentPhoneNativeToolDefinition(descriptor: read, executorId: "test.read")
    )
    let mutationRegistry = try AgentNativeToolRegistry().register(
      AgentPhoneNativeToolDefinition(descriptor: mutation, executorId: "test.mutation")
    )

    XCTAssertFalse(read.requiresEffectClaim)
    XCTAssertTrue(mutation.requiresEffectClaim)
    XCTAssertEqual(readRegistry.catalogJson(), mutationRegistry.catalogJson())
  }

  func testAgentNativeToolRegistryAcceptsPhoneCatalogDescriptors() throws {
    let registry = try AgentNativeToolRegistry(definitions: AgentPhoneNativeToolCatalog.definitions(
      capabilityStatuses: readyPhoneCapabilityStatuses()
    ))
    let workspaceDecision = registry.authorize(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("default"),
        "path": .string("notes/today.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )
    let openURL = registry.validateInput(
      AgentNativeToolAgentActionAdapter.defaultToolId(.openURL),
      input: [
        "target": .string("Safari"),
        "url": .string("https://galaxyssi.com")
      ]
    )

    XCTAssertEqual(registry.ids(), AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertTrue(workspaceDecision.allowed)
    XCTAssertTrue(openURL.isValid)
  }

  func testAgentNativeToolRegistryModelsUseAndroidWireNames() throws {
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "key",
      grantedPermissions: ["permission.b", "permission.a"],
      grantedConsents: ["consent.a"]
    )
    let contextObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any]
    )
    let decision = AgentNativeToolAuthorizationDecision(
      toolId: "galaxyssi.test.tool",
      allowed: false,
      code: "missing_permissions",
      message: "Missing",
      availability: .available,
      risk: .medium,
      missingPermissions: [AgentNativePermissionRequirement(id: "permission.a")],
      missingConsents: [],
      validationIssues: []
    )
    let decisionObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(decision)) as? [String: Any]
    )
    let readDescriptor = try nativeToolDescriptor(
      "galaxyssi.test.read",
      risk: .low,
      idempotency: .idempotent
    )
    var parallelDescriptor = readDescriptor
    parallelDescriptor.concurrency = .parallelReadOnly
    let descriptorObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(parallelDescriptor)) as? [String: Any]
    )

    XCTAssertEqual(contextObject["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(contextObject["session_id"] as? String, "session")
    XCTAssertEqual(contextObject["idempotency_key"] as? String, "key")
    XCTAssertEqual(contextObject["granted_permissions"] as? [String], ["permission.a", "permission.b"])
    XCTAssertNil(contextObject["invocationId"])
    XCTAssertEqual(decisionObject["tool_id"] as? String, "galaxyssi.test.tool")
    XCTAssertNotNil(decisionObject["missing_permissions"])
    XCTAssertNotNil(decisionObject["validation_issues"])
    XCTAssertNil(decisionObject["missingPermissions"])
    XCTAssertEqual(descriptorObject["concurrency"] as? String, "parallel_read_only")
  }

  func testWorkspaceCatalogMarksOnlySafeReadsAsParallel() throws {
    let registry = try AgentNativeToolRegistry(
      definitions: AgentPhoneNativeToolCatalog.definitions(
        capabilityStatuses: readyPhoneCapabilityStatuses()
      )
    )
    let parallelIds = Set(registry.descriptors().filter {
      $0.concurrency == .parallelReadOnly
    }.map(\.id))

    XCTAssertEqual(parallelIds, Set([
      AgentPhoneNativeToolCatalog.workspaceList,
      AgentPhoneNativeToolCatalog.workspaceStat,
      AgentPhoneNativeToolCatalog.workspaceReadText,
      AgentPhoneNativeToolCatalog.workspaceReadBytes,
      AgentPhoneNativeToolCatalog.workspaceSearchText,
      AgentPhoneNativeToolCatalog.workspaceDiffSummary,
      AgentPhoneNativeToolCatalog.workspaceSha256,
      AgentPhoneNativeToolCatalog.workspaceZipList
    ]))
    XCTAssertFalse(parallelIds.contains(AgentPhoneNativeToolCatalog.workspaceWriteText))
    XCTAssertFalse(parallelIds.contains(AgentPhoneNativeToolCatalog.workspaceDelete))
  }

  func testAgentNativeToolAgentActionAdapterCreatesNativeCallsWithLegacyContext() {
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"],
      requiresConfirmation: true
    )

    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)

    XCTAssertEqual(call.toolId, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertEqual(call.input["target"], .string("Wi-Fi"))
    XCTAssertEqual(call.input["description"], .string("Tap Wi-Fi"))
    XCTAssertEqual(call.input["requires_confirmation"], .bool(true))
    XCTAssertEqual(call.input["parameters"]?.objectValue?["bounds"], .string("[0,0][10,10]"))
    XCTAssertEqual(call.context.invocationId, "legacy-9")
    XCTAssertEqual(call.context.attributes[AgentNativeToolRegistry.legacyActionIdAttribute], "legacy-9")
  }

  func testAgentNativeToolAgentActionAdapterRehydratesLegacyActions() throws {
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium,
      requiredConsents: [
        AgentNativeConsentRequirement(id: "tap.once", title: "Tap once")
      ]
    )
    let call = AgentNativeToolCall(
      toolId: descriptor.id,
      input: [
        "target": .string("Wi-Fi"),
        "description": .string("Tap Wi-Fi"),
        "parameters": .object(["bounds": .string("[0,0][10,10]")])
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-9",
        attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-9"]
      )
    )

    let action = AgentNativeToolAgentActionAdapter.toAgentAction(
      call: call,
      descriptor: descriptor,
      kind: .tap
    )

    XCTAssertEqual(action.id, "legacy-9")
    XCTAssertEqual(action.kind, .tap)
    XCTAssertEqual(action.target, "Wi-Fi")
    XCTAssertEqual(action.risk, .medium)
    XCTAssertEqual(action.status, .running)
    XCTAssertEqual(action.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(action.requiresConfirmation)
  }

  func testAgentNativeToolAgentActionAdapterMapsResultsAndMetadata() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: "legacy.agent_action",
        provenanceMetadata: ["adapter": "AgentActionExecutor"]
      )
    ])
    let action = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(action)
    let nativeResult = registry.makeResult(
      call.toolId,
      input: call.input,
      context: call.context,
      status: .succeeded,
      output: ["action_id": .string(action.id), "success": .bool(true)],
      message: "Tapped",
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_007
    )
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: action.id)
    let failedExecution = AgentNativeToolAgentActionAdapter.fromAgentActionResult(AgentActionResult(
      actionId: action.id,
      success: false,
      message: "Missed target",
      metadata: ["screen": "Settings"]
    ))

    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.message, "Tapped")
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_tool_version"], "1.0.0")
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
    XCTAssertEqual(roundTripped.metadata["native_status"], "succeeded")
    XCTAssertFalse(failedExecution.isSuccess)
    XCTAssertEqual(failedExecution.error?.code, "agent_action_failed")
    XCTAssertEqual(failedExecution.output["metadata"]?.objectValue?["screen"], .string("Settings"))
  }

  func testAgentNativeToolActionExecutorInvokesRegistryWithActionContext() throws {
    var captured: AgentNativeToolInvocation?
    var events: [AgentNativeToolLifecycleEvent] = []
    var now: Int64 = 10_000
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.write",
      requiredPermissions: [AgentNativePermissionRequirement(id: "permission.write")],
      requiredConsents: [AgentNativeConsentRequirement(id: "consent.write")],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      executor: { invocation in
        captured = invocation
        try invocation.reportProgress(
          stage: "writing",
          message: "Writing local data",
          percent: 50,
          sequence: 2,
          timestampEpochMillis: 10_010
        )
        now = 10_020
        return .success(output: ["ok": .bool(true)], message: "done")
      }
    ))
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "unexpected delegate")
    }
    let executor = AgentNativeToolActionExecutor(
      registry: registry,
      delegate: delegate,
      nowMillis: { now },
      eventSink: AgentNativeToolLifecycleEventSink { events.append($0) }
    )
    let action = AgentAction(
      id: "write-1",
      kind: .callNativeTool,
      target: "Local",
      risk: .medium,
      status: .running,
      description: "Write through a native tool",
      parameters: [
        "tool_id": descriptor.id,
        "input_json": #"{"text":"hello"}"#,
        "tool_timeout_seconds": "5",
        "_galaxyssi_session_id": "session-a",
        "_galaxyssi_conversation_id": "conversation-a",
        "_galaxyssi_turn_id": "turn-a"
      ]
    )

    let result = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"))

    XCTAssertTrue(result.success)
    XCTAssertEqual(delegate.callCount, 0)
    XCTAssertEqual(captured?.descriptor.id, descriptor.id)
    XCTAssertEqual(captured?.input["text"], .string("hello"))
    XCTAssertEqual(captured?.context.invocationId, "write-1")
    XCTAssertEqual(captured?.context.idempotencyKey, "write-1")
    XCTAssertEqual(captured?.context.sessionId, "session-a")
    XCTAssertEqual(captured?.context.conversationId, "conversation-a")
    XCTAssertEqual(captured?.context.turnId, "turn-a")
    XCTAssertEqual(captured?.context.deadlineEpochMillis, 15_000)
    XCTAssertEqual(captured?.context.grantedPermissions, Set(["permission.write"]))
    XCTAssertEqual(captured?.context.grantedConsents, Set(["consent.write"]))
    XCTAssertEqual(captured?.context.attributes["step_id"], "write-1")
    XCTAssertEqual(captured?.context.attributes[AgentNativeToolRegistry.legacyActionIdAttribute], "write-1")
    XCTAssertEqual(result.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(result.metadata["native_tool_status"], "succeeded")
    XCTAssertEqual(result.metadata["idempotency_key"], "write-1")
    XCTAssertEqual(events.map(\.stage), [.started, .progress, .finished])
    XCTAssertEqual(events.map(\.toolId), [descriptor.id, descriptor.id, descriptor.id])
    XCTAssertEqual(events.map(\.invocationId), ["write-1", "write-1", "write-1"])
    XCTAssertEqual(events.map(\.stepId), ["write-1", "write-1", "write-1"])
    XCTAssertEqual(events.map(\.conversationId), ["conversation-a", "conversation-a", "conversation-a"])
    XCTAssertEqual(events.map(\.turnId), ["turn-a", "turn-a", "turn-a"])
    XCTAssertEqual(events[0].timestampMillis, 10_000)
    XCTAssertEqual(events[1].progressStage, "writing")
    XCTAssertEqual(events[1].message, "Writing local data")
    XCTAssertEqual(events[1].percent, 50)
    XCTAssertEqual(events[1].sequence, 2)
    XCTAssertEqual(events[1].timestampMillis, 10_010)
    XCTAssertEqual(events[2].status, .succeeded)
    XCTAssertEqual(events[2].message, "done")
    XCTAssertEqual(events[2].timestampMillis, 10_020)
  }

  func testAgentNativeToolActionExecutorBindsWorkspaceInputAndDelegatesOtherActions() throws {
    var captured: AgentNativeToolInvocation?
    var delegated: AgentAction?
    let descriptor = try nativeToolDescriptor(AgentPhoneNativeToolCatalog.workspaceReadText)
    let registry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "workspace.executor"),
      executor: { invocation in
        captured = invocation
        return .success(output: ["text": .string("hello")], message: "read")
      }
    ))
    let delegate = TestAgentActionExecutor { action, _ in
      delegated = action
      return AgentActionResult(actionId: action.id, success: true, message: "delegated")
    }
    let executor = AgentNativeToolActionExecutor(registry: registry, delegate: delegate)
    let workspaceAction = AgentAction(
      id: "read-current",
      kind: .callNativeTool,
      target: "Workspace",
      risk: .low,
      status: .running,
      description: "Read workspace",
      parameters: [
        "tool_id": descriptor.id,
        "input_json": #"{"workspace_id":"foreign","path":"notes.txt"}"#,
        "_galaxyssi_conversation_id": "conversation-workspace"
      ],
      requiresConfirmation: false
    )
    let openURL = AgentAction(
      id: "open-url",
      kind: .openURL,
      target: "https://galaxyssi.com",
      risk: .low,
      status: .running,
      description: "Open URL"
    )

    let workspaceResult = executor.execute(action: workspaceAction, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))
    let delegatedResult = executor.execute(action: openURL, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))

    XCTAssertTrue(workspaceResult.success)
    XCTAssertEqual(
      captured?.input["workspace_id"],
      .string(AgentWorkspaceScope.id(conversationId: "conversation-workspace"))
    )
    XCTAssertEqual(captured?.input["path"], .string("notes.txt"))
    XCTAssertTrue(delegatedResult.success)
    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(delegated?.id, "open-url")
  }

  func testWorkspaceArtifactRequiresLatestScopedVerifiedExportThroughNativeExecutor() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = AgentPhoneNativeToolCatalog.self
    let registry = try AgentNativeToolRegistry().registerExecutables(
      catalog.workspaceExecutableDefinitions(store: AgentWorkspaceNativeToolExecutor(runtimeRoot: root)))
    let executor = AgentNativeToolActionExecutor(registry: registry, delegate: TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "Unexpected legacy action")
    })
    let scope = AgentPlanContinuationScope(conversationId: "files", turnId: "current")
    let workspace = AgentWorkspaceScope.id(conversationId: scope.conversationId)
    let target = try XCTUnwrap(AgentArtifactRequirement(path: "output.txt", workspaceId: workspace))
    func run(_ tool: String, input: AgentMcpJSONObject, key: String? = nil) -> AgentAction {
      var action = scope.bind(AgentAction(id: UUID().uuidString, kind: .callNativeTool, target: tool,
        risk: .low, status: .running, description: "Fixture", parameters: [
          "tool_id": tool, "input_json": AgentMcpJSONCodec.stringify(input),
          "_galaxyssi_workspace_id": workspace
        ], requiresConfirmation: false))
      action.parameters["idempotency_key"] = key
      let result = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))
      action.status = result.success ? .completed : .failed
      action.artifactReceipt = AgentArtifactOperationReceipt.from(result)
      action.evidence = result.metadata["native_tool_output"] ?? ""
      return action
    }
    func write(_ text: String) -> AgentAction {
      run(catalog.workspaceWriteText, input: ["path": .string(target.path), "text": .string(text)])
    }
    func export(_ key: String? = nil) -> AgentAction {
      run(catalog.workspaceExport, input: ["path": .string(target.path), "workspace_id": .string("foreign")], key: key)
    }
    func missing(_ history: [AgentAction], requirement: AgentArtifactRequirement? = nil) -> [String] {
      AgentArtifactCompletionEvidence.missing([requirement ?? target], history: history, scope: scope)
    }
    let original = "Name,Total\r\n  A,7\r\n"
    let initial = run(catalog.workspaceCreateText, input: ["path": .string(target.path), "text": .string(original)])
    let source = run(catalog.workspaceSha256, input: ["path": .string(target.path)])
    let old = export("export-before-edit")
    XCTAssertEqual(old.status, .completed)
    let first = try XCTUnwrap(old.artifactReceipt)
    XCTAssertEqual(first.workspaceId, workspace)
    let snapshot = try XCTUnwrap(first.inspection)
    let file = AgentVerifiedArtifactSnapshot.url(root: root, digest: snapshot.digest, path: snapshot.path)
    XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8))
    let review = try XCTUnwrap(AgentPlannerObservation.artifactExport(old, scope: scope))
    XCTAssertEqual(review.status, "complete")
    XCTAssertEqual(AgentObservedOutputFields.value(at: "/artifacts/0/openability/details/text", in: review.output),
      .string(original))
    XCTAssertTrue(missing([initial, source, old]).isEmpty)
    let changed = write("Edited")
    XCTAssertFalse(missing([initial, source, old, changed]).isEmpty)
    let replay = export("export-before-edit")
    XCTAssertTrue(replay.artifactReceipt?.replayed == true)
    XCTAssertFalse(missing([initial, source, old, changed, replay]).isEmpty)
    let fresh = export()
    XCTAssertEqual(try Data(contentsOf: file), Data(original.utf8))
    XCTAssertTrue(missing([initial, source, old, changed, replay, fresh]).isEmpty)
    let transform = try XCTUnwrap(AgentArtifactRequirement(path: target.path,
      sourceSha256: try XCTUnwrap(source.artifactReceipt?.inspection?.digest), workspaceId: workspace))
    XCTAssertTrue(missing([initial, source, old, changed, fresh], requirement: transform).isEmpty)
    XCTAssertTrue(missing([initial, source, old], requirement: transform).first?
      .contains("artifact_unchanged_from_declared_source") == true)
    let prior = AgentCompletionRequirements(publication: .none, phoneLinux: false, fileArtifacts: [transform])
    let correction = AgentCompletionRequirements(publication: .none, phoneLinux: false,
      reason: "This was a new file; I used its output hash.", fileArtifacts: [target])
    func corrected(_ history: [AgentAction], candidate: AgentCompletionRequirements? = nil) -> [AgentArtifactRequirement] {
      AgentArtifactCompletionEvidence.combinedRequirements(prior: prior, candidate: candidate ?? correction,
        history: history, scope: scope)
    }
    XCTAssertEqual(corrected([initial, source, old]), [target])
    XCTAssertEqual(corrected([source, old]), [transform, target])
    let unchangedWrite = write(original)
    XCTAssertEqual(corrected([initial, source, old, unchangedWrite, export()]), [transform, target])
    XCTAssertEqual(corrected([initial, source, old], candidate: .init(publication: .none, phoneLinux: false,
      fileArtifacts: [target])), [transform, target])
    let deleted = run(catalog.workspaceDelete, input: ["path": .string(target.path)])
    let failedExport = export()
    XCTAssertEqual(failedExport.status, .failed)
    XCTAssertFalse(missing([fresh, deleted, failedExport]).isEmpty)
    let restored = try JSONDecoder().decode(AgentAction.self, from: JSONEncoder().encode(fresh))
    XCTAssertTrue(missing([restored]).isEmpty)
  }

  func testWorkspaceExportSchemaValidatesFullTextAndRejectsInvalidUTF8Evidence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = try XCTUnwrap(AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(
      store: AgentWorkspaceNativeToolExecutor(runtimeRoot: root)).first {
        $0.definition.descriptor.id == AgentPhoneNativeToolCatalog.workspaceExport
      }?.definition.descriptor)
    let limit = AgentVerifiedArtifactSnapshot.maximumReviewCharacters
    let exact = String(repeating: "a", count: limit)
    let fixtures: [(Data, String, Bool?, String?)] = [
      (Data(), "verified", true, ""),
      (Data(exact.utf8), "verified", true, exact),
      (Data((exact + "b").utf8), "verified", false, nil),
      (Data(exact.utf8) + Data([0xC3, 0x28]), "unverified", nil, nil),
      (Data([0xEF, 0xBB, 0xBF, 0x61]), "verified", true, "\u{FEFF}a")
    ]
    for (bytes, status, complete, text) in fixtures {
      let artifact = try AgentVerifiedArtifactSnapshot.write(data: bytes, path: "nested/review.csv", root: root)
      let output: AgentMcpJSONObject = [
        "workspace_id": .string("scope"), "artifact_workspace_id": .string("scope"),
        "artifacts": .array([.object(artifact)])
      ]
      XCTAssertTrue(AgentNativeJsonSchemaValidator.validateObject(schema: tool.outputSchema, object: output).isValid)
      let inspection = try XCTUnwrap(artifact["openability"]?.objectValue)
      XCTAssertEqual(inspection.string("status"), status)
      XCTAssertEqual(inspection.string("sha256"), artifact.string("sha256"))
      let details = inspection["details"]?.objectValue
      XCTAssertEqual(details?["text_complete"]?.boolValue, complete)
      XCTAssertEqual(details?["text"]?.strictStringValue, text)
      if let text { XCTAssertEqual(Data(text.utf8), bytes) }
    }
    XCTAssertFalse(AgentNativeJsonSchemaValidator.validateObject(
      schema: tool.outputSchema, object: ["relative_path": .string("review.csv")]).isValid)
  }

  func testWorkspaceExportInspectsRecognizedBinaryFormats() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let page = CGRect(x: 0, y: 0, width: 40, height: 60)
    let pdf = UIGraphicsPDFRenderer(bounds: page).pdfData { $0.beginPage() }
    let png = UIGraphicsImageRenderer(size: page.size).pngData { context in
      context.cgContext.fill(page)
    }
    func zip(_ files: [(String, String)]) -> Data {
      AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: files.map {
        AgentRuntimeProjectArchiveEntry(path: $0.0, data: Data($0.1.utf8))
      })
    }
    let archive = zip([("README.txt", "crc protected")])
    var corrupt = archive
    corrupt[30 + "README.txt".utf8.count] ^= 0x01
    let docx = zip([
      ("[Content_Types].xml", #"<Types><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>"#),
      ("_rels/.rels", #"<Relationships><Relationship Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#),
      ("word/document.xml", #"<w:document xmlns:w="urn:word"><w:body/></w:document>"#)
    ])
    let fixtures: [(String, Data, String, Bool)] = [
      ("good.pdf", pdf, "pdf_document_open", true),
      ("bad.pdf", png, "pdf_document_open", false),
      ("good.png", png, "image_first_frame_decode", true),
      ("bad.png", pdf, "image_first_frame_decode", false),
      ("good.zip", archive, "archive_entries_read", true),
      ("bad.zip", corrupt, "archive_entries_read", false),
      ("good.docx", docx, "office_package_open", true),
      ("bad.docx", archive, "office_package_open", false),
      ("unrecognized.bin", archive, "byte_stream", true)
    ]
    for (path, bytes, scope, verified) in fixtures {
      let artifact = try AgentVerifiedArtifactSnapshot.write(data: bytes, path: path, root: root)
      let receipt = try XCTUnwrap(artifact["openability"]?.objectValue)
      XCTAssertEqual(receipt.string("scope"), scope, path)
      XCTAssertEqual(receipt.string("sha256"), artifact.string("sha256"), path)
      XCTAssertEqual(receipt.string("status"), verified ? "verified" : "unverified", path)
      let rich = AgentRuntimeArtifactUi.richOutput(output: ["artifacts": .array([.object(artifact)])],
        responseText: "Prepared file.", preferredFileName: path, zh: false)
      XCTAssertEqual(AgentRichContentCodec.decode(rich).contains { $0.type == .file }, verified, path)
    }
  }

  func testArtifactEvidenceRejectsPendingParentOperationsAndAmbiguousWorkspace() throws {
    let scope = AgentPlanContinuationScope(conversationId: "conversation", turnId: "turn")
    let path = "outputs/result.csv"
    let target = try XCTUnwrap(AgentArtifactRequirement(path: path))
    func fixture(_ tool: String, path: String, workspace: String, status: AgentActionStatus = .completed,
                 inspection: AgentArtifactOperationReceipt.Inspection? = nil) -> AgentAction {
      var action = scope.bind(AgentAction(id: UUID().uuidString, kind: .callNativeTool, target: tool, risk: .low,
        status: status, description: "Fixture", parameters: [
          "tool_id": tool, "input_json": AgentMcpJSONCodec.stringify(["path": .string(path)])
        ]))
      action.artifactReceipt = AgentArtifactOperationReceipt(toolId: tool, workspaceId: workspace,
        conversationId: scope.conversationId, turnId: scope.turnId, invocationId: action.id,
        replayed: false, succeeded: status == .completed, inspection: inspection)
      return action
    }
    let catalog = AgentPhoneNativeToolCatalog.self
    let inspected = AgentArtifactOperationReceipt.Inspection(path: path, digest: String(repeating: "a", count: 64), size: 8)
    let export = fixture(catalog.workspaceExport, path: path, workspace: "a", inspection: inspected)
    let foreignExport = fixture(catalog.workspaceExport, path: path, workspace: "b", inspection: inspected)
    let pending = fixture(catalog.workspaceDelete, path: "outputs", workspace: "a", status: .running)
    let other = fixture(catalog.workspaceDelete, path: "outputs-old", workspace: "a", status: .failed)
    let foreign = fixture(catalog.workspaceDelete, path: "outputs", workspace: "b", status: .failed)
    XCTAssertTrue(AgentArtifactCompletionEvidence.missing([target], history: [export, other, foreign], scope: scope).isEmpty)
    XCTAssertFalse(AgentArtifactCompletionEvidence.missing([target], history: [pending, export], scope: scope).isEmpty)
    XCTAssertFalse(AgentArtifactCompletionEvidence.missing([target], history: [export, foreignExport], scope: scope).isEmpty)
    let explicit = try XCTUnwrap(AgentArtifactRequirement(path: path, workspaceId: "a"))
    XCTAssertTrue(AgentArtifactCompletionEvidence.missing([explicit], history: [export, foreignExport], scope: scope).isEmpty)
    let wrongTurn = AgentPlanContinuationScope(conversationId: scope.conversationId, turnId: "other-turn")
    XCTAssertFalse(AgentArtifactCompletionEvidence.missing([explicit], history: [export], scope: wrongTurn).isEmpty)
    XCTAssertNil(AgentArtifactRequirement(path: "../result.csv"))
    XCTAssertNil(AgentArtifactRequirement(path: path, workspaceId: " guessed "))
  }

  func testAgentNativeToolActionExecutorRejectsInvalidNativeActionInput() throws {
    let descriptor = try nativeToolDescriptor("galaxyssi.test.read")
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "unexpected delegate")
    }
    let executor = AgentNativeToolActionExecutor(registry: registry, delegate: delegate)
    let action = AgentAction(
      id: "bad-json",
      kind: .callNativeTool,
      target: "Local",
      risk: .low,
      status: .running,
      description: "Bad input",
      parameters: ["tool_id": descriptor.id, "input_json": "[1,2,3]"]
    )

    let result = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))

    XCTAssertFalse(result.success)
    XCTAssertEqual(result.metadata["error_code"], "invalid_input_json")
    XCTAssertEqual(delegate.callCount, 0)
  }

  func testAgentNativeToolActionExecutorIncludesStructuredValidationIssuesInFailure() throws {
    let descriptor = try nativeToolDescriptor("galaxyssi.test.validation")
    let registry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      executor: { _ in
        .failure(
          code: "invalid_input",
          message: "Native tool rejected the input",
          details: [
            "validation_issues": .array([
              .object([
                "path": .string("repository_url"),
                "code": .string("invalid_format"),
                "message": .string("Use an HTTPS repository URL")
              ]),
              .object([
                "path": .string("model_id"),
                "code": .string("required"),
                "message": .string("Select a model")
              ])
            ])
          ]
        )
      }
    ))
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "unexpected delegate")
    }
    let action = AgentAction(
      id: "validation-issues",
      kind: .callNativeTool,
      target: "Local",
      risk: .low,
      status: .running,
      description: "Validate native input",
      parameters: ["tool_id": descriptor.id, "input_json": "{}"]
    )

    let result = AgentNativeToolActionExecutor(registry: registry, delegate: delegate)
      .execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))

    XCTAssertFalse(result.success)
    XCTAssertEqual(
      result.message,
      "Native tool rejected the input: repository_url | invalid_format | Use an HTTPS repository URL; model_id | required | Select a model"
    )
    XCTAssertEqual(delegate.callCount, 0)
  }

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.result",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let context = AgentNativeToolInvocationContext(
      invocationId: "invoke-1",
      idempotencyKey: "key-1",
      attributes: [AgentNativeToolRegistry.legacyActionIdAttribute: "legacy-1"]
    )
    let result = registry.makeResult(
      descriptor.id,
      input: [:],
      context: context,
      status: .rejected,
      message: "Missing permission",
      error: AgentNativeToolError(code: "missing_permissions", message: "Missing permission"),
      verification: AgentNativeToolVerification(status: .skipped),
      startedAtEpochMillis: 1_000,
      finishedAtEpochMillis: 1_010
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    let callData = try JSONEncoder().encode(AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-1",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap"
    )))
    let callObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: callData) as? [String: Any]
    )

    XCTAssertEqual(receipt["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(receipt["idempotency_key"] as? String, "key-1")
    XCTAssertEqual(receipt["started_at_epoch_ms"] as? Int, 1_000)
    XCTAssertEqual(receipt["finished_at_epoch_ms"] as? Int, 1_010)
    XCTAssertEqual(receipt["duration_ms"] as? Int, 10)
    XCTAssertNotNil(receipt["input_sha256"])
    XCTAssertEqual(provenance["tool_id"] as? String, descriptor.id)
    XCTAssertEqual(provenance["executor_id"] as? String, "test.executor")
    XCTAssertEqual(provenance["legacy_agent_action_id"] as? String, "legacy-1")
    XCTAssertEqual(callObject["tool_id"] as? String, AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    XCTAssertNil(receipt["startedAtEpochMillis"])
    XCTAssertNil(provenance["legacyAgentActionId"])
    XCTAssertNil(callObject["toolId"])
  }

  func testAgentNativeToolRegistryBuildsPreflightRejectionResults() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.preflight",
      requiredPermissions: [AgentNativePermissionRequirement(id: "ios.permission.camera")]
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])

    let result = try XCTUnwrap(registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-preflight")
    ))
    let passed = registry.preflightRejectionResult(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-ready",
        grantedPermissions: ["ios.permission.camera"]
      )
    )

    XCTAssertEqual(result.status, .rejected)
    XCTAssertEqual(result.error?.code, "missing_permissions")
    XCTAssertEqual(result.receipt.invocationId, "invoke-preflight")
    XCTAssertEqual(result.provenance.toolId, descriptor.id)
    XCTAssertNil(passed)
  }

  func testAgentNativeToolRegistryInvokeReturnsReceiptProgressAndVerification() throws {
    var now: Int64 = 1_000
    var started = 0
    var progress: [AgentNativeToolProgressUpdate] = []
    var finished = 0
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.invoke",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "test.executor",
          provenanceMetadata: ["implementation": "fake"]
        ),
        executor: { invocation in
          try invocation.reportProgress(
            stage: "working",
            message: "Preparing output",
            percent: 40,
            sequence: 3
          )
          now += 7
          return .success(
            output: ["value": .string("done")],
            message: "Completed",
            metadata: ["native_call": .string("local")]
          )
        },
        verifier: { _, execution in
          AgentNativeToolVerification(
            status: .passed,
            evidence: ["observed": execution.output["value"] ?? .null]
          )
        }
      ))

    let result = registry.invoke(
      descriptor.id,
      input: [:],
      context: AgentNativeToolInvocationContext(invocationId: "invoke-7", requestedAtEpochMillis: now),
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onStarted: { _ in started += 1 },
        onProgress: { _, update in progress.append(update) },
        onFinished: { _ in finished += 1 }
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.output["value"], .string("done"))
    XCTAssertEqual(result.message, "Completed")
    XCTAssertEqual(result.receipt.durationMillis, 7)
    XCTAssertEqual(result.receipt.inputSha256.count, 64)
    XCTAssertEqual(result.receipt.outputSha256.count, 64)
    XCTAssertEqual(result.verification?.status, .passed)
    XCTAssertEqual(result.provenance.executorId, "test.executor")
    XCTAssertEqual(result.provenance.toolVersion, "1.0.0")
    XCTAssertEqual(started, 1)
    XCTAssertEqual(progress.first?.stage, "working")
    XCTAssertEqual(progress.first?.percent, 40)
    XCTAssertEqual(progress.first?.sequence, 3)
    XCTAssertEqual(finished, 1)
    XCTAssertTrue(result.toJson().contains("\"invocation_id\":\"invoke-7\""))
  }

  func testAgentNativeToolRegistryInvokeRejectsInvalidOutputAndFailedVerification() throws {
    let invalidOutput = try nativeToolDescriptor(
      "galaxyssi.test.invalid-output",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let verificationFailed = try nativeToolDescriptor("galaxyssi.test.verification")
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: invalidOutput, executorId: "test.executor"),
        executor: { _ in .success(output: ["value": .int(1)], message: "Invalid") }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: verificationFailed, executorId: "test.executor"),
        executor: { _ in .success(message: "Executed") },
        verifier: { _, _ in AgentNativeToolVerification(status: .failed, message: "Screen did not change") }
      ))

    let invalid = registry.invoke(invalidOutput.id, input: [:])
    let failed = registry.invoke(verificationFailed.id, input: [:])

    XCTAssertEqual(invalid.status, .failed)
    XCTAssertEqual(invalid.error?.code, "invalid_output")
    XCTAssertEqual(failed.status, .verificationFailed)
    XCTAssertEqual(failed.error?.code, "verification_failed")
    XCTAssertEqual(failed.verification?.message, "Screen did not change")
  }

  func testAgentNativeToolRegistryInvokeHandlesCancellationTimeoutAndMissingExecutor() throws {
    var now: Int64 = 10
    var cancelledHooks = 0
    var timeoutHooks = 0
    var executions = 0
    let cancelledDescriptor = try nativeToolDescriptor("galaxyssi.test.cancelled")
    let timedDescriptor = try nativeToolDescriptor("galaxyssi.test.timeout", timeoutMillis: 5)
    let descriptorOnly = try nativeToolDescriptor("galaxyssi.test.descriptor-only")
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptorOnly, executorId: "test.executor")
    ])
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: cancelledDescriptor, executorId: "test.executor"),
        executor: { _ in
          executions += 1
          return .success()
        }
      ))
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: timedDescriptor, executorId: "test.executor"),
        executor: { invocation in
          now += 5
          try invocation.checkpoint()
          return .success()
        }
      ))

    let cancelled = registry.invoke(
      cancelledDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        cancellationRequested: { true },
        onCancelled: { _ in cancelledHooks += 1 }
      )
    )
    let timedOut = registry.invoke(
      timedDescriptor.id,
      input: [:],
      hooks: AgentNativeToolInvocationHooks(
        nowMillis: { now },
        onTimeout: { _ in timeoutHooks += 1 }
      )
    )
    let missingExecutor = registry.invoke(descriptorOnly.id, input: [:])

    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.error?.code, "cancelled")
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(cancelledHooks, 1)
    XCTAssertEqual(timedOut.status, .timedOut)
    XCTAssertEqual(timedOut.error?.code, "timeout")
    XCTAssertEqual(timeoutHooks, 1)
    XCTAssertEqual(missingExecutor.status, .unavailable)
    XCTAssertEqual(missingExecutor.error?.code, "missing_executor")
  }

  func testProgressAwareInvocationRenewsRollingDeadlineButHonorsHardDeadline() throws {
    var now: Int64 = 90
    let descriptor = try AgentNativeToolDescriptor(
      id: "galaxyssi.test.progress-timeout",
      version: "1.0.0",
      title: "Progress timeout",
      description: "Exercises cooperative rolling deadlines.",
      location: .application,
      risk: .low,
      timeoutMillis: 100,
      timeoutPolicy: .progressAware
    )
    let invocation = AgentNativeToolInvocation(
      descriptor: descriptor, input: [:], context: AgentNativeToolInvocationContext(),
      startedAtEpochMillis: 0, deadlineEpochMillis: 100,
      nowMillis: { now }, cancellationRequested: { false }, progressReporter: { _, _ in })

    try invocation.checkpoint()
    XCTAssertEqual(invocation.deadlineEpochMillis, 190)
    now = 150
    try invocation.checkpoint()
    XCTAssertEqual(invocation.deadlineEpochMillis, 250)

    now = 90
    let bounded = AgentNativeToolInvocation(
      descriptor: descriptor, input: [:], context: AgentNativeToolInvocationContext(),
      startedAtEpochMillis: 0, deadlineEpochMillis: 100, hardDeadlineEpochMillis: 150,
      nowMillis: { now }, cancellationRequested: { false }, progressReporter: { _, _ in })
    try bounded.checkpoint()
    XCTAssertEqual(bounded.deadlineEpochMillis, 150)
    now = 150
    XCTAssertThrowsError(try bounded.checkpoint()) { error in
      XCTAssertEqual(error as? AgentNativeToolInvocationError, .timedOut)
    }
  }

  func testAgentNativeToolRegistryInvokeReplaysSuccessfulKeyedResults() throws {
    var executions = 0
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.replay",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )

    func registry() throws -> AgentNativeToolRegistry {
      try AgentNativeToolRegistry(replayStore: replayStore)
        .registerExecutable(AgentNativeToolExecutableDefinition(
          definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
          executor: { _ in
            executions += 1
            return .success(output: ["execution": .int(Int64(executions))])
          }
        ))
    }

    let missingKey = try registry().invoke(descriptor.id, input: ["value": .int(1)])
    let first = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = try registry().invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = try registry().invoke(
      descriptor.id,
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(first.output, replay.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "first")
    XCTAssertEqual(replay.receipt.invocationId, "second")
    XCTAssertEqual(conflict.status, .rejected)
    XCTAssertEqual(conflict.error?.code, "idempotency_key_conflict")
  }

  func testAgentNativeToolRegistryReplaysSnapshotStoreAcrossRegistryRecreation() throws {
    var executions = 0
    var now: Int64 = 2_000
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.snapshot.replay",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )

    func registry(replayStore: AgentNativeToolReplayStore) throws -> AgentNativeToolRegistry {
      try AgentNativeToolRegistry(replayStore: replayStore)
        .registerExecutable(AgentNativeToolExecutableDefinition(
          definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
          executor: { _ in
            executions += 1
            return .success(output: ["execution": .int(Int64(executions))])
          }
        ))
    }

    let firstStore = AgentNativeToolReplaySnapshotStore(nowMillis: { now })
    let first = try registry(replayStore: firstStore).invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let serialized = firstStore.serializedSnapshot()
    now += 10
    let restoredStore = AgentNativeToolReplaySnapshotStore(serializedEntries: serialized, nowMillis: { now })
    let replay = try registry(replayStore: restoredStore).invoke(
      descriptor.id,
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )

    XCTAssertTrue(first.isSuccess)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(replay.output, first.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "first")
    XCTAssertEqual(replay.receipt.invocationId, "second")
    XCTAssertTrue(serialized.contains(#""tool_id":"galaxyssi.test.snapshot.replay""#))
  }

  func testAgentNativeEffectJournalScopesIdenticalKeysToTheirRunIdentity() throws {
    var executions = 0
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.scoped.effect",
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry(replayStore: InMemoryAgentNativeToolReplayStore())
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.effect"),
        executor: { _ in
          executions += 1
          return .success(output: ["execution": .int(Int64(executions))])
        }
      ))
    let base = AgentNativeToolInvocationContext(
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "effect",
      attributes: ["client_route_id": "phone", "goal_id": "goal", "task_id": "task"]
    )
    let contexts = [
      base,
      AgentNativeToolInvocationContext(sessionId: "other", conversationId: "conversation", turnId: "turn", idempotencyKey: "effect", attributes: base.attributes),
      AgentNativeToolInvocationContext(sessionId: "session", conversationId: "other", turnId: "turn", idempotencyKey: "effect", attributes: base.attributes),
      AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation", turnId: "other", idempotencyKey: "effect", attributes: base.attributes),
      AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation", turnId: "turn", idempotencyKey: "effect", attributes: base.attributes.merging(["task_id": "other"]) { _, new in new }),
      AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation", turnId: "turn", idempotencyKey: "effect", attributes: base.attributes.merging(["goal_id": "other"]) { _, new in new }),
      AgentNativeToolInvocationContext(sessionId: "session", conversationId: "conversation", turnId: "turn", idempotencyKey: "effect", attributes: base.attributes.merging(["client_route_id": "other"]) { _, new in new })
    ]

    for context in contexts {
      let first = registry.invoke(descriptor.id, input: [:], context: context)
      var replayContext = context
      replayContext.invocationId = UUID().uuidString
      let replay = registry.invoke(descriptor.id, input: [:], context: replayContext)
      XCTAssertTrue(first.isSuccess)
      XCTAssertTrue(replay.receipt.replayed)
      XCTAssertEqual(first.output, replay.output)
    }
    XCTAssertEqual(executions, contexts.count)
  }

  func testAgentNativeEffectJournalDoesNotRerunUnfinishedClaim() throws {
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.interrupted.effect",
      idempotency: .idempotent,
      effect: .mutation
    )
    let context = AgentNativeToolInvocationContext(
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "effect",
      attributes: ["task_id": "task", "goal_id": "goal", "client_route_id": "phone"]
    )
    let key = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: "effect",
      scope: AgentNativeEffectScope(context: context)
    )
    let store = InMemoryAgentNativeToolReplayStore()
    let inputSha256 = AgentMcpJSONCodec.sha256(AgentMcpJSONObject())
    XCTAssertTrue(try store.claim(key, inputSha256: inputSha256, invocationId: "interrupted").acquired)
    let registry = try AgentNativeToolRegistry(replayStore: store)
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.effect"),
        executor: { _ in XCTFail("An uncertain effect must not execute again"); return .success() }
      ))

    let result = registry.invoke(descriptor.id, input: [:], context: context)

    XCTAssertEqual(result.error?.code, "effect_outcome_unknown")
    XCTAssertEqual(result.error?.retryable, false)
    XCTAssertEqual(result.error?.details["original_invocation_id"], .string("interrupted"))
    XCTAssertNil(result.error?.details["recovery_query"], "Legacy claims must not invent an observation")
  }

  func testNativeEffectRecoveryQueryIsClaimedBeforeDispatchAndReplaysUncertainResults() throws {
    let root = try temporaryDirectory("native-effect-query")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("replay.json")
    let secrets = InMemorySecretStore()
    let write = try nativeToolDescriptor("galaxyssi.test.recovery.write", idempotency: .idempotencyKeyRequired,
      effect: .mutation)
    let read = try nativeToolDescriptor("galaxyssi.test.recovery.read", inputSchema: [
      "type": .string("object"), "properties": .object(["operation_id": .object(["type": .string("string")])]),
      "required": .array([.string("operation_id")]), "additionalProperties": .bool(false)
    ], idempotency: .idempotent, effect: .readOnly)
    var context = AgentNativeToolInvocationContext(invocationId: "original-private-operation", sessionId: "session",
      conversationId: "conversation", turnId: "turn", idempotencyKey: "effect",
      attributes: ["task_id": "task", "goal_id": "goal", "client_route_id": "phone"])
    let key = AgentNativeToolReplayKey(toolId: write.id, toolVersion: write.version, idempotencyKey: "effect",
      scope: AgentNativeEffectScope(context: context))
    let query = AgentNativeEffectRecoveryQuery(toolId: read.id, toolVersion: read.version,
      arguments: ["operation_id": .string(context.invocationId)])
    var executions = 0
    var automaticReads = 0
    var preparations = 0
    let store = FileAgentNativeToolReplayStore(fileURL: file, secrets: secrets)
    func registry(_ storage: AgentNativeToolReplayStore, recipe: AgentNativeEffectRecoveryQuery) throws -> AgentNativeToolRegistry {
      let observer = AgentNativeToolExecutableDefinition(
        definition: .init(descriptor: read, executorId: "test.effect_read"),
        executor: { _ in automaticReads += 1; return .success() })
      var mutation = AgentNativeToolExecutableDefinition(
        definition: .init(descriptor: write, executorId: "test.effect_write"),
        executor: { _ in
          executions += 1
          XCTAssertEqual(storage.observe(key)?.recoveryQuery, query)
          return .failure(code: "lost_response", message: "Response lost",
            details: ["outcome_unknown": .bool(true), "recovery_query": .string("untrusted")])
        })
      mutation.recoveryQuery = { _ in preparations += 1; return recipe }
      return try AgentNativeToolRegistry(replayStore: storage).registerExecutables([observer, mutation])
    }
    let invalid = AgentNativeEffectRecoveryQuery(toolId: write.id, toolVersion: write.version, arguments: [:])
    for recipe in [invalid, .init(toolId: read.id, toolVersion: "0.0.0", arguments: query.arguments),
                   .init(toolId: read.id, toolVersion: read.version, arguments: [:])] {
      let rejected = try registry(store, recipe: recipe).invoke(write.id, input: [:], context: context)
      XCTAssertEqual(rejected.error?.code, "invalid_effect_recovery_query")
    }
    XCTAssertNil(store.observe(key))
    let original = try registry(store, recipe: query).invoke(write.id, input: [:], context: context)
    XCTAssertEqual(original.error?.details["recovery_query"], query.json)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(automaticReads, 0)
    let bytes = try Data(contentsOf: file)
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("original-private-operation"))

    let reopened = FileAgentNativeToolReplayStore(fileURL: file, secrets: secrets)
    context.invocationId = "retry-invocation"
    let retry = try registry(reopened, recipe: invalid).invoke(write.id, input: [:], context: context)
    XCTAssertTrue(retry.receipt.replayed)
    XCTAssertEqual(retry.error?.details["recovery_query"], query.json)
    XCTAssertEqual(preparations, 4, "Replaying committed results must not reprepare the query")
    XCTAssertEqual(executions, 1)

    let pendingKey = AgentNativeToolReplayKey(toolId: write.id, toolVersion: write.version, idempotencyKey: "pending",
      scope: key.scope)
    _ = try store.claim(pendingKey, inputSha256: AgentMcpJSONCodec.sha256(AgentMcpJSONObject()),
      invocationId: "original-private-operation", recoveryQuery: query)
    context.idempotencyKey = "pending"
    let interrupted = try registry(reopened, recipe: invalid).invoke(write.id, input: [:], context: context)
    XCTAssertEqual(interrupted.error?.code, "effect_outcome_unknown")
    XCTAssertEqual(interrupted.receipt.originalInvocationId, "original-private-operation")
    XCTAssertEqual(interrupted.error?.details["recovery_query"], query.json)
    let conflict = try registry(reopened, recipe: invalid).invoke(write.id, input: ["changed": .bool(true)], context: context)
    XCTAssertEqual(conflict.error?.code, "idempotency_key_conflict")
    XCTAssertNil(conflict.error?.details["recovery_query"])
    var otherScope = context
    otherScope.turnId = "foreign"
    let foreign = try registry(reopened, recipe: invalid).invoke(write.id, input: [:], context: otherScope)
    XCTAssertEqual(foreign.error?.code, "invalid_effect_recovery_query")
    XCTAssertNil(foreign.error?.details["recovery_query"])
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(automaticReads, 0)

    let noKey = FileAgentNativeToolReplayStore(fileURL: file, secrets: InMemorySecretStore())
    let inaccessible = try registry(noKey, recipe: query).invoke(write.id, input: [:], context: context)
    XCTAssertFalse(inaccessible.isSuccess)
    XCTAssertNil(inaccessible.error?.details["recovery_query"])
    XCTAssertEqual(executions, 1, "Unreadable claims must not look like a new execution")
    let corrupt = Data("not a replay journal".utf8)
    try corrupt.write(to: file, options: .atomic)
    let damaged = try registry(reopened, recipe: query).invoke(write.id, input: [:], context: context)
    XCTAssertFalse(damaged.isSuccess)
    XCTAssertEqual(try Data(contentsOf: file), corrupt)
    XCTAssertEqual(executions, 1)
  }

  func testAgentNativeEffectObservationPrecedesLiveAvailability() throws {
    var available = true
    var availabilityChecks = 0
    var executions = 0
    let store = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.offline.effect",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: "test.effect",
      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
        availabilityChecks += 1
        return available
          ? .available
          : AgentNativeToolAvailability(status: .unavailable, reason: "Provider is offline")
      }
    )
    let registry = try AgentNativeToolRegistry(replayStore: store)
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: definition,
        executor: { _ in
          executions += 1
          return .success(output: ["execution": .int(Int64(executions))])
        }
      ))
    let context = AgentNativeToolInvocationContext(
      invocationId: "first",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "effect",
      attributes: ["client_route_id": "phone", "goal_id": "goal", "task_id": "task"]
    )

    let first = registry.invoke(descriptor.id, input: ["value": .int(1)], context: context)
    available = false
    var replayContext = context
    replayContext.invocationId = "second"
    let replay = registry.invoke(descriptor.id, input: ["value": .int(1)], context: replayContext)
    replayContext.invocationId = "third"
    let conflict = registry.invoke(descriptor.id, input: ["value": .int(2)], context: replayContext)

    XCTAssertTrue(first.isSuccess)
    XCTAssertEqual(replay.output, first.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "first")
    XCTAssertEqual(conflict.error?.code, "idempotency_key_conflict")
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(availabilityChecks, 1)
  }

  func testAgentNativeEffectObservationProtectsUnfinishedClaimWhileOffline() throws {
    var availabilityChecks = 0
    var executions = 0
    let store = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.offline.interrupted-effect",
      idempotency: .idempotencyKeyRequired
    )
    let definition = AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: "test.effect",
      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in
        availabilityChecks += 1
        return AgentNativeToolAvailability(status: .unavailable, reason: "Provider is offline")
      }
    )
    let registry = try AgentNativeToolRegistry(replayStore: store)
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: definition,
        executor: { _ in
          executions += 1
          return .success()
        }
      ))
    let interruptedContext = AgentNativeToolInvocationContext(
      invocationId: "interrupted",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "interrupted-effect",
      attributes: ["client_route_id": "phone", "goal_id": "goal", "task_id": "task"]
    )
    let interruptedKey = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: "interrupted-effect",
      scope: AgentNativeEffectScope(context: interruptedContext)
    )
    XCTAssertTrue(try store.claim(
      interruptedKey,
      inputSha256: AgentMcpJSONCodec.sha256(AgentMcpJSONObject()),
      invocationId: "interrupted"
    ).acquired)

    var recoveryContext = interruptedContext
    recoveryContext.invocationId = "recovery"
    let recovery = registry.invoke(descriptor.id, input: [:], context: recoveryContext)
    let freshContext = AgentNativeToolInvocationContext(
      invocationId: "fresh",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "fresh-effect",
      attributes: interruptedContext.attributes
    )
    let fresh = registry.invoke(descriptor.id, input: [:], context: freshContext)
    let freshKey = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: "fresh-effect",
      scope: AgentNativeEffectScope(context: freshContext)
    )

    XCTAssertEqual(recovery.error?.code, "effect_outcome_unknown")
    XCTAssertEqual(recovery.error?.retryable, false)
    XCTAssertEqual(recovery.error?.details["original_invocation_id"], .string("interrupted"))
    XCTAssertEqual(fresh.error?.code, "tool_unavailable")
    XCTAssertNil(store.observe(freshKey))
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(availabilityChecks, 1)
  }

  func testNonIdempotentEffectUsesInvocationFallbackAndReplaysRecordedOutcome() throws {
    var executions = 0
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.non-idempotent.effect",
      idempotency: .nonIdempotent
    )
    let registry = try AgentNativeToolRegistry(replayStore: InMemoryAgentNativeToolReplayStore())
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.effect"),
        executor: { _ in
          executions += 1
          return .success(output: ["execution": .int(Int64(executions))])
        }
      ))
    let context = AgentNativeToolInvocationContext(
      invocationId: "stable-invocation",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      attributes: ["task_id": "task"]
    )

    let first = registry.invoke(descriptor.id, input: [:], context: context)
    let replay = registry.invoke(descriptor.id, input: [:], context: context)

    XCTAssertTrue(first.isSuccess)
    XCTAssertEqual(replay.output, first.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.idempotencyKey, "stable-invocation")
    XCTAssertEqual(executions, 1)
  }

  func testAgentNativeEffectJournalReplaysFailuresAndCommitsBeforeFinishedHook() throws {
    var executions = 0
    var durableBeforeHook = false
    let store = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.failed.effect",
      idempotency: .idempotencyKeyRequired
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "first",
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      idempotencyKey: "effect",
      attributes: ["task_id": "task"]
    )
    let key = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: "effect",
      scope: AgentNativeEffectScope(context: context)
    )
    let registry = try AgentNativeToolRegistry(replayStore: store)
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.effect"),
        executor: { _ in
          executions += 1
          return .failure(code: "external_write_uncertain", message: "Connection lost after sending")
        }
      ))

    let first = registry.invoke(
      descriptor.id,
      input: [:],
      context: context,
      hooks: AgentNativeToolInvocationHooks(onFinished: { result in
        durableBeforeHook = store.get(key)?.receipt.invocationId == result.receipt.invocationId
      })
    )
    var replayContext = context
    replayContext.invocationId = "second"
    let replay = registry.invoke(descriptor.id, input: [:], context: replayContext)

    XCTAssertEqual(first.error?.code, "external_write_uncertain")
    XCTAssertEqual(replay.error, first.error)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(executions, 1)
    XCTAssertTrue(durableBeforeHook)
  }

  func testAgentNativeToolRegistryAuditsReplayFailureAndUnknownTools() throws {
    var executions = 0
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let auditStore = InMemoryAgentNativeToolAuditStore()
    let descriptor = try nativeToolDescriptor(
      "galaxyssi.test.audit",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["secret": .object(["type": .string("string")])]),
        "required": .array([.string("secret")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry(replayStore: replayStore, auditStore: auditStore)
      .registerExecutable(AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.audit"),
        executor: { invocation in
          executions += 1
          if invocation.input["secret"] == .string("fail-me") {
            return .failure(code: "expected_failure", message: "Sensitive value was rejected")
          }
          return .success(output: ["private_result": .string("hidden")])
        }
      ))

    func context(_ invocationId: String, key: String? = nil) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        invocationId: invocationId,
        sessionId: "session-secret",
        conversationId: "conversation-secret",
        turnId: "turn-secret",
        callerId: "agent",
        idempotencyKey: key,
        attributes: ["task_id": "task-secret"]
      )
    }

    _ = registry.invoke(descriptor.id, input: ["secret": .string("missing-key")], context: context("missing-key"))
    let first = registry.invoke(
      descriptor.id,
      input: ["secret": .string("keep-private")],
      context: context("first", key: "request-1")
    )
    let replay = registry.invoke(
      descriptor.id,
      input: ["secret": .string("keep-private")],
      context: context("second", key: "request-1")
    )
    _ = registry.invoke(
      descriptor.id,
      input: ["secret": .string("fail-me")],
      context: context("failed", key: "request-2")
    )
    _ = registry.invoke(
      "galaxyssi.test.audit.missing",
      input: ["secret": .string("never-store")],
      context: context("unknown")
    )

    let records = registry.audit()
    XCTAssertEqual(executions, 2)
    XCTAssertEqual(first.output, replay.output)
    XCTAssertTrue(replay.receipt.replayed)
    XCTAssertEqual(records.map(\.status), [.rejected, .failed, .succeeded, .succeeded, .rejected])
    XCTAssertEqual(records.map(\.replayed), [false, false, true, false, false])
    XCTAssertEqual(records[1].errorCode, "expected_failure")
    XCTAssertEqual(
      registry.audit(toolId: descriptor.id, status: .succeeded).map(\.invocationId),
      ["second", "first"]
    )

    let serialized = String(data: try JSONEncoder().encode(records), encoding: .utf8) ?? ""
    XCTAssertFalse(serialized.contains("keep-private"))
    XCTAssertFalse(serialized.contains("hidden"))
    XCTAssertFalse(serialized.contains("never-store"))
    XCTAssertFalse(serialized.contains("session-secret"))
    XCTAssertFalse(serialized.contains("conversation-secret"))
    XCTAssertFalse(serialized.contains("task-secret"))
    XCTAssertTrue(records.allSatisfy { $0.inputSha256.count == 64 && $0.recordSha256.count == 64 })
    XCTAssertTrue(records[1].identityHashes.keys.contains("session_id_sha256"))
    XCTAssertTrue(records[1].identityHashes.keys.contains("conversation_id_sha256"))
    XCTAssertTrue(records[1].identityHashes.keys.contains("turn_id_sha256"))
    XCTAssertTrue(records[1].identityHashes.keys.contains("task_id_sha256"))
  }

  func testAgentNativeToolAuditStoresBoundFilterAndPersistRecords() throws {
    let memoryStore = InMemoryAgentNativeToolAuditStore()
    let context = AgentNativeToolInvocationContext(
      sessionId: "session-a",
      conversationId: "conversation-a",
      turnId: "turn-a",
      attributes: ["task_id": "task-a"]
    )
    let success = AgentNativeToolAuditRecord.from(
      result: nativeToolResult(invocationId: "success", idempotencyKey: nil),
      context: context,
      risk: .low
    )
    let failure = AgentNativeToolAuditRecord.from(
      result: nativeToolResult(status: .failed, invocationId: "failure", idempotencyKey: nil),
      context: context,
      risk: .high
    )
    memoryStore.append(success)
    memoryStore.append(failure)

    XCTAssertEqual(memoryStore.list(limit: 10, toolId: "", status: nil).map(\.invocationId), ["failure", "success"])
    XCTAssertEqual(memoryStore.list(limit: 10, toolId: success.toolId, status: .failed).map(\.errorCode), ["test_failure"])
    memoryStore.clear()
    XCTAssertEqual(memoryStore.list(limit: 10, toolId: "", status: nil), [])

    let root = try temporaryDirectory("native-tool-audit")
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = relativeFile("audit/records.json", under: root)
    let fileStore = FileAgentNativeToolAuditStore(fileURL: fileURL)
    fileStore.append(success)
    fileStore.append(failure)

    let restored = FileAgentNativeToolAuditStore(fileURL: fileURL)
    XCTAssertEqual(restored.list(limit: 10, toolId: "", status: nil).map(\.auditId), [failure.auditId, success.auditId])
    XCTAssertEqual(restored.list(limit: 1, toolId: "", status: nil).map(\.auditId), [failure.auditId])
    restored.clear()
    XCTAssertEqual(FileAgentNativeToolAuditStore(fileURL: fileURL).list(limit: 10, toolId: "", status: nil), [])
  }

  func testAgentActionNativeToolExecutorRunsLegacyExecutorThroughRegistry() throws {
    var capturedAction: AgentAction?
    var capturedScreen: AgentScreenContext?
    let descriptor = try nativeToolDescriptor(
      AgentNativeToolAgentActionAdapter.defaultToolId(.tap),
      risk: .medium
    )
    let delegate = TestAgentActionExecutor { action, screen in
      capturedAction = action
      capturedScreen = screen
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Tapped",
        metadata: ["screen": screen.pageTitle]
      )
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(
          descriptor: descriptor,
          executorId: "legacy.agent_action",
          provenanceMetadata: ["adapter": "AgentActionExecutor"]
        ),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Settings") }
      ))
    let legacy = AgentAction(
      id: "legacy-9",
      kind: .tap,
      target: "Wi-Fi",
      risk: .medium,
      status: .proposed,
      description: "Tap Wi-Fi",
      parameters: ["bounds": "[0,0][10,10]"]
    )
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(legacy, toolId: descriptor.id)

    let nativeResult = registry.invoke(call.toolId, input: call.input, context: call.context)
    let roundTripped = AgentNativeToolAgentActionAdapter.toAgentActionResult(nativeResult, actionId: legacy.id)

    XCTAssertTrue(nativeResult.toJson(), nativeResult.isSuccess)
    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(capturedAction?.id, "legacy-9")
    XCTAssertEqual(capturedAction?.kind, .tap)
    XCTAssertEqual(capturedAction?.target, "Wi-Fi")
    XCTAssertEqual(capturedAction?.parameters["bounds"], "[0,0][10,10]")
    XCTAssertTrue(capturedAction?.requiresConfirmation == true)
    XCTAssertEqual(capturedScreen?.pageTitle, "Settings")
    XCTAssertEqual(nativeResult.provenance.legacyAgentActionId, "legacy-9")
    XCTAssertEqual(nativeResult.provenance.executorId, "legacy.agent_action")
    XCTAssertTrue(roundTripped.success)
    XCTAssertEqual(roundTripped.metadata["native_tool_id"], descriptor.id)
    XCTAssertEqual(roundTripped.metadata["native_receipt_id"], "legacy-9")
  }

  func testAgentPhoneNativeToolCatalogBuildsExecutableActionDefinitions() throws {
    var captured: [AgentAction] = []
    let delegate = TestAgentActionExecutor { action, _ in
      captured.append(action)
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Executed \(action.kind.rawValue)"
      )
    }
    let executables = AgentPhoneNativeToolCatalog.actionExecutableDefinitions(
      delegate: delegate,
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Browser") },
      capabilityStatuses: readyPhoneCapabilityStatuses()
    )
    let openURL = try XCTUnwrap(
      executables.first { $0.id == AgentNativeToolAgentActionAdapter.defaultToolId(.openURL) }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(executables)
    let context = AgentNativeToolInvocationContext(
      invocationId: "open-url",
      grantedPermissions: Set(openURL.descriptor.requiredPermissions.filter { $0.required }.map(\.id)),
      grantedConsents: Set(openURL.descriptor.requiredConsents.filter { $0.required }.map(\.id))
    )

    let result = registry.invoke(
      openURL.id,
      input: [
        "target": .string("Safari"),
        "url": .string("https://galaxyssi.com"),
        "parameters": .object(["url": .string("https://galaxyssi.com")])
      ],
      context: context
    )

    XCTAssertEqual(Set(executables.map(\.id)), Set(AgentPhoneNativeToolCatalog.supportedActionKinds.map {
      AgentNativeToolAgentActionAdapter.defaultToolId($0)
    }))
    XCTAssertEqual(registry.ids(), Set(executables.map(\.id)))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(captured.first?.kind, .openURL)
    XCTAssertEqual(captured.first?.target, "Safari")
    XCTAssertEqual(captured.first?.parameters["url"], "https://galaxyssi.com")
    XCTAssertEqual(result.provenance.executorId, AgentPhoneNativeToolCatalog.actionExecutorId)
  }

  func testAgentActionNativeToolExecutorMapsLegacyFailuresToNativeFailures() throws {
    let descriptor = try nativeToolDescriptor(AgentNativeToolAgentActionAdapter.defaultToolId(.tap))
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: false, message: "Missed target")
    }
    let registry = try AgentNativeToolRegistry()
      .registerExecutable(AgentActionNativeToolExecutor.executableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "legacy.agent_action"),
        delegate: delegate,
        kind: .tap,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Settings") }
      ))
    let call = AgentNativeToolAgentActionAdapter.fromAgentAction(AgentAction(
      id: "legacy-failed",
      kind: .tap,
      target: "Wi-Fi",
      risk: .low,
      status: .proposed,
      description: "Tap Wi-Fi"
    ))

    let result = registry.invoke(call.toolId, input: call.input, context: call.context)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "agent_action_failed")
    XCTAssertEqual(result.output["action_id"], .string("legacy-failed"))
  }

}
