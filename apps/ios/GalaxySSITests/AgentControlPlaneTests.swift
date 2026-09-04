import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentProtocolNegotiatorSelectsHighestCompatibleVersionAndCommonFeatures() {
    let local = AgentProtocolRange(
      preferred: "1.3",
      minimum: "1.0",
      maximum: "1.4",
      features: ["run.cancel", "run.recover", "message.observe"]
    )
    let remote = AgentProtocolRange(
      preferred: "1.2",
      minimum: "1.1",
      maximum: "1.2",
      features: ["run.cancel", "message.observe", "provider.list"]
    )

    let agreement = AgentProtocolNegotiator.negotiate(local: local, remote: remote)

    XCTAssertEqual(agreement?.version, "1.2")
    XCTAssertEqual(agreement?.features, Set(["run.cancel", "message.observe"]))
  }

  func testAgentProtocolNegotiatorRejectsIncompatibleOrInvalidRanges() {
    XCTAssertNil(
      AgentProtocolNegotiator.negotiate(
        local: AgentProtocolRange(preferred: "1.0", minimum: "1.0", maximum: "1.1"),
        remote: AgentProtocolRange(preferred: "2.0", minimum: "2.0", maximum: "2.2")
      )
    )
    XCTAssertNil(
      AgentProtocolNegotiator.negotiate(
        local: AgentProtocolRange(preferred: "1.0", minimum: "bad", maximum: "1.1"),
        remote: AgentProtocolRange(preferred: "1.0", minimum: "1.0", maximum: "1.1")
      )
    )
  }

  func testAgentControlMessageModelsUseAndroidWireNames() throws {
    let message = AgentControlMessage(
      messageId: "message-1",
      role: "assistant",
      text: "Verification patch is attached",
      attachments: [
        AgentArtifactReference(
          id: "patch",
          uri: "galaxyssi-workspace://task/patch.diff",
          name: "patch.diff",
          mimeType: "text/x-diff",
          metadataJson: #"{"sha256":"abc"}"#,
          createdAtMillis: 123
        )
      ],
      deliveryMode: .observe
    )

    let encoded = try JSONEncoder().encode(message)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let attachment = try XCTUnwrap((object["attachments"] as? [[String: Any]])?.first)
    let decoded = try JSONDecoder().decode(AgentControlMessage.self, from: encoded)
    let recoverable = AgentRecoverableRun(
      handle: AgentRunHandle(runId: "run", taskId: "task", agentId: "codex", remoteRunId: "remote"),
      lastEventSequence: 14,
      checkpoint: ["phase": .string("compile")]
    )
    let recoverableObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(recoverable)) as? [String: Any]
    )

    XCTAssertEqual(object["message_id"] as? String, "message-1")
    XCTAssertEqual(object["delivery_mode"] as? String, "OBSERVE")
    XCTAssertNil(object["messageId"])
    XCTAssertEqual(attachment["mime_type"] as? String, "text/x-diff")
    XCTAssertEqual(attachment["metadata_json"] as? String, #"{"sha256":"abc"}"#)
    XCTAssertEqual(decoded.deliveryMode, .observe)
    XCTAssertEqual(decoded.attachments.first?.uri, "galaxyssi-workspace://task/patch.diff")
    XCTAssertEqual(recoverableObject["last_event_sequence"] as? Int, 14)
  }

  func testAgentHandoffLifecycleUsesAndroidStableIdentityAndTerminalRules() {
    let first = AgentHandoffLifecycle.stableId(runId: "run", stepId: "compile", fromAgentId: "codex", toAgentId: "tester")
    let replay = AgentHandoffLifecycle.stableId(runId: "run", stepId: "compile", fromAgentId: "codex", toAgentId: "tester")
    let differentStep = AgentHandoffLifecycle.stableId(runId: "run", stepId: "verify", fromAgentId: "codex", toAgentId: "tester")
    let returned = AgentHandoffLifecycle.transition(current: .active, requested: .returned)

    XCTAssertEqual(first, "56d09990-3cd7-35c8-8ba8-c6957d925cd8")
    XCTAssertEqual(replay, first)
    XCTAssertNotEqual(first, differentStep)
    XCTAssertEqual(AgentHandoffLifecycle.transition(current: returned, requested: .active), .returned)
    XCTAssertEqual(AgentHandoffLifecycle.transition(current: .active, requested: .failed), .failed)
    XCTAssertEqual(AgentHandoffLifecycle.transition(current: .active, requested: .requested), .active)
  }

  func testAgentHandoffRequestCodecPreservesReturnPathCheckpointAndAndroidKeys() throws {
    let request = AgentHandoffRequest(
      handoffId: "handoff-1",
      conversationId: "conversation",
      taskId: "task",
      runId: "run",
      fromAgentId: "codex",
      toAgentId: "test-agent",
      returnToAgentId: "codex",
      reason: "Implementation is ready for verification",
      deliveryMode: .respond,
      requiredCapabilities: [.code, .taskExecution],
      artifactIds: ["patch", "patch"],
      checkpoint: ["sequence": .int(12)],
      context: ["handoff_scope": .string("verification")],
      createdAtMillis: 1_000
    )
    let record = AgentHandoffRecord(
      request: request,
      state: .active,
      sourceMessageId: 42,
      resultSummary: "waiting",
      updatedAtMillis: 2_000
    )

    let encoded = AgentHandoffJsonCodec.encode([record])
    let object = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])?.first
    )
    let decoded = try XCTUnwrap(AgentHandoffJsonCodec.decode(encoded).first)

    XCTAssertEqual(object["handoff_id"] as? String, "handoff-1")
    XCTAssertEqual(object["from_agent_id"] as? String, "codex")
    XCTAssertEqual(object["return_to_agent_id"] as? String, "codex")
    XCTAssertEqual(object["delivery_mode"] as? String, "RESPOND")
    XCTAssertNil(object["handoffId"])
    XCTAssertEqual(decoded.request.returnToAgentId, "codex")
    XCTAssertEqual(decoded.request.artifactIds, ["patch"])
    XCTAssertEqual(decoded.request.checkpoint["sequence"]?.intValue, Int64(12))
    XCTAssertEqual(decoded.request.context["handoff_scope"]?.stringValue, "verification")
    XCTAssertEqual(decoded.state, .active)
    XCTAssertEqual(decoded.sourceMessageId, 42)
  }

  func testAgentHandoffStoreBeginsIdempotentlyFinishesAndSkipsInvalidSnapshots() throws {
    var now: Int64 = 10_000
    let request = AgentHandoffRequest(
      handoffId: AgentHandoffLifecycle.stableId(runId: "run", stepId: "compile", fromAgentId: "codex", toAgentId: "tester"),
      conversationId: "conversation",
      taskId: "task",
      runId: "run",
      fromAgentId: "codex",
      toAgentId: "tester",
      reason: "verify",
      artifactIds: ["patch"],
      createdAtMillis: 9_000
    )
    let store = InMemoryAgentHandoffStore(serialized: #"[{"handoff_id":""}]"#, clock: { now })

    let created = try store.beginActive(request, sourceMessageId: 100)
    let replay = try store.beginActive(request, sourceMessageId: 200)

    XCTAssertTrue(created.created)
    XCTAssertFalse(replay.created)
    XCTAssertEqual(replay.record.sourceMessageId, 100)
    XCTAssertEqual(store.active().count, 1)
    XCTAssertEqual(store.forRun("run").count, 1)

    now = 11_000
    let returned = try XCTUnwrap(
      store.finish(
        runId: "run",
        sourceMessageId: 100,
        state: .returned,
        resultSummary: String(repeating: "x", count: 2_500)
      )
    )

    XCTAssertEqual(returned.state, .returned)
    XCTAssertEqual(returned.resultSummary.count, 2_000)
    XCTAssertEqual(returned.updatedAtMillis, 11_000)
    XCTAssertTrue(store.active().isEmpty)
    XCTAssertNil(try store.finish(runId: "run", sourceMessageId: 100, state: .failed))
    XCTAssertTrue(store.serializedSnapshot().contains(#""source_message_id":100"#))

    let restored = InMemoryAgentHandoffStore(serialized: store.serializedSnapshot(), clock: { 12_000 })
    XCTAssertEqual(restored.list().count, 1)
    XCTAssertEqual(restored.list().first?.state, .returned)
  }

  func testAgentRegistrationCarriesProviderProfileThroughAndroidWireNames() throws {
    let embedded = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:qwen",
      provider: "Qwen",
      model: providerCloudModel(
        provider: "Qwen",
        modelId: "qwen-max",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      ),
      apiKey: "stored",
      performance: ProviderPerformanceProfile(attempts: 10, successes: 8, failures: 2, failureRate: 0.2)
    )
    let registration = AgentRegistration(
      agentId: "cloud:qwen",
      installationId: "ios",
      deviceId: "ios",
      providerId: "qwen",
      displayName: "Qwen",
      kind: .model,
      location: .cloud,
      capabilities: [.chat, .reasoning],
      protocol: AgentProtocolRange(preferred: "1.1", minimum: "1.0", maximum: "1.1"),
      connectionKind: .http,
      cost: .medium,
      latency: .normal,
      trust: .cloudConfigured,
      providerProfile: embedded
    )

    let encoded = try JSONEncoder().encode(registration)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let profileObject = try XCTUnwrap(object["provider_profile"] as? [String: Any])
    let decoded = try JSONDecoder().decode(AgentRegistration.self, from: encoded)
    let inferred = ProviderProfileCatalog.fromRegistration(decoded)

    XCTAssertNil(object["providerProfile"])
    XCTAssertEqual(profileObject["provider_id"] as? String, "qwen")
    XCTAssertEqual(decoded.providerProfile?.performance.failureRate ?? -1, 0.2)
    XCTAssertEqual(inferred.contextWindowTokens, embedded.contextWindowTokens)
    XCTAssertEqual(inferred.performance.failureRate, 0.2)
    XCTAssertEqual(inferred.pricing.tier, .medium)
  }
}
