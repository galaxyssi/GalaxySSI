import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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

    XCTAssertEqual(contextObject["invocation_id"] as? String, "invoke-1")
    XCTAssertEqual(contextObject["session_id"] as? String, "session")
    XCTAssertEqual(contextObject["idempotency_key"] as? String, "key")
    XCTAssertEqual(contextObject["granted_permissions"] as? [String], ["permission.a", "permission.b"])
    XCTAssertNil(contextObject["invocationId"])
    XCTAssertEqual(decisionObject["tool_id"] as? String, "galaxyssi.test.tool")
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
