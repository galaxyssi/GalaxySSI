import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testGlobalCapabilityObservationExtractorAuthorizationAndSafetyUseLocalOnlyProjection() {
    let authorizationEvents = GlobalCapabilityObservationExtractor.authorizationMutations(
      before: ["location"],
      after: ["location", "microphone"],
      timestampMillis: 42
    )
    let revokedEvents = GlobalCapabilityObservationExtractor.authorizationMutations(
      before: ["downloads"],
      after: [],
      timestampMillis: 43
    )
    let safety = GlobalCapabilityObservationExtractor.safetyPolicyMutation(
      before: .default,
      after: AgentSafetySettings(
        taskExecutionMode: .planOnly,
        permissionMode: .autoLowRisk,
        highRiskGuard: true,
        memoryCapture: false,
        screenObservationAllowed: false,
        localActionsAllowed: true,
        connectorCallsAllowed: false,
        deviceControlAllowed: false,
        executionPaused: true
      ),
      timestampMillis: 44
    )

    XCTAssertEqual(authorizationEvents.count, 1)
    XCTAssertEqual(authorizationEvents[0].type, .authorizationGranted)
    XCTAssertTrue(authorizationEvents[0].type.isCapabilityLifecycleEvent)
    XCTAssertEqual(authorizationEvents[0].conversationId, "global-capabilities")
    XCTAssertEqual(authorizationEvents[0].conversationTitle, "Local authorization")
    XCTAssertEqual(authorizationEvents[0].metadata["origin"], "confirmation_consent")
    XCTAssertEqual(authorizationEvents[0].metadata["authorization_scope"], "microphone use")
    XCTAssertEqual(authorizationEvents[0].metadata["authorization_state"], "granted")
    XCTAssertEqual(authorizationEvents[0].metadata["context_visibility"], "LOCAL_ONLY")
    XCTAssertEqual(authorizationEvents[0].metadata["projection"], "replace")
    XCTAssertEqual(revokedEvents.first?.type, .authorizationRevoked)
    XCTAssertEqual(revokedEvents.first?.metadata["authorization_state"], "revoked")
    XCTAssertNotNil(safety)
    XCTAssertEqual(safety?.type, .authorizationPolicyChanged)
    XCTAssertEqual(safety?.contentRef, "encrypted://agent-authorization/safety-policy")
    XCTAssertEqual(safety?.metadata["task_execution_mode"], "plan_only")
    XCTAssertEqual(safety?.metadata["permission_mode"], "auto_low_risk")
    XCTAssertEqual(safety?.metadata["screen_observation_allowed"], "false")
    XCTAssertEqual(safety?.metadata["connector_calls_allowed"], "false")
    XCTAssertEqual(safety?.metadata["execution_paused"], "true")
    XCTAssertEqual(safety?.metadata["identity_kind"], "DECISION")
    XCTAssertEqual(safety?.metadata["identity_layer"], "USER")
    XCTAssertNil(GlobalCapabilityObservationExtractor.safetyPolicyMutation(before: .default, after: .default))
  }

  func testGlobalCapabilityObservationExtractorMcpAgentAndHealthAreRedacted() throws {
    let endpoint = "https://secret.example/mcp"
    let connection = AgentMcpConnection(
      id: "github",
      catalogId: "signalasi.mcp.github",
      displayName: "  GitHub   MCP  ",
      endpoint: endpoint,
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired,
      state: .connected,
      toolIds: ["issues.search", "repo.read", "repo.read"]
    )
    let mcp = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.mcpMutations(
        before: [],
        after: [connection],
        timestampMillis: 100
      ).first
    )
    let agent = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.agentMutations(
        before: [],
        after: [
          networkRegistration(
            agentId: "desktop-agent",
            displayName: "Desktop Agent",
            location: .trustedDesktop,
            status: .online,
            capabilities: [.chat, .code],
            activeRuns: 4,
            maxParallelRuns: 4
          )
        ],
        timestampMillis: 101
      ).first
    )
    let resourceId = "target:https://secret.example/runtime"
    let health = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.resourceHealthTransition(
        resourceId: resourceId,
        before: AgentResourceHealth(),
        after: AgentResourceHealth(failures: 3, consecutiveFailures: 3, circuitOpenUntil: 2_000),
        timestampMillis: 102
      )
    )

    XCTAssertEqual(mcp.type, .resourceRegistered)
    XCTAssertEqual(mcp.metadata["resource_kind"], "mcp")
    XCTAssertEqual(mcp.metadata["resource_state"], "available")
    XCTAssertEqual(mcp.metadata["auth_state"], "not_required")
    XCTAssertEqual(mcp.metadata["connection_state"], "connected")
    XCTAssertEqual(mcp.metadata["tool_count"], "2")
    assertGlobalCapabilityEventDoesNotExpose(mcp, secrets: [endpoint, "secret.example"])
    XCTAssertEqual(agent.metadata["resource_kind"], "agent")
    XCTAssertEqual(agent.metadata["resource_state"], "busy")
    XCTAssertEqual(agent.metadata["endpoint_state"], "online")
    XCTAssertEqual(agent.metadata["capability_count"], "2")
    XCTAssertEqual(agent.metadata["at_capacity"], "true")
    XCTAssertEqual(health.type, .resourceStateChanged)
    XCTAssertEqual(health.metadata["origin"], "resource_health")
    XCTAssertEqual(health.metadata["resource_kind"], "health")
    XCTAssertEqual(health.metadata["resource_state"], "unavailable")
    XCTAssertEqual(health.metadata["consecutive_failures"], "3")
    XCTAssertEqual(health.metadata["reliability_percent"], "0")
    assertGlobalCapabilityEventDoesNotExpose(health, secrets: [resourceId, "secret.example/runtime"])
  }

  func testGlobalCapabilityObservationExtractorDeviceResourcesAreRedacted() throws {
    let home = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.homeAssistantMutations(
        before: .default,
        after: HomeAssistantSettings(
          enabled: true,
          baseUrl: "https://home.secret.local",
          accessToken: "ha-token-secret",
          defaultEntityId: "light.private_room"
        ),
        timestampMillis: 200
      ).first
    )
    let device = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.customDeviceMutations(
        before: [],
        after: [
          CustomDeviceConnector(
            id: "door-lock",
            name: "Door Lock",
            transport: .mqtt,
            endpoint: "mqtt://device.secret.local",
            commandTarget: "locks/private-door",
            username: "private-user",
            authToken: "device-token-secret",
            risk: .high,
            enabled: true
          )
        ],
        timestampMillis: 201
      ).first
    )

    XCTAssertEqual(home.metadata["resource_kind"], "home_assistant")
    XCTAssertEqual(home.metadata["resource_state"], "ready")
    XCTAssertEqual(home.metadata["credentials_configured"], "true")
    XCTAssertEqual(home.metadata["default_target_configured"], "true")
    XCTAssertEqual(device.metadata["resource_kind"], "custom_device")
    XCTAssertEqual(device.metadata["resource_state"], "ready")
    XCTAssertEqual(device.metadata["transport"], "mqtt")
    XCTAssertEqual(device.metadata["risk"], "high")
    XCTAssertEqual(device.metadata["configured"], "true")
    assertGlobalCapabilityEventDoesNotExpose(
      home,
      secrets: ["home.secret.local", "ha-token-secret", "light.private_room"]
    )
    assertGlobalCapabilityEventDoesNotExpose(
      device,
      secrets: ["device.secret.local", "locks/private-door", "private-user", "device-token-secret"]
    )
  }

  func testGlobalCapabilityObservationModelsUseAndroidWireNames() throws {
    let reset = GlobalCapabilityObservationExtractor.snapshotReset(timestampMillis: 300)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(reset)) as? [String: Any]
    )
    let health = AgentResourceHealth(
      successes: 3,
      failures: 1,
      consecutiveFailures: 0,
      averageLatencyMs: 250,
      circuitOpenUntil: 0,
      lastUpdatedAt: 123
    )
    let healthObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(health)) as? [String: Any]
    )

    XCTAssertEqual(object["type"] as? String, "CAPABILITY_SNAPSHOT_RESET")
    XCTAssertEqual(object["conversation_id"] as? String, "global-capabilities")
    XCTAssertEqual(object["timestamp_millis"] as? Int, 300)
    XCTAssertNotNil(object["message_id"])
    XCTAssertNotNil(object["content_ref"])
    XCTAssertNotNil(object["conversation_title"])
    XCTAssertNotNil(object["topic_hints"])
    XCTAssertNotNil(object["causal_event_ids"])
    XCTAssertNotNil(object["retracted_event_ids"])
    XCTAssertEqual(object["actor"] as? String, "SYSTEM")
    XCTAssertEqual(object["sensitivity"] as? String, "PERSONAL")
    XCTAssertEqual((object["metadata"] as? [String: Any])?["context_visibility"] as? String, "LOCAL_ONLY")
    XCTAssertEqual(healthObject["consecutive_failures"] as? Int, 0)
    XCTAssertEqual(healthObject["average_latency_ms"] as? Int, 250)
    XCTAssertEqual(healthObject["circuit_open_until"] as? Int, 0)
    XCTAssertEqual(healthObject["last_updated_at"] as? Int, 123)
    XCTAssertEqual(health.reliabilityPercent, 75)
    XCTAssertTrue(GlobalConversationEventType.resourceRegistered.isCapabilityLifecycleEvent)
    XCTAssertFalse(GlobalConversationEventType.messageCreated.isCapabilityLifecycleEvent)
  }

  func testAgentActionRiskHardenerRaisesConnectorAndVisualOcrRisk() {
    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "connector-deploy",
        kind: .callConnector,
        risk: .low,
        target: "Codex",
        description: "Ask Codex to prepare a release",
        parameters: ["prompt": "Deploy and send email release notes"]
      ),
      riskHardenerAction(
        id: "tap-low-confidence",
        kind: .tap,
        risk: .low,
        parameters: [
          "element_origin": AgentElementOrigin.visualOcr.rawValue,
          "element_confidence": "0.42"
        ]
      ),
      riskHardenerAction(
        id: "type-confident-ocr",
        kind: .typeText,
        risk: .low,
        parameters: [
          "field_origin": AgentElementOrigin.visualOcr.rawValue,
          "field_confidence": "0.91"
        ]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(plan: plan)

    XCTAssertEqual(hardened.actions.first { $0.id == "connector-deploy" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "tap-low-confidence" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "type-confident-ocr" }?.risk, .medium)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentActionRiskHardenerUsesCustomDeviceAndHomeAssistantRisk() {
    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "known-custom-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "custom-device:kitchen-light"]
      ),
      riskHardenerAction(
        id: "unknown-custom-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "custom-device:missing-device"]
      ),
      riskHardenerAction(
        id: "home-assistant-lock",
        kind: .controlDevice,
        risk: .low,
        parameters: [
          "connector_id": "home-assistant",
          "prompt": "Unlock the front door"
        ]
      ),
      riskHardenerAction(
        id: "unknown-device",
        kind: .controlDevice,
        risk: .low,
        parameters: ["connector_id": "zigbee-hub"]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(
      plan: plan,
      customDeviceConnectors: [
        CustomDeviceConnector(
          id: "kitchen-light",
          name: "Kitchen Light",
          endpoint: "http://kitchen-light.local",
          risk: .medium
        )
      ],
      homeAssistantSettings: HomeAssistantSettings(
        enabled: true,
        baseUrl: "http://homeassistant.local:8123",
        accessToken: "token",
        defaultEntityId: "lock.front_door"
      )
    )

    XCTAssertEqual(hardened.actions.first { $0.id == "known-custom-device" }?.risk, .medium)
    XCTAssertEqual(hardened.actions.first { $0.id == "unknown-custom-device" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "home-assistant-lock" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "unknown-device" }?.risk, .high)
    XCTAssertEqual(AgentHomeAssistantRiskPolicy.riskForPrompt("Turn on switch.kitchen"), .medium)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentActionRiskHardenerNeverLowersExistingRiskAndModelsUseAndroidSignals() throws {
    let decoded = try JSONDecoder.signalASI.decode(AgentElementOrigin.self, from: Data(#""visual-ocr""#.utf8))
    let encoded = String(decoding: try JSONEncoder.signalASI.encode(AgentElementOrigin.visualOcr), as: UTF8.self)
    XCTAssertEqual(decoded, .visualOcr)
    XCTAssertEqual(encoded, #""VISUAL_OCR""#)
    XCTAssertEqual(AgentElementOrigin.fromWireValue("visual ocr"), .visualOcr)
    XCTAssertEqual(AgentElementOrigin.fromWireValue(nil), .unknown)

    let plan = riskHardenerPlan([
      riskHardenerAction(
        id: "existing-high",
        kind: .tap,
        risk: .high,
        parameters: [
          "element_origin": AgentElementOrigin.visualOcr.rawValue,
          "element_confidence": "0.99"
        ]
      ),
      riskHardenerAction(
        id: "accessibility-long-press",
        kind: .longPress,
        risk: .medium,
        parameters: [
          "element_origin": AgentElementOrigin.accessibility.rawValue,
          "element_confidence": "0.20"
        ]
      ),
      riskHardenerAction(
        id: "connector-transfer",
        kind: .callConnector,
        risk: .low,
        target: "Payments",
        description: "Ask connector",
        parameters: ["prompt": "\u{8bf7}\u{8f6c}\u{8d26}\u{7ed9}\u{4f9b}\u{5e94}\u{5546}"]
      )
    ])

    let hardened = AgentActionRiskHardener.enforce(plan: plan)

    XCTAssertEqual(hardened.actions.first { $0.id == "existing-high" }?.risk, .high)
    XCTAssertEqual(hardened.actions.first { $0.id == "accessibility-long-press" }?.risk, .medium)
    XCTAssertEqual(hardened.actions.first { $0.id == "connector-transfer" }?.risk, .high)
    XCTAssertTrue(hardened.validation.valid)
  }

  func testAgentVisualGroundingAnalyzesRolesAndAndroidWireNames() throws {
    let scene = AgentVisualGrounding.analyze(
      rawElements: [
        AgentVisualElement(text: "  Continue\nnow ", bounds: "20,1500,320,1580", confidence: 1.4),
        AgentVisualElement(text: "Continue now", bounds: "20,1500,320,1580", confidence: 0.9),
        AgentVisualElement(text: "Account Settings", bounds: "20,20,600,110", confidence: 0.8),
        AgentVisualElement(text: "Email address", bounds: "30,620,860,690", confidence: 0.7),
        AgentVisualElement(text: "Home", bounds: "20,1650,200,1740", confidence: 0.6),
        AgentVisualElement(text: " ", bounds: "10,10,20,20"),
        AgentVisualElement(text: "Broken", bounds: "10,10,8,20")
      ],
      width: 1_080,
      height: 1_800,
      timestampMillis: 12_345
    )
    let encoded = try JSONEncoder.signalASI.encode(scene)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let firstElement = try XCTUnwrap((object["elements"] as? [[String: Any]])?.first)

    XCTAssertTrue(scene.available)
    XCTAssertEqual(scene.width, 1_080)
    XCTAssertEqual(scene.height, 1_800)
    XCTAssertEqual(scene.modelProfile, "mlkit-ocr-layout-v1")
    XCTAssertEqual(scene.timestampMillis, 12_345)
    XCTAssertEqual(scene.elements.count, 4)
    XCTAssertEqual(scene.elements.first?.text, "Continue now")
    XCTAssertEqual(scene.elements.first?.confidence, 1)
    XCTAssertEqual(scene.elements.first?.role, .button)
    XCTAssertEqual(scene.elements.first { $0.text == "Account Settings" }?.role, .title)
    XCTAssertEqual(scene.elements.first { $0.text == "Email address" }?.role, .input)
    XCTAssertEqual(scene.elements.first { $0.text == "Home" }?.role, .navigation)
    XCTAssertEqual(scene.actionCandidateCount, 2)
    XCTAssertEqual(scene.inputCandidateCount, 1)
    XCTAssertEqual(object["model_profile"] as? String, "mlkit-ocr-layout-v1")
    XCTAssertEqual(object["action_candidate_count"] as? Int, 2)
    XCTAssertEqual(object["input_candidate_count"] as? Int, 1)
    XCTAssertEqual(firstElement["input_candidate"] as? Bool, false)
    XCTAssertEqual(AgentVisualRole.fromWireValue("list item"), .listItem)
    XCTAssertEqual(AgentElementOrigin.fromWireValue("fused"), .fused)
  }

  func testAgentVisualGroundingFusesAccessibilityAndVisualElements() {
    let accessibility = [
      agentScreenElement(
        label: "",
        viewId: "android:id/button1",
        className: "Button",
        bounds: "100,100,300,180",
        confidence: 0.6,
        actionable: true
      )
    ]
    let scene = AgentVisualScene(
      width: 1_080,
      height: 1_800,
      elements: [
        AgentVisualElement(
          text: "Continue",
          bounds: "104,104,296,176",
          confidence: 0.8,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Save",
          bounds: "400,100,620,180",
          confidence: 0.7,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Maybe",
          bounds: "700,100,820,180",
          confidence: 0.3,
          role: .button,
          actionable: true
        ),
        AgentVisualElement(
          text: "Email",
          bounds: "80,500,900,580",
          confidence: 0.9,
          role: .input,
          actionable: false,
          inputCandidate: true
        )
      ]
    )

    let fusedActions = AgentVisualGrounding.fuseClickableElements(accessibilityElements: accessibility, scene: scene)
    let fusedFields = AgentVisualGrounding.fuseInputFields(accessibilityElements: [], scene: scene)

    XCTAssertEqual(fusedActions.count, 2)
    XCTAssertEqual(fusedActions[0].label, "Continue")
    XCTAssertEqual(fusedActions[0].origin, .fused)
    XCTAssertEqual(fusedActions[0].confidence, 0.8)
    XCTAssertEqual(fusedActions[0].visualRole, .button)
    XCTAssertEqual(fusedActions[1].label, "Save")
    XCTAssertEqual(fusedActions[1].viewId, "visual:button:0")
    XCTAssertEqual(fusedActions[1].className, "AgentVisualButton")
    XCTAssertEqual(fusedActions[1].origin, .visualOcr)
    XCTAssertEqual(fusedFields.count, 1)
    XCTAssertEqual(fusedFields.first?.label, "Email")
    XCTAssertEqual(fusedFields.first?.viewId, "visual:input:0")
    XCTAssertEqual(fusedFields.first?.origin, .visualOcr)
  }

  func testAgentScreenElementMatcherResolvesAndroidStyleQueries() {
    let accessibility = agentScreenElement(
      label: "Continue",
      viewId: "primary_action",
      className: "Button",
      bounds: "10,10,210,80",
      origin: .accessibility,
      confidence: 0.8,
      visualRole: .button
    )
    let visual = agentScreenElement(
      label: "Continue",
      viewId: "visual:button:0",
      className: "AgentVisualButton",
      bounds: "10,10,210,80",
      origin: .visualOcr,
      confidence: 0.8,
      visualRole: .button
    )
    let input = agentScreenElement(
      label: "Email address",
      viewId: "field_email",
      className: "EditText",
      bounds: "10,200,600,280",
      confidence: 0.7,
      visualRole: .input
    )
    let elements = [visual, input, accessibility]

    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "Continue", elements: elements), accessibility)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "primary action", elements: elements), accessibility)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "email", elements: elements), input)
    XCTAssertEqual(AgentScreenElementMatcher.resolve(query: "input", elements: elements), input)
    XCTAssertNil(AgentScreenElementMatcher.resolve(query: "   ", elements: elements))
  }

  func testAgentRemoteReputationDecodesDesktopReceiptAndPreservesCanonicalFieldOrder() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))

    XCTAssertEqual(receipt.agentId, remoteReputationContactId)
    XCTAssertEqual(receipt.capabilities, Set([AgentCapability.chat, AgentCapability.code]))
    XCTAssertEqual(receipt.provenance, .hostObserved)

    let canonical = String(decoding: receipt.canonicalPayload(), as: UTF8.self)
    let taskHash = agentReputationSha256(Data(remoteReputationTaskId.utf8))
    XCTAssertTrue(canonical.hasPrefix("{\"actual_cost_units\":0,\"agent_id\":\"\(remoteReputationContactId)\""))
    XCTAssertTrue(
      canonical.hasSuffix(
        "\"started_at_millis\":1000,\"task_id_hash\":\"\(taskHash)\",\"version\":1}"
      )
    )
    XCTAssertEqual(
      agentReputationSha256(Data(canonical.utf8)),
      "fe6995403d63a8ca06ab70ae20d0e3b62749d3ab9eac8b2a2e3e62e775ecf4e7"
    )
  }

  func testAgentRemoteReputationBindsReceiptToPairedDesktopAgentAndTask() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let envelope = remoteReputationEnvelope()

    XCTAssertNil(AgentRemoteReputation.bindingFailure(envelope, receipt: receipt))
    XCTAssertEqual(AgentRemoteReputation.boundReceipt(from: envelope)?.receiptId, receipt.receiptId)

    var changedTask = envelope
    changedTask["task_id"] = .string("other-task")
    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(changedTask, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
  }

  func testAgentRemoteReputationRejectsCrossDesktopOrCrossAgentClaims() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let crossDesktop = remoteReputationEnvelope(
      desktopId: "desktop_fedcba9876543210",
      contactId: "desktop_fedcba9876543210:codex"
    )
    let crossAgent = remoteReputationEnvelope(contactId: "\(remoteReputationDesktopId):browser")

    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(crossDesktop, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
    XCTAssertEqual(
      AgentRemoteReputation.bindingFailure(crossAgent, receipt: receipt),
      AgentRemoteReputation.invalidBindingReason
    )
  }

  func testAgentRemoteReputationRejectsMalformedReceiptsAndUsesAndroidWireNames() throws {
    var invalidReceipt = remoteReputationReceiptObject()
    invalidReceipt["outcome"] = .string("DONE")
    XCTAssertNil(AgentReputationWireCodec.decodeReceipt(invalidReceipt))

    var invalidEnvelope = remoteReputationEnvelope()
    invalidEnvelope["execution_receipt"] = .object(invalidReceipt)
    XCTAssertEqual(
      AgentRemoteReputation.receiptFailureReason(from: invalidEnvelope),
      AgentRemoteReputation.invalidReceiptReason
    )

    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any]
    )
    XCTAssertEqual(object["receipt_id"] as? String, "receipt-1")
    XCTAssertEqual(object["task_id_hash"] as? String, agentReputationSha256(Data(remoteReputationTaskId.utf8)))
    XCTAssertEqual(object["executor_failure_domain"] as? String, remoteReputationDesktopId)
    XCTAssertEqual(object["started_at_millis"] as? Int, 1_000)
    XCTAssertEqual(object["completed_at_millis"] as? Int, 2_000)
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "a", count: 64))
    XCTAssertNil(object["taskIdHash"])
    XCTAssertNil(object["startedAtMillis"])
  }

  func testAgentReputationAttestationCanonicalPayloadBindsReceiptHash() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )

    XCTAssertEqual(attestation.verdict, .passed)
    XCTAssertEqual(attestation.receiptId, receipt.receiptId)
    XCTAssertEqual(attestation.receiptPayloadHash, agentReputationSha256(receipt.canonicalPayload()))
    XCTAssertNil(attestation.validationFailure(for: receipt, nowMillis: 10_000))

    let canonical = String(decoding: attestation.canonicalPayload(), as: UTF8.self)
    XCTAssertTrue(canonical.hasPrefix("{\"attestation_id\":\"\(attestation.attestationId)\""))
    XCTAssertTrue(canonical.hasSuffix("\"verifier_installation_id\":\"verifier-host\",\"version\":1}"))
    XCTAssertEqual(
      agentReputationSha256(attestation.canonicalPayload()),
      "ad01c99d132f3e0458d43c9deaec1365445a14b429bd486ec57fe68ea6f3f18c"
    )
  }

  func testAgentReputationAttestationRejectsDependentOrTamperedClaims() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )

    var tamperedHash = attestation
    tamperedHash.receiptPayloadHash = String(repeating: "f", count: 64)
    XCTAssertEqual(
      tamperedHash.validationFailure(for: receipt, nowMillis: 10_000),
      AgentRemoteReputation.invalidBindingReason
    )

    var sameAgent = attestation
    sameAgent.verifierAgentId = receipt.agentId
    XCTAssertEqual(
      sameAgent.validationFailure(for: receipt, nowMillis: 10_000),
      "independence_boundary_invalid"
    )

    var signerMismatch = attestation
    signerMismatch.signerId = "other-verifier"
    signerMismatch.signatureKeyId = String(repeating: "e", count: 64)
    XCTAssertEqual(
      signerMismatch.validationFailure(for: receipt, nowMillis: 10_000),
      "signer_subject_mismatch"
    )

    var tooEarly = attestation
    tooEarly.createdAtMillis = receipt.completedAtMillis - 1
    XCTAssertEqual(
      tooEarly.validationFailure(for: receipt, nowMillis: 10_000),
      "time_boundary_invalid"
    )
  }

  func testAgentReputationAttestationModelsUseAndroidWireNames() throws {
    let receipt = try XCTUnwrap(AgentReputationWireCodec.decodeReceipt(remoteReputationReceiptObject()))
    let attestation = try XCTUnwrap(
      AgentReputationWireCodec.decodeAttestation(remoteReputationAttestationObject(for: receipt))
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(attestation)) as? [String: Any]
    )

    XCTAssertEqual(object["attestation_id"] as? String, attestation.attestationId)
    XCTAssertEqual(object["receipt_payload_hash"] as? String, agentReputationSha256(receipt.canonicalPayload()))
    XCTAssertEqual(object["verifier_agent_id"] as? String, "independent-verifier")
    XCTAssertEqual(object["verifier_installation_id"] as? String, "verifier-host")
    XCTAssertEqual(object["verifier_failure_domain"] as? String, "phone-b")
    XCTAssertEqual(object["created_at_millis"] as? Int, 2_100)
    XCTAssertEqual(object["signature_key_id"] as? String, String(repeating: "d", count: 64))
    XCTAssertNil(object["receiptPayloadHash"])
    XCTAssertNil(object["verifierAgentId"])

    var invalid = remoteReputationAttestationObject(for: receipt)
    invalid["verdict"] = .string("UNKNOWN")
    XCTAssertNil(AgentReputationWireCodec.decodeAttestation(invalid))
  }

  func testAgentReputationSnapshotNeutralAndIndependentPassRaiseConfidence() {
    let receipt = reputationReceipt("run-1", outcome: .succeeded)
    let neutral = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [],
      attestations: [],
      nowMillis: reputationNow
    )
    let before = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let after = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [reputationAttestation(for: receipt, verdict: .passed)],
      nowMillis: reputationNow + 1_000
    )

    XCTAssertEqual(neutral, AgentReputationSnapshot.neutral(receipt.agentId))
    XCTAssertTrue(after.confidence > before.confidence)
    XCTAssertTrue(after.score >= before.score)
    XCTAssertEqual(after.independentlyVerifiedRuns, 1)
    XCTAssertEqual(after.independentFailureDomains, 1)
    XCTAssertEqual(after.lastEvidenceAtMillis, receipt.completedAtMillis + 100)
  }

  func testAgentReputationSnapshotFailureTimeoutAndBudgetDimensions() {
    let succeeded = reputationReceipt("run-1", outcome: .succeeded)
    let beforeFailure = AgentReputationScoring.snapshot(
      agentId: succeeded.agentId,
      receipts: [succeeded],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let afterFailure = AgentReputationScoring.snapshot(
      agentId: succeeded.agentId,
      receipts: [succeeded],
      attestations: [reputationAttestation(for: succeeded, verdict: .failed)],
      nowMillis: reputationNow + 1_000
    )
    let timeout = reputationReceipt(
      "run-timeout",
      outcome: .timedOut,
      deadlineAtMillis: reputationNow - 500,
      estimatedCostUnits: 2,
      actualCostUnits: 8
    )
    let timeoutProfile = AgentReputationScoring.snapshot(
      agentId: timeout.agentId,
      receipts: [timeout],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )

    XCTAssertTrue(afterFailure.score < beforeFailure.score)
    XCTAssertEqual(afterFailure.disputedRuns, 1)
    XCTAssertEqual(afterFailure.independentlyVerifiedRuns, 0)
    XCTAssertEqual(timeoutProfile.timeoutRuns, 1)
    XCTAssertTrue(timeoutProfile.timeliness < 70)
    XCTAssertTrue(timeoutProfile.costEfficiency < 70)
    XCTAssertTrue(timeoutProfile.reliability < 70)
  }

  func testAgentReputationSnapshotFiltersCapabilitiesAndUsesLatestRunVersion() {
    let codeReceipts = (0..<4).map {
      reputationReceipt("code-\($0)", outcome: .succeeded, capabilities: [.code])
    }
    let researchFailure = reputationReceipt(
      "research-failure",
      outcome: .failed,
      capabilities: [.research]
    )
    let code = AgentReputationScoring.snapshot(
      agentId: "codex-agent",
      capabilities: [.code],
      receipts: codeReceipts + [researchFailure],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let research = AgentReputationScoring.snapshot(
      agentId: "codex-agent",
      capabilities: [.research],
      receipts: codeReceipts + [researchFailure],
      attestations: [],
      nowMillis: reputationNow + 1_000
    )
    let failed = reputationReceipt("run-1", outcome: .failed)
    let corrected = reputationReceipt("run-1", outcome: .succeeded, completedAtMillis: reputationNow + 100)
    let correctedProfile = AgentReputationScoring.snapshot(
      agentId: failed.agentId,
      receipts: [failed, corrected],
      attestations: [],
      nowMillis: reputationNow + 100
    )

    XCTAssertTrue(code.score > research.score)
    XCTAssertEqual(code.evaluatedRuns, 4)
    XCTAssertEqual(research.evaluatedRuns, 1)
    XCTAssertEqual(correctedProfile.evaluatedRuns, 1)
    XCTAssertTrue(correctedProfile.score > 70)
  }

  func testAgentReputationSnapshotModelsUseAndroidWireNames() throws {
    let receipt = reputationReceipt("run-1", outcome: .succeeded)
    let snapshot = AgentReputationScoring.snapshot(
      agentId: receipt.agentId,
      receipts: [receipt],
      attestations: [reputationAttestation(for: receipt, verdict: .passed)],
      nowMillis: reputationNow + 1_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
    )

    XCTAssertEqual(object["agent_id"] as? String, "codex-agent")
    XCTAssertEqual(object["cost_efficiency"] as? Int, snapshot.costEfficiency)
    XCTAssertEqual(object["evaluated_runs"] as? Int, 1)
    XCTAssertEqual(object["independently_verified_runs"] as? Int, 1)
    XCTAssertEqual(object["independent_failure_domains"] as? Int, 1)
    XCTAssertEqual(object["last_evidence_at_millis"] as? Int, Int(reputationNow + 100))
    XCTAssertEqual(object["routing_adjustment"] as? Int, snapshot.routingAdjustment)
    XCTAssertNil(object["costEfficiency"])
    XCTAssertNil(object["evaluatedRuns"])
  }

  func testAgentNetworkSearchRanksCapableNamedAgentsWithoutCollapsingIdentity() {
    let index = AgentNetworkIndex([
      networkRegistration(
        agentId: "codex.office",
        displayName: "Codex - Office PC",
        capabilities: [.chat, .code, .taskExecution],
        latency: .fast
      ),
      networkRegistration(
        agentId: "claude-code.home",
        displayName: "Claude Code - Home PC",
        capabilities: [.chat, .code, .reasoning],
        latency: .normal
      ),
      networkRegistration(
        agentId: "hermes.research",
        displayName: "Hermes - Research PC",
        capabilities: [.chat, .research, .liveData]
      )
    ])

    let page = index.search(
      AgentNetworkSearchQuery(text: "Find a fast Agent to debug a Python project"),
      nowMillis: 1_000_000
    )

    XCTAssertEqual(page.totalMatches, 2)
    XCTAssertEqual(page.hits.first?.registration.agentId, "codex.office")
    XCTAssertEqual(page.hits.first?.registration.displayName, "Codex - Office PC")
    XCTAssertTrue(page.hits.first?.matchedCapabilities.contains(.code) == true)
    XCTAssertFalse(page.hits.contains { $0.registration.agentId == "hermes.research" })
  }

  func testAgentNetworkSearchEnforcesTrustCapacityCostAndStaleHeartbeat() {
    let now: Int64 = 1_000_000
    let staleHeartbeat = now - AgentNetworkIndex.heartbeatTTLMillis - 1
    let index = AgentNetworkIndex([
      networkRegistration(
        agentId: "phone.local",
        displayName: "Phone Agent",
        location: .phone,
        trust: .phoneSystem,
        cost: .free,
        lastHeartbeatMillis: staleHeartbeat
      ),
      networkRegistration(
        agentId: "desktop.busy",
        displayName: "Codex - Busy PC",
        activeRuns: 2,
        maxParallelRuns: 2,
        cost: .low
      ),
      networkRegistration(
        agentId: "cloud.unknown",
        displayName: "Unknown Cloud Agent",
        location: .cloud,
        trust: .unknown,
        cost: .high
      ),
      networkRegistration(
        agentId: "desktop.stale",
        displayName: "Codex - Stale PC",
        lastHeartbeatMillis: staleHeartbeat
      )
    ])

    let filtered = index.search(
      AgentNetworkSearchQuery(trustedOnly: true, maximumCost: .low),
      nowMillis: now
    )
    let all = index.search(AgentNetworkSearchQuery(routableOnly: false), nowMillis: now)

    XCTAssertEqual(filtered.hits.map { $0.registration.agentId }, ["phone.local"])
    XCTAssertEqual(
      all.hits.first { $0.registration.agentId == "desktop.stale" }?.registration.status,
      .unreachable
    )
  }

  func testAgentNetworkSearchCursorInvalidatesAfterDirectoryOrReputationMutation() {
    let registrations = (0..<75).map {
      networkRegistration(
        agentId: "agent-\($0)",
        displayName: "Agent \(String(format: "%03d", $0))"
      )
    }
    let index = AgentNetworkIndex(registrations)
    let query = AgentNetworkSearchQuery(pageSize: 25)
    let first = index.search(query, nowMillis: 1_000_000)
    let second = index.search(AgentNetworkSearchQuery(pageSize: 25, cursor: first.nextCursor), nowMillis: 1_000_000)

    XCTAssertEqual(first.hits.count, 25)
    XCTAssertEqual(second.hits.count, 25)
    XCTAssertTrue(Set(first.hits.map { $0.registration.agentId }).isDisjoint(with: second.hits.map { $0.registration.agentId }))
    XCTAssertFalse(second.cursorReset)

    index.upsert(networkRegistration(agentId: "agent-new", displayName: "Agent New"))
    let resetAfterDirectoryChange = index.search(
      AgentNetworkSearchQuery(pageSize: 25, cursor: second.nextCursor),
      nowMillis: 1_000_000
    )
    XCTAssertTrue(resetAfterDirectoryChange.cursorReset)

    let reputation = AgentReputationSnapshot(
      agentId: "agent-new",
      score: 92,
      confidence: 60,
      reliability: 92,
      quality: 92,
      timeliness: 92,
      costEfficiency: 92,
      evaluatedRuns: 5,
      independentlyVerifiedRuns: 5,
      disputedRuns: 0,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: 65
    )
    let pageBeforeReputationChange = index.search(query, nowMillis: 1_000_000)
    index.replaceReputations(["agent-new": reputation], revision: 7)
    let resetAfterReputationChange = index.search(
      AgentNetworkSearchQuery(pageSize: 25, cursor: pageBeforeReputationChange.nextCursor),
      nowMillis: 1_000_000
    )
    XCTAssertTrue(resetAfterReputationChange.cursorReset)
    XCTAssertTrue(resetAfterReputationChange.revision > pageBeforeReputationChange.revision)
  }

  func testAgentNetworkSearchUsesReputationButDoesNotBlockColdStart() {
    let proven = AgentReputationSnapshot(
      agentId: "z-proven",
      score: 94,
      confidence: 63,
      reliability: 94,
      quality: 94,
      timeliness: 94,
      costEfficiency: 94,
      evaluatedRuns: 5,
      independentlyVerifiedRuns: 5,
      disputedRuns: 0,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: 73
    )
    let poor = AgentReputationSnapshot(
      agentId: "a-poor",
      score: 31,
      confidence: 80,
      reliability: 31,
      quality: 31,
      timeliness: 31,
      costEfficiency: 31,
      evaluatedRuns: 8,
      independentlyVerifiedRuns: 0,
      disputedRuns: 8,
      timeoutRuns: 0,
      independentFailureDomains: 1,
      lastEvidenceAtMillis: 1_000_000,
      routingAdjustment: -109
    )
    let index = AgentNetworkIndex(
      [
        networkRegistration(agentId: "a-new", displayName: "New Agent", capabilities: [.chat, .reasoning]),
        networkRegistration(agentId: "z-proven", displayName: "Proven Agent", capabilities: [.chat, .reasoning]),
        networkRegistration(agentId: "a-poor", displayName: "Poor Agent", capabilities: [.chat, .reasoning])
      ],
      reputations: ["z-proven": proven, "a-poor": poor],
      reputationRevision: 3
    )

    let ranked = index.search(
      AgentNetworkSearchQuery(preferredCapabilities: [.reasoning], pageSize: 10),
      nowMillis: 1_000_000
    )
    let thresholded = index.search(
      AgentNetworkSearchQuery(
        minimumReputationScore: 80,
        minimumReputationConfidence: 40,
        pageSize: 10
      ),
      nowMillis: 1_000_000
    )

    XCTAssertEqual(ranked.hits.first?.registration.agentId, "z-proven")
    XCTAssertTrue(ranked.hits.first?.reasons.contains("reputation:94") == true)
    XCTAssertTrue(thresholded.hits.contains { $0.registration.agentId == "a-new" })
    XCTAssertFalse(thresholded.hits.contains { $0.registration.agentId == "a-poor" })
  }

  func testAgentNetworkSearchModelsUseAndroidWireNames() throws {
    let registration = networkRegistration(agentId: "codex.office", displayName: "Codex Office")
    let index = AgentNetworkIndex([registration])
    let page = index.search(
      AgentNetworkSearchQuery(
        text: "codex",
        requiredCapabilities: [.chat],
        preferredCapabilities: [.code],
        trustedOnly: true,
        maximumCost: .low,
        pageSize: 10
      ),
      nowMillis: 1_000_000
    )
    let pageObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any]
    )
    let registrationObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: Any]
    )

    XCTAssertEqual(registrationObject["agent_id"] as? String, "codex.office")
    XCTAssertEqual(registrationObject["installation_id"] as? String, "installation-codex.office")
    XCTAssertEqual(registrationObject["provider_id"] as? String, "desktop-provider")
    XCTAssertEqual(registrationObject["display_name"] as? String, "Codex Office")
    XCTAssertEqual(registrationObject["connection_kind"] as? String, "SIGNALASI_LINK")
    XCTAssertEqual(registrationObject["last_heartbeat_millis"] as? Int, 0)
    XCTAssertNil(registrationObject["agentId"])
    XCTAssertEqual(pageObject["query_id"] as? String, page.queryId)
    XCTAssertEqual(pageObject["total_matches"] as? Int, 1)
    XCTAssertEqual(pageObject["next_cursor"] as? String, "")
    XCTAssertEqual(pageObject["cursor_reset"] as? Bool, false)
    XCTAssertEqual(pageObject["generated_at_millis"] as? Int, 1_000_000)
    XCTAssertNil(pageObject["totalMatches"])
  }

  func testProviderProfileCatalogContainsAndroidModelProviders() {
    XCTAssertEqual(
      Set(ProviderProfileCatalog.modelProviders.map(\.providerId)),
      Set(["openai", "anthropic", "gemini", "deepseek", "qwen", "ollama", "lm-studio", "openrouter"])
    )
    XCTAssertTrue(ProviderProfileCatalog.modelProviders.allSatisfy { $0.contextWindowTokens > 0 })
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Claude"), "anthropic")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Google Gemini"), "gemini")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("dashscope"), "qwen")
    XCTAssertEqual(ProviderProfileCatalog.normalizeProviderId("Open Router"), "openrouter")
  }

  func testProviderProfileCatalogBuildsCloudAndLocalModelProfiles() {
    let deepseek = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:deepseek",
      provider: "DeepSeek",
      displayName: "DeepSeek V4",
      model: providerCloudModel(
        provider: "DeepSeek",
        modelId: "deepseek-v4-pro",
        endpoint: "https://api.deepseek.com/chat/completions"
      ),
      apiKey: "stored-key",
      status: .available,
      performance: ProviderPerformanceProfile(
        attempts: 10,
        successes: 8,
        failures: 2,
        failureRate: 0.2,
        ewmaLatencyMs: 1_100
      )
    )

    XCTAssertEqual(deepseek.profileId, "model:deepseek")
    XCTAssertEqual(deepseek.kind, .cloudModel)
    XCTAssertEqual(deepseek.location, .cloud)
    XCTAssertEqual(deepseek.modelId, "deepseek-v4-pro")
    XCTAssertEqual(deepseek.contextWindowTokens, 128_000)
    XCTAssertEqual(deepseek.maxParallelRuns, 4)
    XCTAssertEqual(deepseek.quality, .frontier)
    XCTAssertEqual(deepseek.pricing.tier, .low)
    XCTAssertTrue(deepseek.credentialConfigured)
    XCTAssertTrue(deepseek.supportsTools)
    XCTAssertTrue(deepseek.supportsStreaming)
    XCTAssertTrue(deepseek.supportsBackground)
    XCTAssertTrue(deepseek.capabilities.isSuperset(of: Set([.chat, .reasoning, .toolUse, .liveData])))
    XCTAssertEqual(deepseek.performance.failures, 2)

    let ollama = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:ollama",
      provider: "Ollama",
      model: providerCloudModel(
        provider: "Ollama",
        modelId: "llama3",
        endpoint: "http://localhost:11434/v1/chat/completions"
      )
    )

    XCTAssertEqual(ollama.displayName, "Ollama")
    XCTAssertEqual(ollama.kind, .localModel)
    XCTAssertEqual(ollama.location, .privateNetwork)
    XCTAssertEqual(ollama.trust, .privateConfigured)
    XCTAssertEqual(ollama.maxParallelRuns, 2)
    XCTAssertEqual(ollama.pricing.tier, .free)
    XCTAssertTrue(ollama.credentialConfigured)
    XCTAssertTrue(ollama.capabilities.contains(.localInference))
    XCTAssertFalse(ollama.supportsTools)
  }

  func testProviderProfileModelsRoundTripAndroidWireNamesAndNoCredentials() throws {
    var profile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:openai",
      provider: "OpenAI",
      model: providerCloudModel(
        provider: "OpenAI",
        modelId: "gpt-5.4-mini",
        endpoint: "https://api.openai.com/v1/chat/completions"
      ),
      apiKey: "private-secret",
      performance: ProviderPerformanceProfile(attempts: 3, successes: 2, failures: 1, ewmaLatencyMs: 940)
    )
    profile.pricing = ProviderPricingProfile(
      tier: profile.pricing.tier,
      inputMicrosPerMillionTokens: 200_000,
      outputMicrosPerMillionTokens: 600_000,
      source: "catalog_estimate"
    )
    let encoded = try JSONEncoder().encode(profile)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let pricing = try XCTUnwrap(object["pricing"] as? [String: Any])
    let performance = try XCTUnwrap(object["performance"] as? [String: Any])
    let capabilities = try XCTUnwrap(object["capabilities"] as? [String])
    let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    let restored = try JSONDecoder().decode(ProviderProfile.self, from: encoded)

    XCTAssertEqual(object["schema_version"] as? Int, ProviderProfile.schemaVersion)
    XCTAssertEqual(object["profile_id"] as? String, "model:openai")
    XCTAssertEqual(object["resource_id"] as? String, "cloud:openai")
    XCTAssertEqual(object["kind"] as? String, "cloud_model")
    XCTAssertEqual(object["location"] as? String, "cloud")
    XCTAssertEqual(object["status"] as? String, "available")
    XCTAssertEqual(object["quality_tier"] as? String, "frontier")
    XCTAssertEqual(object["protocol_family"] as? String, "openai")
    XCTAssertEqual(object["credential_configured"] as? Bool, true)
    XCTAssertNil(object["profileId"])
    XCTAssertEqual(pricing["tier"] as? String, "medium")
    XCTAssertEqual(pricing["input_micros_per_million_tokens"] as? Int, 200_000)
    XCTAssertEqual(pricing["output_micros_per_million_tokens"] as? Int, 600_000)
    XCTAssertNotNil(performance["ewma_latency_ms"])
    XCTAssertTrue(capabilities.contains("live_data"))
    XCTAssertFalse(json.contains("private-secret"))
    XCTAssertEqual(restored, profile)

    let minimal = try JSONDecoder().decode(
      ProviderProfile.self,
      from: Data(
        #"{"schema_version":1,"profile_id":"model:future","resource_id":"cloud:future","provider_id":"future","product_id":"future","display_name":"Future","kind":"future","location":"private_network","status":"ready","pricing":{"tier":"medium"},"performance":{"attempts":2}}"#.utf8
      )
    )

    XCTAssertEqual(minimal.kind, .agent)
    XCTAssertEqual(minimal.status, .available)
    XCTAssertEqual(minimal.location, .privateNetwork)
    XCTAssertEqual(minimal.pricing.tier, .medium)
    XCTAssertEqual(minimal.performance.attempts, 2)
    XCTAssertEqual(minimal.performance.failures, 0)
  }

  func testProviderProfileCatalogBuildsAgentAndTargetProfiles() throws {
    let registration = networkRegistration(
      agentId: "desktop_a:codex",
      displayName: "Codex Workstation",
      providerId: "desktop_a",
      capabilities: [.chat, .code, .taskExecution, .toolUse],
      cost: .low,
      latency: .fast,
      failureDomain: "desktop_a",
      adapterType: "codex-app-server"
    )
    let profile = ProviderProfileCatalog.fromRegistration(registration)

    XCTAssertEqual(profile.profileId, "agent:desktop_a:codex")
    XCTAssertEqual(profile.productId, "codex")
    XCTAssertEqual(profile.providerId, "desktop_a")
    XCTAssertEqual(profile.kind, .agent)
    XCTAssertEqual(profile.location, .trustedDesktop)
    XCTAssertEqual(profile.status, .available)
    XCTAssertEqual(profile.adapterType, "codex-app-server")
    XCTAssertEqual(profile.pricing.tier, .low)
    XCTAssertTrue(profile.supportsTools)
    XCTAssertTrue(profile.supportsBackground)

    let embedded = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:qwen",
      provider: "Qwen",
      model: providerCloudModel(
        provider: "Qwen",
        modelId: "qwen3.7-max",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      ),
      apiKey: "stored-key"
    )
    let target = AgentCallableTarget(
      id: "cloud:qwen",
      title: "Qwen",
      kind: .model,
      status: .available,
      capabilities: Array(embedded.capabilities),
      providerProfile: embedded
    )
    let inferred = ProviderProfileCatalog.fromTarget(
      AgentCallableTarget(
        id: "codex",
        title: "Codex",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .taskExecution],
        failureDomain: "desktop_a",
        adapterType: "codex-app-server"
      )
    )
    let targetObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any]
    )

    XCTAssertEqual(ProviderProfileCatalog.fromTarget(target), embedded)
    XCTAssertNotNil(targetObject["provider_profile"])
    XCTAssertNil(targetObject["providerProfile"])
    XCTAssertEqual(inferred.kind, .agent)
    XCTAssertEqual(inferred.location, .trustedDesktop)
    XCTAssertEqual(inferred.trust, .verifiedPaired)
    XCTAssertTrue(inferred.supportsBackground)
  }

  func testAgentConnectorRouteSelectorSelectsCodexWhenPhoneToolIsTopScoredResource() throws {
    let codex = routeTarget("codex", kind: .agent)
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(phoneWeb, score: 900),
      fallbacks: [resourceCandidate(codexResource, score: 800)],
      catalog: [phoneWeb, codexResource]
    )

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [codex], decision: decision))

    XCTAssertEqual(selected.target.id, codex.id)
    XCTAssertEqual(selected.decision?.primary?.resource.targetId, codex.id)
    XCTAssertEqual(selected.decision?.orderedTargetIds, [codex.id])
  }

  func testAgentConnectorRouteSelectorUsesOnlyConnectorFallbacks() throws {
    let codex = routeTarget("codex", kind: .agent)
    let cloud = routeTarget("cloud-model:deepseek", kind: .model)
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let cloudResource = routingResource(
      targetId: cloud.id,
      type: .cloudModel,
      location: .cloud
    )
    let decision = routingDecision(
      primary: resourceCandidate(codexResource, score: 900),
      fallbacks: [resourceCandidate(phoneWeb, score: 850), resourceCandidate(cloudResource, score: 700)],
      catalog: [codexResource, phoneWeb, cloudResource]
    )

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [codex, cloud], decision: decision))

    XCTAssertEqual(selected.target.id, codex.id)
    XCTAssertEqual(selected.decision?.fallbacks.map(\.resource.targetId), [cloud.id])
  }

  func testAgentConnectorRouteSelectorHonorsExplicitConnectorPreference() throws {
    let codex = routeTarget("codex", kind: .agent)
    let cloud = routeTarget("cloud-model:deepseek", kind: .model)
    let phoneWeb = routingResource(
      targetId: "web.search",
      type: .localTool,
      location: .phone
    )
    let cloudResource = routingResource(
      targetId: cloud.id,
      type: .cloudModel,
      location: .cloud
    )
    let codexResource = routingResource(
      targetId: codex.id,
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(phoneWeb, score: 950),
      fallbacks: [resourceCandidate(cloudResource, score: 900), resourceCandidate(codexResource, score: 800)],
      catalog: [phoneWeb, cloudResource, codexResource]
    )

    let selected = try XCTUnwrap(
      AgentConnectorRouteSelector.select(
        targets: [codex, cloud],
        decision: decision,
        preferredTargetId: codex.id
      )
    )

    XCTAssertEqual(selected.decision?.primary?.resource.targetId, codex.id)
    XCTAssertEqual(selected.decision?.fallbacks.map(\.resource.targetId), [cloud.id])
  }

  func testAgentConnectorRouteSelectorRecoversReasoningTargetDuringHeartbeat() throws {
    var recovering = routeTarget("codex", kind: .agent)
    recovering.status = .disconnected

    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [recovering], decision: nil))

    XCTAssertEqual(selected.target.id, "codex")
    XCTAssertTrue(AgentConnectorRouteSelector.isDeliverable(recovering))
  }

  func testAgentConnectorRouteSelectorRejectsSetupAndDeviceOnlyTargets() {
    var unavailable = routeTarget("codex", kind: .agent)
    unavailable.status = .needsSetup
    let device = AgentCallableTarget(
      id: "device:lamp",
      title: "Lamp",
      kind: .device,
      status: .available,
      capabilities: [.deviceControl]
    )

    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [unavailable], decision: nil))
    XCTAssertFalse(AgentConnectorRouteSelector.isDeliverable(device))
    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [device], decision: nil))
  }

  func testAgentResourceRoutingModelsUseAndroidWireNames() throws {
    let codexResource = routingResource(
      targetId: "codex",
      type: .remoteAgent,
      location: .trustedDesktop
    )
    let decision = routingDecision(
      primary: resourceCandidate(codexResource, score: 800),
      fallbacks: [],
      catalog: [codexResource]
    )
    let encoded = try JSONEncoder().encode(decision)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let requirements = try XCTUnwrap(object["requirements"] as? [String: Any])
    let primary = try XCTUnwrap(object["primary"] as? [String: Any])
    let resource = try XCTUnwrap(primary["resource"] as? [String: Any])

    XCTAssertEqual(requirements["live_data_required"] as? Bool, true)
    XCTAssertEqual(requirements["estimated_input_tokens"] as? Int, 200)
    XCTAssertEqual(requirements["execution_horizon"] as? String, "INTERACTIVE")
    XCTAssertEqual(resource["target_id"] as? String, "codex")
    XCTAssertEqual(resource["supports_tools"] as? Bool, false)
    XCTAssertEqual(resource["context_window_tokens"] as? Int, 8_192)
    XCTAssertEqual(resource["max_parallel_tasks"] as? Int, 1)
    XCTAssertNotNil(object["task_budget"])
    XCTAssertNil(resource["targetId"])

    let decoded = try JSONDecoder().decode(
      AgentRoutingDecision.self,
      from: Data(
        #"{"requirements":{"capabilities":["live_data"],"mode":"fast"},"primary":{"resource":{"id":"resource:cloud","title":"Cloud","type":"cloud_model","location":"cloud","status":"available","capabilities":["research"],"cost":"low","latency":"fast","quality":"strong","supports_tools":true,"target_id":"cloud-model:deepseek"},"score":10,"reasons":["capability_match"]}}"#.utf8
      )
    )

    XCTAssertEqual(decoded.requirements.mode, .fast)
    XCTAssertEqual(decoded.requirements.liveDataRequired, true)
    XCTAssertEqual(decoded.requirements.executionHorizon, .interactive)
    XCTAssertEqual(decoded.primary?.resource.type, .cloudModel)
    XCTAssertEqual(decoded.primary?.resource.cost, .low)
    XCTAssertEqual(decoded.primary?.resource.latency, .fast)
    XCTAssertEqual(decoded.primary?.resource.quality, .strong)
    XCTAssertEqual(decoded.fallbacks, [])
  }

  func testAgentResourceCatalogBuildsTargetsToolsAndNativeTools() throws {
    let codex = AgentCallableTarget(
      id: "desktop:codex",
      title: "Codex",
      kind: .agent,
      status: .available,
      capabilities: [.chat, .code, .taskExecution, .toolUse],
      failureDomain: "desktop-dev",
      adapterType: "codex-app-server"
    )
    let qwenProfile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:qwen",
      provider: "Qwen",
      model: providerCloudModel(
        provider: "Qwen",
        modelId: "qwen3.7-max",
        endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      ),
      apiKey: "stored-key",
      performance: ProviderPerformanceProfile(attempts: 10, successes: 8, failures: 2, failureRate: 0.2)
    )
    let cloud = AgentCallableTarget(
      id: "cloud:qwen",
      title: "Qwen",
      kind: .model,
      status: .available,
      capabilities: Array(qwenProfile.capabilities),
      providerProfile: qwenProfile
    )
    let workflow = AgentSystemTool(
      id: "workflow:daily",
      title: "Daily workflow",
      kind: .draftPlan,
      risk: .low,
      capabilities: [.taskExecution]
    )
    let native = try nativeToolDescriptor(
      "signalasi.runtime.python",
      capabilities: ["runtime.python", "workspace.files"]
    )

    let catalog = AgentResourceCatalog.build(
      targets: [codex, cloud],
      tools: [workflow],
      nativeTools: [native]
    )
    let codexResource = try XCTUnwrap(catalog.first { $0.id == "target:desktop:codex" })
    let cloudResource = try XCTUnwrap(catalog.first { $0.id == "target:cloud:qwen" })
    let workflowResource = try XCTUnwrap(catalog.first { $0.id == "tool:workflow:daily" })
    let nativeResource = try XCTUnwrap(catalog.first { $0.id == "native:\(native.id)" })

    XCTAssertEqual(codexResource.type, .remoteAgent)
    XCTAssertEqual(codexResource.location, .trustedDesktop)
    XCTAssertEqual(codexResource.targetId, codex.id)
    XCTAssertEqual(codexResource.failureDomain, "desktop-dev")
    XCTAssertTrue(codexResource.supportsBackground)
    XCTAssertEqual(cloudResource.contextWindowTokens, qwenProfile.contextWindowTokens)
    XCTAssertEqual(cloudResource.cost, qwenProfile.pricing.tier)
    XCTAssertEqual(cloudResource.latency, qwenProfile.latency)
    XCTAssertEqual(cloudResource.providerProfile?.performance.failureRate, 0.2)
    XCTAssertEqual(workflowResource.type, .localSkill)
    XCTAssertEqual(workflowResource.status, .available)
    XCTAssertEqual(workflowResource.trust, .phoneSystem)
    XCTAssertEqual(workflowResource.energy, .minimal)
    XCTAssertEqual(workflowResource.maxParallelTasks, 4)
    XCTAssertEqual(nativeResource.type, .localTool)
    XCTAssertEqual(nativeResource.energy, .high)
    XCTAssertTrue(nativeResource.supportsBackground)
    XCTAssertTrue(nativeResource.capabilities.isSuperset(of: Set([.toolUse, .code, .taskExecution])))
  }

  func testAgentResourceCatalogMapsCapabilitySnapshotStatus() throws {
    let available = try nativeToolDescriptor("signalasi.test.available")
    let unavailable = try nativeToolDescriptor(
      "signalasi.test.unavailable",
      availability: AgentNativeToolAvailability(status: .unavailable, reason: "Missing")
    )
    let target = AgentCallableTarget(
      id: "codex",
      title: "Codex",
      kind: .agent,
      status: .disconnected,
      capabilities: [.code]
    )

    let catalog = AgentResourceCatalog.build(
      targets: [target],
      tools: [],
      nativeTools: [available, unavailable]
    )

    XCTAssertEqual(catalog.first { $0.id == "target:codex" }?.status, .disconnected)
    XCTAssertEqual(catalog.first { $0.id == "native:\(available.id)" }?.status, .available)
    XCTAssertEqual(catalog.first { $0.id == "native:\(unavailable.id)" }?.status, .disconnected)
  }

  func testAgentResourceCatalogClassifiesRemoteTargets() {
    let targets = [
      AgentCallableTarget(
        id: "home-assistant",
        title: "Home Assistant",
        kind: .device,
        status: .available,
        capabilities: [.smartHome]
      ),
      AgentCallableTarget(
        id: "custom-device:lamp",
        title: "Lamp",
        kind: .device,
        status: .available,
        capabilities: [.deviceControl]
      ),
      AgentCallableTarget(
        id: "remote-mcp:github",
        title: "GitHub MCP",
        kind: .agent,
        status: .available,
        capabilities: [.mcp, .toolUse]
      ),
      AgentCallableTarget(
        id: "remote-skill:summary",
        title: "Summary Skill",
        kind: .agent,
        status: .available,
        capabilities: [.skill, .toolUse]
      ),
      AgentCallableTarget(
        id: "knowledge:docs",
        title: "Docs",
        kind: .knowledge,
        status: .available,
        capabilities: [.knowledgeSearch]
      ),
      AgentCallableTarget(
        id: "local-llm",
        title: "Local LLM",
        kind: .model,
        status: .available,
        capabilities: [.chat, .localInference]
      )
    ]

    let catalog = AgentResourceCatalog.build(targets: targets, tools: [])

    XCTAssertEqual(catalog.first { $0.targetId == "home-assistant" }?.type, .homeAssistant)
    XCTAssertEqual(catalog.first { $0.targetId == "home-assistant" }?.location, .privateNetwork)
    XCTAssertEqual(catalog.first { $0.targetId == "custom-device:lamp" }?.type, .customDevice)
    XCTAssertEqual(catalog.first { $0.targetId == "remote-mcp:github" }?.type, .remoteMcp)
    XCTAssertEqual(catalog.first { $0.targetId == "remote-skill:summary" }?.type, .remoteSkill)
    XCTAssertEqual(catalog.first { $0.targetId == "knowledge:docs" }?.location, .phone)
    XCTAssertEqual(catalog.first { $0.targetId == "local-llm" }?.type, .remoteLocalModel)
    XCTAssertEqual(catalog.first { $0.targetId == "local-llm" }?.maxParallelTasks, 2)
  }

  func testCallableTargetCatalogUsesOnlyActiveLocalModelIdentity() {
    let profile = LocalModelRuntimeProfiles.GEMMA_3_4B_Q4
    let hidden = AgentCallableTargetCatalog.build(
      contacts: [],
      apiKey: { _ in nil },
      activeLocalProfiles: [],
      localModelReady: { _ in true }
    )
    let visible = AgentCallableTargetCatalog.build(
      contacts: [],
      apiKey: { _ in nil },
      activeLocalProfiles: [profile],
      localModelReady: { _ in true }
    )

    XCTAssertNil(hidden.first { $0.id == "local-llm" })
    XCTAssertEqual(visible.first { $0.id == "local-llm" }?.title, profile.displayName)
    XCTAssertEqual(visible.first { $0.id == "local-llm" }?.status, .available)
  }

  func testExecutionTargetReplacesInternalLocalRouteWithModelName() {
    XCTAssertEqual(
      AgentExecutionTargetStatusPolicy.resolveLabel(
        connectorId: "local-llm",
        activeLocalModelName: "Gemma 3 4B Q4",
        contacts: []
      ),
      "Gemma 3 4B Q4"
    )
    XCTAssertEqual(
      AgentExecutionTargetStatusPolicy.resolveLabel(
        runtimeTarget: "Local Model",
        activeLocalModelName: "",
        contacts: []
      ),
      ""
    )
    XCTAssertEqual(
      AgentExecutionTargetStatusPolicy.resolveLabel(
        connectorId: "local-llm",
        runtimeTarget: "Gemma 3 1B Q4_K_M",
        activeLocalModelName: "",
        contacts: []
      ),
      "Gemma 3 1B Q4_K_M"
    )
  }

  func testAgentResourceCatalogModelsUseAndroidWireNames() throws {
    let profile = ProviderProfileCatalog.fromCloudModel(
      resourceId: "cloud:deepseek",
      provider: "DeepSeek",
      model: providerCloudModel(
        provider: "DeepSeek",
        modelId: "deepseek-v4-pro",
        endpoint: "https://api.deepseek.com/chat/completions"
      ),
      apiKey: "stored-key"
    )
    let catalog = AgentResourceCatalog.build(
      targets: [
        AgentCallableTarget(
          id: "cloud:deepseek",
          title: "DeepSeek",
          kind: .model,
          status: .available,
          capabilities: Array(profile.capabilities),
          providerProfile: profile
        )
      ],
      tools: []
    )
    let resource = try XCTUnwrap(catalog.first)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(resource)) as? [String: Any]
    )

    XCTAssertEqual(object["target_id"] as? String, "cloud:deepseek")
    XCTAssertEqual(object["supports_background"] as? Bool, true)
    XCTAssertEqual(object["max_parallel_tasks"] as? Int, 4)
    XCTAssertNotNil(object["provider_profile"])
    XCTAssertNil(object["targetId"])
    XCTAssertNil(object["supportsBackground"])
  }

}
