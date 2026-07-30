import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentPhoneNativeToolCatalogRegistersStableDefaultIds() {
    var expected: Set<String> = [
      "signalasi.workspace.initialize",
      "signalasi.workspace.directory.create",
      "signalasi.workspace.directory.list",
      "signalasi.workspace.file.stat",
      "signalasi.workspace.file.read.text",
      "signalasi.workspace.file.read.bytes",
      "signalasi.workspace.file.write.text",
      "signalasi.workspace.file.create.text",
      "signalasi.workspace.file.append.text",
      "signalasi.workspace.file.write.bytes",
      "signalasi.workspace.file.create.bytes",
      "signalasi.workspace.file.append.bytes",
      "signalasi.workspace.entry.move",
      "signalasi.workspace.entry.copy",
      "signalasi.workspace.entry.delete",
      "signalasi.workspace.file.search.text",
      "signalasi.workspace.file.patch.exact",
      "signalasi.workspace.file.diff.summary",
      "signalasi.workspace.file.sha256",
      "signalasi.workspace.zip.create",
      "signalasi.workspace.zip.list",
      "signalasi.workspace.zip.extract",
      "signalasi.agent_action.read.screen",
      "signalasi.agent_action.tap",
      "signalasi.agent_action.type.text",
      "signalasi.agent_action.swipe",
      "signalasi.agent_action.long.press",
      "signalasi.agent_action.delete.text",
      "signalasi.agent_action.paste.text",
      "signalasi.agent_action.copy.screen.text",
      "signalasi.agent_action.back",
      "signalasi.agent_action.home",
      "signalasi.agent_action.recents",
      "signalasi.agent_action.lock.screen",
      "signalasi.agent_action.open.app",
      "signalasi.agent_action.open.url",
      "signalasi.agent_action.set.alarm",
      "signalasi.agent_action.reply.notification"
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
    let descriptors = AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: readyPhoneCapabilityStatuses())

    XCTAssertEqual(expected, AgentPhoneNativeToolCatalog.toolIds)
    XCTAssertEqual(expected, Set(descriptors.map(\.id)))
    XCTAssertEqual(expected.count, descriptors.count)
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
    XCTAssertTrue(reply.availability.reason.contains("SignalASI-owned notification"))
  }

  func testAgentPhoneNativeToolCatalogDefaultIdsIncludeExpansionGroups() {
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.isSuperset(of: AgentPhoneNativeToolCatalog.toolIds))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.media.playback.handoff"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.web.intelligence.search"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.hardware.location.foreground.read"))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.status))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentIOSOnDeviceRuntimeNativeToolCatalog.execute))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.listConnections))
    XCTAssertTrue(AgentPhoneNativeToolCatalog.defaultToolIds.contains(AgentMcpNativeTools.callTool))
    XCTAssertFalse(AgentPhoneNativeToolCatalog.defaultToolIds.contains("signalasi.mcp.call_tool"))
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
      "signalasi.test.echo",
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

    XCTAssertEqual(registry.ids(), Set(["signalasi.test.echo"]))
    XCTAssertEqual(registry.lookup("signalasi.test.echo"), definition)
    XCTAssertThrowsError(try registry.register(AgentPhoneNativeToolDefinition(
      descriptor: try nativeToolDescriptor("signalasi.test.echo"),
      executorId: "duplicate.executor"
    )))

    let json = registry.catalogJson()
    XCTAssertTrue(json.contains("\"contract_version\":\"signalasi.phone-native-tools/1.0\""))
    XCTAssertTrue(json.contains("\"id\":\"signalasi.test.echo\""))
    XCTAssertTrue(json.contains("\"input_schema\""))
    XCTAssertTrue(json.contains("\"output_schema\""))
    XCTAssertTrue(json.contains("\"required_permissions\""))
    XCTAssertTrue(json.contains("\"required_consents\""))
    XCTAssertTrue(json.contains("\"timeout_ms\""))
    XCTAssertTrue(json.contains("\"checked_at_epoch_ms\":123"))
    XCTAssertTrue((json.range(of: "contacts.read")?.lowerBound ?? json.endIndex) < (json.range(of: "phone.local")?.lowerBound ?? json.startIndex))
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
        descriptor: try nativeToolDescriptor("signalasi.test.schema", inputSchema: schema),
        executorId: "test.executor"
      )
    ])

    let invalid = registry.validateInput("signalasi.test.schema", input: [
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
    XCTAssertTrue(registry.validateInput("signalasi.test.schema", input: [
      "name": .string("ok"),
      "count": .int(1),
      "mode": .string("safe")
    ]).isValid)
    XCTAssertEqual(registry.validateInput("signalasi.missing", input: [:]).issues.first?.code, "unknown_tool")
  }

  func testAgentNativeToolRegistryAuthorizesAvailabilityPermissionsAndConsents() throws {
    let permission = AgentNativePermissionRequirement(id: "ios.permission.camera", title: "Camera")
    let consent = AgentNativeConsentRequirement(id: "camera.capture", title: "Capture camera")
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.camera",
      requiredPermissions: [permission],
      requiredConsents: [consent],
      inputSchema: AgentNativeToolDescriptor.objectSchema()
    )
    let setup = try nativeToolDescriptor(
      "signalasi.test.setup",
      availability: AgentNativeToolAvailability(status: .requiresSetup, reason: "Needs configuration")
    )
    let blocked = try nativeToolDescriptor("signalasi.test.blocked", risk: .blocked)
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: setup, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: blocked, executorId: "test.executor")
    ])

    let missingPermission = registry.authorize("signalasi.test.camera", input: [:])
    let missingConsent = registry.authorize(
      "signalasi.test.camera",
      input: [:],
      context: AgentNativeToolInvocationContext(grantedPermissions: ["ios.permission.camera"])
    )
    let ready = registry.authorize(
      "signalasi.test.camera",
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
    XCTAssertEqual(registry.authorize("signalasi.test.setup").code, "tool_unavailable")
    XCTAssertEqual(registry.authorize("signalasi.test.blocked").code, "tool_blocked")
    XCTAssertEqual(registry.authorize("signalasi.missing").code, "unknown_tool")
  }

  func testAgentNativeToolRegistryProtectsIdempotencyKeys() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.idempotent",
      inputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("integer")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ],
      idempotency: .idempotencyKeyRequired
    )
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor")
    ])
    let missingKey = registry.authorize("signalasi.test.idempotent", input: ["value": .int(1)])
    let first = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "first", idempotencyKey: "request-1")
    )
    let replay = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(1)],
      context: AgentNativeToolInvocationContext(invocationId: "second", idempotencyKey: "request-1")
    )
    let conflict = registry.replayDecision(
      "signalasi.test.idempotent",
      input: ["value": .int(2)],
      context: AgentNativeToolInvocationContext(invocationId: "third", idempotencyKey: "request-1")
    )

    XCTAssertEqual(missingKey.code, "missing_idempotency_key")
    XCTAssertEqual(first.code, .accepted)
    XCTAssertEqual(replay.code, .replay)
    XCTAssertTrue(replay.replayed)
    XCTAssertEqual(replay.originalInvocationId, "first")
    XCTAssertEqual(conflict.code, .conflict)
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
        "url": .string("https://signalasi.com")
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
      toolId: "signalasi.test.tool",
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

    XCTAssertEqual(contextObject["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(contextObject["session_id"] as? String, "session")
    XCTAssertEqual(contextObject["idempotency_key"] as? String, "key")
    XCTAssertEqual(contextObject["granted_permissions"] as? [String], ["permission.a", "permission.b"])
    XCTAssertNil(contextObject["invocationId"])
    XCTAssertEqual(decisionObject["tool_id"] as? String, "signalasi.test.tool")
    XCTAssertNotNil(decisionObject["missing_permissions"])
    XCTAssertNotNil(decisionObject["validation_issues"])
    XCTAssertNil(decisionObject["missingPermissions"])
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

  func testAgentNativeToolResultModelsUseAndroidWireNames() throws {
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.result",
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
      "signalasi.test.preflight",
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
      "signalasi.test.invoke",
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
      "signalasi.test.invalid-output",
      outputSchema: [
        "type": .string("object"),
        "properties": .object(["value": .object(["type": .string("string")])]),
        "required": .array([.string("value")]),
        "additionalProperties": .bool(false)
      ]
    )
    let verificationFailed = try nativeToolDescriptor("signalasi.test.verification")
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
    let cancelledDescriptor = try nativeToolDescriptor("signalasi.test.cancelled")
    let timedDescriptor = try nativeToolDescriptor("signalasi.test.timeout", timeoutMillis: 5)
    let descriptorOnly = try nativeToolDescriptor("signalasi.test.descriptor-only")
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

  func testAgentNativeToolRegistryInvokeReplaysSuccessfulKeyedResults() throws {
    var executions = 0
    let replayStore = InMemoryAgentNativeToolReplayStore()
    let descriptor = try nativeToolDescriptor(
      "signalasi.test.replay",
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
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
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
      screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Browser") },
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
        "url": .string("https://signalasi.com"),
        "parameters": .object(["url": .string("https://signalasi.com")])
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
    XCTAssertEqual(captured.first?.parameters["url"], "https://signalasi.com")
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
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Settings") }
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
