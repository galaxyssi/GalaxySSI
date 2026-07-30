import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentTeamCompletionSinkPublishesOneDurableConnectorResponse() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let deliveryLedger = AgentTeamCompletionDeliveryLedger()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: deliveryLedger,
      nowMillis: { 20_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "completion-supervisor",
      teamId: "completion-team",
      conversationId: "completion-conversation",
      taskId: "completion-turn",
      primaryAgentId: "lead",
      goal: "Produce one answer",
      state: .succeeded,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          role: "lead synthesizer",
          deliveryMode: .respond,
          status: .succeeded,
          output: "single final answer"
        )
      ],
      finalOutput: "single final answer",
      updatedAtMillis: 10_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertFalse(sink.publish(snapshot))
    let pending = responseStore.pending()

    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].content, "single final answer")
    XCTAssertEqual(pending[0].turnId, "completion-turn")
    XCTAssertEqual(pending[0].taskId, "completion-turn")
    XCTAssertEqual(pending[0].conversationId, "completion-conversation")
    XCTAssertEqual(pending[0].contactId, AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId))
    XCTAssertEqual(pending[0].sourceMessageId, AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId))
    XCTAssertTrue(pending[0].success)
    XCTAssertEqual(pending[0].receivedAtMillis, 20_000)
    XCTAssertEqual(deliveryLedger.snapshot(), ["completion-supervisor"])

    sink.remove(supervisorRunId: "completion-supervisor")
    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertEqual(responseStore.pending().count, 2)
  }

  func testAgentTeamCompletionSinkPublishesFailureResponseWithReason() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: AgentTeamCompletionDeliveryLedger(),
      nowMillis: { 3_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "failed-supervisor",
      teamId: "failed-team",
      taskId: "failed-turn",
      primaryAgentId: "lead",
      state: .failed,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          deliveryMode: .respond,
          status: .failed,
          errorMessage: "primary Agent timed out"
        )
      ],
      updatedAtMillis: 2_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    let response = responseStore.pending().first

    XCTAssertEqual(response?.success, false)
    XCTAssertEqual(response?.content, "Agent team failed: primary Agent timed out")
    XCTAssertEqual(response?.contactId, "agent-team:failed-team")
    XCTAssertEqual(response?.receivedAtMillis, 3_000)
  }

  func testAgentManagedResponseLedgerCompletesAcknowledgesAndPublishesLateResponses() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    AgentLateManagedResponseBus.shared.clear()
    var lateResponses: [AgentManagedResponseRecord] = []
    let token = AgentLateManagedResponseBus.shared.addListener { lateResponses.append($0) }
    defer {
      AgentLateManagedResponseBus.shared.removeListener(token)
    }

    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-old",
      supervisorRunId: "supervisor",
      agentId: "observer",
      deliveryMode: .observe,
      sourceMessageId: 41,
      contactId: "observer",
      createdAtMillis: 1_000
    ))
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 42,
      contactId: "primary",
      createdAtMillis: 2_000
    ))

    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old", "child-primary"])
    XCTAssertNil(ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "other", content: "wrong")))

    let response = AgentConnectorResponse(
      sourceMessageId: 42,
      contactId: "",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )
    let completed = try XCTUnwrap(ledger.complete(response))

    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(completed.completedAtMillis, 9_000)
    XCTAssertEqual(lateResponses.map(\.ownerRunId), ["child-primary"])
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    _ = ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "primary", content: "duplicate"))
    XCTAssertEqual(lateResponses.count, 1)

    let acknowledged = try XCTUnwrap(ledger.acknowledge(response))
    XCTAssertEqual(acknowledged.state, .applied)
    XCTAssertTrue(ledger.completedUnapplied().isEmpty)
    ledger.removeOwner("child-primary")
    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old"])
  }

  func testAgentManagedResponseCodecUsesAndroidWireNamesAndBoundsPayloads() throws {
    let content = String(repeating: "a", count: AgentConnectorResponse.maxContentCharacters + 50)
    let rich = String(repeating: "b", count: AgentConnectorResponse.maxRichOutputCharacters + 50)
    let record = AgentManagedResponseRecord(
      ownerRunId: "child",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 77,
      contactId: "primary",
      state: .completed,
      response: AgentConnectorResponse(
        sourceMessageId: 77,
        contactId: "primary",
        content: content,
        conversationId: "conversation",
        turnId: "turn",
        taskId: "task",
        inputTokens: 11,
        outputTokens: 22,
        costMicros: 33,
        richOutputJson: rich,
        receivedAtMillis: 4_000
      ),
      createdAtMillis: 1_000,
      completedAtMillis: 4_000
    )

    let encoded = AgentManagedResponseCodec.encode([record])
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.first)
    let response = try XCTUnwrap(object["response"] as? [String: Any])
    let decoded = AgentManagedResponseCodec.decode(encoded)

    XCTAssertEqual(object["owner_run_id"] as? String, "child")
    XCTAssertEqual(object["supervisor_run_id"] as? String, "supervisor")
    XCTAssertEqual(object["delivery_mode"] as? String, "RESPOND")
    XCTAssertEqual(object["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["conversation_id"] as? String, "conversation")
    XCTAssertEqual(response["turn_id"] as? String, "turn")
    XCTAssertEqual(response["input_tokens"] as? Int, 11)
    XCTAssertEqual((response["content"] as? String)?.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual((response["rich_output"] as? String)?.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertNil(object["ownerRunId"])
    XCTAssertEqual(decoded.first?.response?.content.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual(decoded.first?.response?.richOutputJson.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertTrue(AgentManagedResponseCodec.decode(#"[{"owner_run_id":"","source_message_id":0}]"#).isEmpty)
  }

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

  func testAgentConnectorResponseBusInterceptsManagedResponsesOnce() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(registry: registry, store: store, nowMillis: { 10_000 })
    var intercepted: [AgentConnectorResponse] = []
    try registry.register(
      sourceMessageId: 73,
      contactId: "codex",
      ownerId: "managed-run"
    ) { response in
      intercepted.append(response)
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "Reviewed result",
      inputTokens: 10,
      outputTokens: 4
    )

    XCTAssertTrue(bus.publish(response))
    XCTAssertFalse(registry.consume(response))
    XCTAssertEqual(intercepted.map(\.content), ["Reviewed result"])
    XCTAssertTrue(store.pending().isEmpty)

    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(store.pending().map(\.content), ["Reviewed result"])
  }

  func testAgentConnectorResponseBusCompletesManagedLedgerBeforeStore() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 9001,
      contactId: "primary",
      createdAtMillis: 1_000
    ))
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: ledger,
      store: store,
      nowMillis: { 10_000 }
    )

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )))
    XCTAssertTrue(store.pending().isEmpty)
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "duplicate",
      receivedAtMillis: 9_500
    )))
    XCTAssertTrue(store.pending().isEmpty)
  }

  func testAgentConnectorResponseBusFallbacksRichOutputAndNotifiesListeners() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      store: store,
      nowMillis: { 10_000 }
    )
    let rich = #"{"version":1,"blocks":[{"type":"text","text":"Rendered rich answer","title":"","fallback_text":"","uri":""}]}"#
    var notified: [AgentConnectorResponse] = []
    let token = bus.addListener { notified.append($0) }
    defer { bus.removeListener(token) }

    XCTAssertFalse(bus.publish(AgentConnectorResponse(
      sourceMessageId: 501,
      contactId: "codex",
      content: "",
      richOutputJson: rich
    )))

    XCTAssertEqual(store.pending().map(\.content), ["Rendered rich answer"])
    XCTAssertEqual(notified.map(\.content), ["Rendered rich answer"])
    XCTAssertFalse(store.pending().first?.richOutputJson.isEmpty ?? true)
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 0, content: "invalid")))
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 502, content: "", richOutputJson: "{}")))
  }

  func testAgentConnectorResponseStoreBoundsDedupeExpiryAndAndroidWireNames() throws {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    for index in 0..<35 {
      store.append(AgentConnectorResponse(
        sourceMessageId: Int64(index + 1),
        contactId: "codex",
        content: "answer-\(index)",
        receivedAtMillis: Int64(index + 1)
      ))
    }
    XCTAssertEqual(store.pending().count, AgentConnectorResponseStore.maxResponses)
    XCTAssertEqual(store.pending().first?.sourceMessageId, 6)

    store.append(AgentConnectorResponse(
      sourceMessageId: 35,
      contactId: "codex",
      content: "replacement",
      receivedAtMillis: 101_000
    ))
    XCTAssertEqual(store.pending().filter { $0.sourceMessageId == 35 && $0.contactId == "codex" }.count, 1)
    XCTAssertEqual(store.pending().last?.content, "replacement")

    let encoded = store.serializedSnapshot()
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.last)
    XCTAssertEqual(object["source_message_id"] as? Int, 35)
    XCTAssertEqual(object["received_at"] as? Int, 101_000)
    XCTAssertNil(object["received_at_millis"])
    XCTAssertNil(object["sourceMessageId"])

    let stale = AgentConnectorResponseStoreCodec.encode([
      AgentConnectorResponse(
        sourceMessageId: 900,
        contactId: "codex",
        content: "old",
        receivedAtMillis: 100_000 - AgentConnectorResponseStore.maxResponseAgeMillis - 1
      )
    ])
    XCTAssertTrue(AgentConnectorResponseStore(serialized: stale, nowMillis: { 100_000 }).pending().isEmpty)

    store.remove(AgentConnectorResponse(sourceMessageId: 35, contactId: "codex", content: ""))
    XCTAssertFalse(store.pending().contains { $0.sourceMessageId == 35 && $0.contactId == "codex" })
  }

  func testAgentActionRecoveryModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder.signalASI.decode(
      AgentActionResult.self,
      from: Data(#"{"action_id":"home-1","success":false,"message":"Timed out","metadata":{"code":"timeout"}}"#.utf8)
    )
    XCTAssertEqual(decoded.actionId, "home-1")
    XCTAssertFalse(decoded.success)
    XCTAssertEqual(decoded.metadata["code"], "timeout")

    let observation = agentObservation(.changedAndStable, sampleCount: 2, durationMillis: 500, changed: true, stable: true)
    let encoded = try JSONEncoder.signalASI.encode(observation)
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
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
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
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
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
    XCTAssertEqual(result.metadata["execution_authority"], "signalasi-phone")
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
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(snapshot), as: UTF8.self)
    let decoded = try JSONDecoder.signalASI.decode(
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
