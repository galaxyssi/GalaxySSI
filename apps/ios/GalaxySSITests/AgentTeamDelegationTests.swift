import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentCrossTeamDelegationLaunchRequestUsesIsolatedContext() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam()
    let input = crossTeamInput(
      constraints: ["Use public evidence only"],
      expectedOutput: "A concise verified answer",
      evidence: [
        AgentDelegationEvidence(
          evidenceId: "evidence-one",
          summary: "The API changed in the latest release.",
          sourceAgentId: "hermes-source",
          contentHash: "ABC123"
        )
      ]
    )

    let prepared = try fixture.coordinator.prepare(
      input: input,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let admission = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let request = try XCTUnwrap(admission.launchSpec?.request)

    XCTAssertEqual(admission.record.state, .authorized)
    XCTAssertEqual(request.conversationId, "delegation:\(input.delegationId)")
    XCTAssertEqual(request.parentRunId, input.sourceRunId)
    XCTAssertEqual(request.requiredCapabilities, Set([AgentCapability.chat]))
    XCTAssertTrue(request.goal.contains("Use public evidence only"))
    XCTAssertTrue(request.goal.contains("The API changed in the latest release."))
    XCTAssertNil(request.context["conversation_history"])
    XCTAssertNil(request.context["internal_memory"])
    XCTAssertNil(request.context["system_prompt"])
    XCTAssertNil(request.context["checkpoint"])
    XCTAssertEqual(request.context["cross_team_delegation"]?.boolValue, true)
  }

  func testAgentCrossTeamDelegationArtifactManifestWaitsForGrantAndOmitsUris() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam()
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(artifacts: [
        AgentDelegationArtifactManifest(
          artifactId: "artifact-one",
          name: "report.pdf",
          mimeType: "APPLICATION/PDF",
          contentHash: "DEADBEEF",
          sizeBytes: 1_024
        )
      ]),
      destination: destination,
      registrations: crossTeamRegistrations()
    )

    XCTAssertEqual(prepared.state, .waitingConfirmation)
    _ = try fixture.grants.grant(crossTeamGrant(subjectId: "codex-destination", lifetime: .permanent))
    let admitted = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: crossTeamRegistrations()
    )
    let encoded = AgentCrossTeamDelegationCodec.encodeEnvelope(admitted.record.envelope)

    XCTAssertEqual(admitted.record.state, .authorized)
    XCTAssertNotNil(admitted.launchSpec)
    XCTAssertTrue(encoded.contains("artifact-one"))
    XCTAssertTrue(encoded.contains("application/pdf"))
    XCTAssertFalse(encoded.contains("content://"))
    XCTAssertFalse(encoded.contains("file://"))
    XCTAssertFalse(encoded.contains("\"uri\""))
  }

  func testAgentCrossTeamDelegationResumesDispatchesAndReturnsPrimaryOutputOnly() throws {
    let fixture = crossTeamFixture()
    let destination = crossTeamDestinationTeam(includeObserver: true)
    let registrations = crossTeamRegistrations(includeObserver: true)
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(),
      destination: destination,
      registrations: registrations
    )
    let firstAdmission = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: registrations
    )
    let resumed = try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: destination,
      registrations: registrations
    )
    let request = try XCTUnwrap(resumed.launchSpec?.request)

    XCTAssertEqual(firstAdmission.record.state, .authorized)
    XCTAssertEqual(firstAdmission.launchSpec?.request.runId, request.runId)
    let dispatched = try fixture.coordinator.markDispatched(
      delegationId: prepared.envelope.delegationId,
      destinationRunId: request.runId
    )
    let finished = try fixture.coordinator.finish(
      delegationId: prepared.envelope.delegationId,
      snapshot: AgentTeamExecutionSnapshot(
        supervisorRunId: dispatched.destinationRunId,
        teamId: destination.teamId,
        taskId: "delegated-task",
        primaryAgentId: destination.primaryAgentId,
        state: .succeeded,
        members: [
          AgentTeamMemberSnapshot(
            agentId: destination.primaryAgentId,
            deliveryMode: .respond,
            status: .succeeded,
            output: "Final delegated result"
          ),
          AgentTeamMemberSnapshot(
            agentId: "hermes-observer",
            deliveryMode: .observe,
            status: .succeeded,
            output: "Private observer evidence"
          )
        ],
        finalOutput: "Final delegated result",
        updatedAtMillis: crossTeamNow + 1_000
      )
    )

    XCTAssertEqual(dispatched.state, .dispatched)
    XCTAssertEqual(finished.state, .returned)
    XCTAssertEqual(finished.resultSummary, "Final delegated result")
    XCTAssertFalse(finished.resultSummary.contains("Private observer evidence"))
  }

  func testAgentCrossTeamDelegationCodecAndDenialsUseAndroidContract() throws {
    let fixture = crossTeamFixture()
    let prepared = try fixture.coordinator.prepare(
      input: crossTeamInput(
        constraints: ["No network writes"],
        evidence: [AgentDelegationEvidence(evidenceId: "evidence-one", summary: "A bounded summary", sourceAgentId: "source-agent")]
      ),
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    let encodedEnvelope = AgentCrossTeamDelegationCodec.encodeEnvelope(prepared.envelope)
    let encodedRecords = AgentCrossTeamDelegationCodec.encodeRecords([prepared])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encodedEnvelope.utf8)) as? [String: Any])
    let returnContract = try XCTUnwrap(object["return_contract"] as? [String: Any])

    XCTAssertEqual(object["delegation_id"] as? String, "delegation-one")
    XCTAssertEqual(object["source_team_id"] as? String, "team-source")
    XCTAssertEqual(returnContract["maximum_characters"] as? Int, 16_000)
    XCTAssertNil(object["delegationId"])
    XCTAssertEqual(AgentCrossTeamDelegationCodec.decodeEnvelope(encodedEnvelope), prepared.envelope)
    XCTAssertEqual(AgentCrossTeamDelegationCodec.decodeRecords(encodedRecords), [prepared])
    XCTAssertFalse(encodedEnvelope.contains("conversation_history"))
    XCTAssertFalse(encodedEnvelope.contains("internal_memory"))
    XCTAssertFalse(encodedEnvelope.contains("system_prompt"))

    let denied = try fixture.coordinator.prepare(
      input: crossTeamInput(delegationId: "delegation-denied", nonce: "delegation-nonce-0002", delegationDepth: 4),
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    let deniedAdmission = try fixture.coordinator.admit(
      delegationId: denied.envelope.delegationId,
      destination: crossTeamDestinationTeam(),
      registrations: crossTeamRegistrations()
    )
    XCTAssertEqual(denied.state, .denied)
    XCTAssertTrue(denied.policyReasonCodes.contains("delegation_depth_exceeded"))
    XCTAssertNil(deniedAdmission.launchSpec)

    let changed = AgentTeamDefinition(
      teamId: crossTeamDestinationTeam().teamId,
      primaryAgentId: "codex-destination",
      members: crossTeamDestinationTeam().members + [
        AgentTeamMember(
          agentId: "unreviewed-agent",
          deliveryMode: .observe,
          requiredCapabilities: [.chat],
          role: "observer",
          objective: "",
          dependsOnAgentIds: [],
          context: [:]
        )
      ],
      visibilityMode: .background,
      collectiveCapabilities: [.chat]
    )
    XCTAssertThrowsError(try fixture.coordinator.admit(
      delegationId: prepared.envelope.delegationId,
      destination: changed,
      registrations: crossTeamRegistrations()
    )) { error in
      XCTAssertTrue("\(error)".contains("members changed"))
    }
  }

  func testAgentActionRecoveryModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.galaxySSI.decode(
      AgentActionResult.self,
      from: Data(#"{"action_id":"home-1","success":false,"message":"Timed out","metadata":{"code":"timeout"}}"#.utf8)
    )
    XCTAssertEqual(decoded.actionId, "home-1")
    XCTAssertFalse(decoded.success)
    XCTAssertEqual(decoded.metadata["code"], "timeout")

    let observation = agentObservation(.changedAndStable, sampleCount: 2, durationMillis: 500, changed: true, stable: true)
    let encoded = try JSONEncoder.galaxySSI.encode(observation)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let screen = try XCTUnwrap(object["screen"] as? [String: Any])

    XCTAssertEqual(object["decision"] as? String, "CHANGED_AND_STABLE")
    XCTAssertEqual(object["sample_count"] as? Int, 2)
    XCTAssertEqual(object["duration_millis"] as? Int, 500)
    XCTAssertEqual(object["screen_changed"] as? Bool, true)
    XCTAssertEqual(object["screen_stable"] as? Bool, true)
    XCTAssertEqual(screen["foreground_app"] as? String, "SpringBoard")
    XCTAssertEqual(screen["visible_text_count"] as? Int, 3)
  }

  func testAgentContinuousObservationControllerReturnsFailureAndNoChangeOutcomes() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let after = agentObservationScreen(pageTitle: "After", visibleTextCount: 2)
    let controller = AgentContinuousObservationController(maxSamples: 3, stableSampleCount: 2, sampleIntervalMillis: 10)

    let failed = controller.observe(
      beforeAction: before,
      actionSucceeded: false,
      changeExpected: true,
      capture: { after },
      sleep: { _ in XCTFail("Failure observation should not sleep") },
      nowMillis: { 1_000 }
    )
    let noChange = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: false,
      capture: { before },
      sleep: { _ in XCTFail("No-change observation should not sleep") },
      nowMillis: { 2_000 }
    )

    XCTAssertEqual(failed.decision, .actionFailed)
    XCTAssertEqual(failed.sampleCount, 1)
    XCTAssertEqual(failed.durationMillis, 0)
    XCTAssertTrue(failed.screenChanged)
    XCTAssertFalse(failed.screenStable)
    XCTAssertTrue(failed.evidence.contains("decision=ACTION_FAILED"))

    XCTAssertEqual(noChange.decision, .noChangeRequired)
    XCTAssertEqual(noChange.sampleCount, 1)
    XCTAssertFalse(noChange.screenChanged)
    XCTAssertTrue(noChange.screenStable)
    XCTAssertTrue(noChange.evidence.contains("stable=true"))
  }

  func testAgentContinuousObservationControllerWaitsForChangedStableScreen() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let changed = agentObservationScreen(pageTitle: "After", visibleTextCount: 2, selectedText: " Done\nnow ")
    var now: Int64 = 1_000
    var captures = 0
    var sleepIntervals: [Int64] = []
    let controller = AgentContinuousObservationController(maxSamples: 4, stableSampleCount: 2, sampleIntervalMillis: 10)

    let outcome = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: {
        captures += 1
        return changed
      },
      sleep: { millis in
        sleepIntervals.append(millis)
        now += millis
      },
      nowMillis: { now }
    )

    XCTAssertEqual(outcome.decision, .changedAndStable)
    XCTAssertEqual(outcome.sampleCount, 2)
    XCTAssertEqual(outcome.durationMillis, 10)
    XCTAssertTrue(outcome.screenChanged)
    XCTAssertTrue(outcome.screenStable)
    XCTAssertEqual(captures, 2)
    XCTAssertEqual(sleepIntervals, [10])
    XCTAssertTrue(outcome.evidence.contains("samples=2"))
  }

  func testAgentContinuousObservationControllerReportsTimeoutAndUnstableChanges() {
    let before = agentObservationScreen(pageTitle: "Before", visibleTextCount: 1)
    let first = agentObservationScreen(pageTitle: "First", visibleTextCount: 2)
    let second = agentObservationScreen(pageTitle: "Second", visibleTextCount: 3)
    let controller = AgentContinuousObservationController(maxSamples: 3, stableSampleCount: 2, sampleIntervalMillis: 5)

    let timeout = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: { before },
      sleep: { _ in },
      nowMillis: { 5_000 }
    )
    var unstableIndex = 0
    let unstableScreens = [first, second, first]
    let unstable = controller.observe(
      beforeAction: before,
      actionSucceeded: true,
      changeExpected: true,
      capture: {
        defer { unstableIndex += 1 }
        return unstableScreens[min(unstableIndex, unstableScreens.count - 1)]
      },
      sleep: { _ in },
      nowMillis: { 6_000 }
    )

    XCTAssertEqual(timeout.decision, .timedOut)
    XCTAssertEqual(timeout.sampleCount, 3)
    XCTAssertFalse(timeout.screenChanged)
    XCTAssertFalse(timeout.screenStable)
    XCTAssertTrue(timeout.evidence.contains("decision=TIMED_OUT"))

    XCTAssertEqual(unstable.decision, .changedButUnstable)
    XCTAssertEqual(unstable.sampleCount, 3)
    XCTAssertTrue(unstable.screenChanged)
    XCTAssertFalse(unstable.screenStable)
    XCTAssertTrue(unstable.evidence.contains("decision=CHANGED_BUT_UNSTABLE"))
  }

  func testAgentObservationContextStoreObservesDedupesAndFiltersConversationScope() throws {
    var now: Int64 = 1_000
    var nextId = 0
    let store = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { nextId += 1 }
        return "observation-\(nextId)"
      }
    )

    let first = try XCTUnwrap(store.observe(
      targetId: " codex ",
      text: " Needs review ",
      conversationId: " conversation-a ",
      taskId: " task-a "
    ))
    now = 2_000
    let duplicate = try XCTUnwrap(store.observe(
      targetId: "codex",
      text: "Needs review",
      conversationId: "conversation-a",
      taskId: "task-a"
    ))
    _ = store.observe(targetId: "codex", text: "Global hint")
    _ = store.observe(targetId: "codex", text: "Other conversation", conversationId: "conversation-b")

    let scoped = store.peek(targetId: " codex ", conversationId: "conversation-a")
    let unscoped = store.peek(targetId: "codex")

    XCTAssertEqual(first.id, "observation-0")
    XCTAssertEqual(duplicate.id, "observation-1")
    XCTAssertEqual(duplicate.targetId, "codex")
    XCTAssertEqual(duplicate.text, "Needs review")
    XCTAssertEqual(duplicate.conversationId, "conversation-a")
    XCTAssertEqual(duplicate.taskId, "task-a")
    XCTAssertEqual(duplicate.createdAtMillis, 2_000)
    XCTAssertEqual(duplicate.expiresAtMillis, 2_000 + AgentObservedContext.defaultTTLMillis)
    XCTAssertEqual(scoped.map(\.id), ["observation-1", "observation-2"])
    XCTAssertEqual(unscoped.map(\.id), ["observation-1", "observation-2", "observation-3"])
    XCTAssertNil(store.observe(targetId: " ", text: "ignored"))
    XCTAssertNil(store.observe(targetId: "codex", text: " "))
  }

  func testAgentObservationContextStoreExpiresAcknowledgesClearsAndBoundsEntries() throws {
    var now: Int64 = 10_000
    let valid = AgentObservedContext(
      id: "valid",
      targetId: "codex",
      text: "Fresh context",
      conversationId: "conversation",
      taskId: "task",
      createdAtMillis: 9_000,
      expiresAtMillis: 20_000
    )
    let expired = AgentObservedContext(
      id: "expired",
      targetId: "codex",
      text: "Old context",
      createdAtMillis: 1_000,
      expiresAtMillis: 9_999
    )
    let invalid = AgentObservedContext(
      id: "invalid",
      targetId: "",
      text: "Missing target",
      createdAtMillis: 9_000,
      expiresAtMillis: 20_000
    )
    let store = InMemoryAgentObservationContextStore(
      serialized: AgentObservationContextJsonCodec.encode([expired, invalid, valid]),
      clock: { now },
      idFactory: { "new" }
    )

    XCTAssertEqual(store.peek(targetId: "codex").map(\.id), ["valid"])
    XCTAssertEqual(store.acknowledge(entryIds: ["missing"]), 0)
    XCTAssertEqual(store.acknowledge(entryIds: ["valid"]), 1)
    XCTAssertTrue(store.peek(targetId: "codex").isEmpty)

    _ = store.observe(targetId: "codex", text: "A")
    _ = store.observe(targetId: "other", text: "B")
    XCTAssertEqual(store.clearTarget(" codex "), 1)
    XCTAssertEqual(store.peek(targetId: "other").map(\.text), ["B"])
    store.clear()
    XCTAssertEqual(AgentObservationContextJsonCodec.decode(store.serializedSnapshot(), nowMillis: now), [])

    now = 1_000
    var boundedSeed = 0
    let bounded = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { boundedSeed += 1 }
        return "bounded-\(boundedSeed)"
      }
    )
    for index in 0..<18 {
      now = Int64(1_000 + index)
      _ = bounded.observe(targetId: "codex", text: "target-entry-\(index)")
    }
    XCTAssertEqual(bounded.peek(targetId: "codex").count, 16)
    XCTAssertEqual(bounded.peek(targetId: "codex").first?.text, "target-entry-2")

    var totalSeed = 0
    let total = InMemoryAgentObservationContextStore(
      clock: { now },
      idFactory: {
        defer { totalSeed += 1 }
        return "total-\(totalSeed)"
      }
    )
    for index in 0..<130 {
      now = Int64(2_000 + index)
      _ = total.observe(targetId: "target-\(index)", text: "total-entry-\(index)")
    }
    let decoded = AgentObservationContextJsonCodec.decode(total.serializedSnapshot(), nowMillis: now)
    XCTAssertEqual(decoded.count, 128)
    XCTAssertFalse(decoded.contains { $0.targetId == "target-0" })
    XCTAssertEqual(decoded.first?.targetId, "target-2")
    XCTAssertEqual(decoded.last?.targetId, "target-129")
  }

  func testAgentObservationContextCodecUsesAndroidWireNamesAndBoundsPayloads() throws {
    let longText = String(repeating: "x", count: 8_050)
    let context = AgentObservedContext(
      id: "context",
      targetId: String(repeating: "t", count: 200),
      text: longText,
      conversationId: String(repeating: "c", count: 200),
      taskId: "task",
      createdAtMillis: 1_000,
      expiresAtMillis: 2_000
    )
    let encoded = AgentObservationContextJsonCodec.encode([context])
    let object = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])?.first
    )
    let decoded = AgentObservationContextJsonCodec.decode(
      """
      [
        "ignored",
        {"id":"blank","target_id":"","text":"ignored","created_at_millis":1,"expires_at_millis":9999},
        {"id":"expired","target_id":"codex","text":"old","created_at_millis":1,"expires_at_millis":999},
        \(encoded.dropFirst().dropLast())
      ]
      """,
      nowMillis: 1_500
    )

    XCTAssertEqual(object["id"] as? String, "context")
    XCTAssertEqual((object["target_id"] as? String)?.count, 160)
    XCTAssertEqual((object["text"] as? String)?.count, 8_000)
    XCTAssertEqual((object["conversation_id"] as? String)?.count, 160)
    XCTAssertEqual(object["task_id"] as? String, "task")
    XCTAssertEqual((object["created_at_millis"] as? NSNumber)?.int64Value, Int64(1_000))
    XCTAssertEqual((object["expires_at_millis"] as? NSNumber)?.int64Value, Int64(2_000))
    XCTAssertEqual(decoded, [context])
    XCTAssertTrue(context.isExpired(nowMillis: 2_000))
    XCTAssertFalse(context.isExpired(nowMillis: 1_999))
    XCTAssertEqual(AgentObservationContextJsonCodec.decode("not-json", nowMillis: 1_500), [])
  }

  func testPhoneExecutionAuthorityAnnotatesConcurrentReadsWithoutSerialization() {
    let action = phoneAuthorityAction(
      id: "read-1",
      kind: .readScreen,
      taskId: "task-read"
    )
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "screen read",
        metadata: ["delegate": "called"]
      )
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["delegate"], "called")
    XCTAssertEqual(result.metadata["execution_location"], "phone")
    XCTAssertEqual(result.metadata["execution_authority"], "galaxyssi-phone")
    XCTAssertEqual(result.metadata["task_id"], "task-read")
    XCTAssertEqual(result.metadata["serialized_side_effect"], "false")
  }

  func testPhoneExecutionAuthoritySerializesSideEffectsAndReportsActiveTask() {
    let taskId = "task-side-effect-\(UUID().uuidString)"
    let action = phoneAuthorityAction(
      id: "open-1",
      kind: .openApp,
      taskId: taskId
    )
    var observedSnapshot = PhoneExecutionAuthoritySnapshot()
    let delegate = TestAgentActionExecutor { action, _ in
      observedSnapshot = PhoneExecutionAuthority.snapshot()
      return AgentActionResult(actionId: action.id, success: true, message: "opened")
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(observedSnapshot.activeSideEffectTaskId, taskId)
    XCTAssertEqual(result.metadata["serialized_side_effect"], "true")
    XCTAssertEqual(result.metadata["execution_authority"], "galaxyssi-phone")
    XCTAssertEqual(PhoneExecutionAuthority.snapshot().activeSideEffectTaskId, "")
  }

  func testPhoneExecutionAuthorityCancellationReturnsAndroidMetadataWithoutDelegate() {
    let taskId = "task-cancel-\(UUID().uuidString)"
    PhoneExecutionAuthority.requestCancellation(taskId: taskId)
    defer { PhoneExecutionAuthority.clearCancellation(taskId: taskId) }
    let action = phoneAuthorityAction(
      id: "tap-1",
      kind: .tap,
      taskId: taskId
    )
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "unexpected")
    }
    let guarded = PhoneExecutionAuthority.guarded(delegate)

    let result = guarded.execute(action: action, screen: phoneAuthorityScreen())

    XCTAssertEqual(delegate.callCount, 0)
    XCTAssertFalse(result.success)
    XCTAssertEqual(result.message, "Phone tool execution was cancelled")
    XCTAssertEqual(result.metadata["execution_location"], "phone")
    XCTAssertEqual(result.metadata["execution_authority"], "galaxyssi-phone")
    XCTAssertEqual(result.metadata["task_id"], taskId)
    XCTAssertEqual(result.metadata["cancelled"], "true")
    XCTAssertTrue(PhoneExecutionAuthority.isCancelled(taskId: taskId))
    XCTAssertGreaterThanOrEqual(PhoneExecutionAuthority.snapshot().cancelledTaskCount, 1)
  }

  func testPhoneExecutionAuthoritySnapshotUsesAndroidWireNames() throws {
    let snapshot = PhoneExecutionAuthoritySnapshot(
      activeSideEffectTaskId: "task-1",
      queuedSideEffectTasks: 2,
      cancelledTaskCount: 3
    )
    let encoded = String(decoding: try JSONEncoder.galaxySSI.encode(snapshot), as: UTF8.self)
    let decoded = try JSONDecoder.galaxySSI.decode(
      PhoneExecutionAuthoritySnapshot.self,
      from: Data(
        #"{"active_side_effect_task_id":"task-2","queued_side_effect_tasks":4,"cancelled_task_count":5}"#.utf8
      )
    )

    XCTAssertTrue(encoded.contains(#""active_side_effect_task_id":"task-1""#))
    XCTAssertTrue(encoded.contains(#""queued_side_effect_tasks":2"#))
    XCTAssertTrue(encoded.contains(#""cancelled_task_count":3"#))
    XCTAssertEqual(decoded.activeSideEffectTaskId, "task-2")
    XCTAssertEqual(decoded.queuedSideEffectTasks, 4)
    XCTAssertEqual(decoded.cancelledTaskCount, 5)
  }

  func testAgentActionRecoveryRetriesLowRiskNavigationTimeoutOnce() {
    var retryCount = 0
    let failed = AgentActionResult(actionId: "home-1", success: false, message: "Timed out")
    let outcome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-1", kind: .home, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(
        result: AgentActionResult(actionId: "home-1", success: true, message: "Home opened"),
        observation: agentObservation(.changedAndStable, sampleCount: 2, durationMillis: 250, changed: true, stable: true)
      )
    }

    XCTAssertEqual(retryCount, 1)
    XCTAssertEqual(outcome.decision, .retrySucceeded)
    XCTAssertEqual(outcome.attemptCount, 1)
    XCTAssertEqual(outcome.result?.success, true)
    XCTAssertEqual(outcome.observation.decision, .changedAndStable)
  }

  func testAgentActionRecoveryRequiresManualForUnsafeOrNonTimeoutFailures() {
    let failed = AgentActionResult(actionId: "tap-1", success: false, message: "Timed out")
    var retryCount = 0

    let unsafeTap = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "tap-1", kind: .tap, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let highRiskHome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-1", kind: .home, risk: .high),
      failedResult: failed,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let nonTimeoutHome = AgentActionRecoveryController().recover(
      action: agentRecoveryAction(id: "home-2", kind: .home, risk: .low),
      failedResult: failed,
      failedObservation: agentObservation(.actionFailed, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }

    XCTAssertEqual(unsafeTap.decision, .manualRequired)
    XCTAssertEqual(highRiskHome.decision, .manualRequired)
    XCTAssertEqual(nonTimeoutHome.decision, .manualRequired)
    XCTAssertEqual(retryCount, 0)
  }

  func testAgentActionRecoverySkipsRetryWhenFailureIsAbsent() {
    var retryCount = 0
    let successful = AgentActionResult(actionId: "open-1", success: true, message: "Opened")
    let controller = AgentActionRecoveryController()

    let nilResult = controller.recover(
      action: agentRecoveryAction(id: "open-1", kind: .openApp, risk: .low),
      failedResult: nil,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }
    let successResult = controller.recover(
      action: agentRecoveryAction(id: "open-1", kind: .openApp, risk: .low),
      failedResult: successful,
      failedObservation: agentObservation(.timedOut, changed: false, stable: false)
    ) {
      retryCount += 1
      return AgentRecoveryAttempt(result: nil, observation: agentObservation(.timedOut))
    }

    XCTAssertEqual(nilResult.decision, .notNeeded)
    XCTAssertEqual(successResult.decision, .notNeeded)
    XCTAssertEqual(retryCount, 0)
  }

}
