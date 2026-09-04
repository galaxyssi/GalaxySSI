import XCTest

extension GalaxySSIStoreTests {
  func testAgentNativeToolDefaultStorePathsUseSeparateFiles() throws {
    let root = try temporaryDirectory("native-tool-default-paths")
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = AgentNativeToolDefaultStorePaths(rootURL: root)

    XCTAssertEqual(paths.replayFileURL.lastPathComponent, "replay_entries.json")
    XCTAssertEqual(paths.auditFileURL.lastPathComponent, "audit_records.json")
    XCTAssertEqual(paths.workspaceFileURL.lastPathComponent, "workspace_state.json")
    XCTAssertEqual(paths.replayFileURL.deletingLastPathComponent(), root)
    XCTAssertEqual(paths.auditFileURL.deletingLastPathComponent(), root)
    XCTAssertEqual(paths.workspaceFileURL.deletingLastPathComponent(), root)
  }

  func testAgentPhoneNativeToolCatalogDefaultRegistryPersistsReplayAuditAndWorkspace() throws {
    let root = try temporaryDirectory("native-tool-default-stores")
    defer { try? FileManager.default.removeItem(at: root) }
    var now: Int64 = 1_000
    let actionExecutor = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "Executed")
    }

    func registry() throws -> AgentNativeToolRegistry {
      try AgentPhoneNativeToolCatalog.defaultRegistry(
        actionExecutor: actionExecutor,
        screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
        capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
        storageRootURL: root,
        nowMillis: { now }
      )
    }

    let first = try registry().invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("persistent")],
      context: AgentNativeToolInvocationContext(
        invocationId: "persistent-first",
        idempotencyKey: "persistent-request",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    now += 1
    let replay = try registry().invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("persistent")],
      context: AgentNativeToolInvocationContext(
        invocationId: "persistent-second",
        idempotencyKey: "persistent-request",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )

    XCTAssertTrue(first.toJson(), first.isSuccess)
    XCTAssertTrue(replay.toJson(), replay.receipt.replayed)
    XCTAssertEqual(replay.receipt.originalInvocationId, "persistent-first")

    let write = try registry().invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: [
        "workspace_id": .string("persistent"),
        "path": .string("notes/readme.txt"),
        "text": .string("restored after registry rebuild"),
        "create_parents": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "persistent-write",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let read = try registry().invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("persistent"),
        "path": .string("notes/readme.txt")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "persistent-read",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )

    XCTAssertTrue(write.toJson(), write.isSuccess)
    XCTAssertTrue(read.toJson(), read.isSuccess)
    XCTAssertEqual(read.output["text"], .string("restored after registry rebuild"))

    let paths = AgentNativeToolDefaultStorePaths(rootURL: root)
    let audit = FileAgentNativeToolAuditStore(fileURL: paths.auditFileURL)
    XCTAssertEqual(
      audit.list(limit: 10, toolId: AgentPhoneNativeToolCatalog.workspaceInitialize, status: .succeeded).map(\.replayed),
      [true, false]
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: paths.replayFileURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: paths.auditFileURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: paths.workspaceFileURL.path))
  }

  func testAgentPhoneNativeToolCatalogDefaultRuntimeExecutesNativeToolActions() throws {
    let root = try temporaryDirectory("native-tool-default-runtime")
    defer { try? FileManager.default.removeItem(at: root) }
    var delegatedAction: AgentAction?
    var events: [AgentNativeToolLifecycleEvent] = []
    let delegate = TestAgentActionExecutor { action, _ in
      delegatedAction = action
      return AgentActionResult(actionId: action.id, success: true, message: "delegated")
    }
    let notificationPublisher = InMemoryAgentActionNotificationPublisher()
    let runtime = try AgentPhoneNativeToolCatalog.defaultRuntime(
      actionExecutor: delegate,
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
      storageRootURL: root,
      nowMillis: { 20_000 },
      actionNotificationPublisher: notificationPublisher,
      nativeToolEventSink: AgentNativeToolLifecycleEventSink { events.append($0) }
    )
    let nativeAction = AgentAction(
      id: "runtime-init",
      kind: .callNativeTool,
      target: "Workspace",
      risk: .medium,
      status: .running,
      description: "Initialize the current workspace",
      parameters: [
        "tool_id": AgentPhoneNativeToolCatalog.workspaceInitialize,
        "input_json": #"{"workspace_id":"foreign"}"#,
        "_galaxyssi_conversation_id": "runtime-conversation"
      ],
      requiresConfirmation: false
    )
    let openURL = AgentAction(
      id: "runtime-open",
      kind: .openURL,
      target: "https://galaxyssi.com",
      risk: .low,
      status: .running,
      description: "Open GalaxySSI"
    )

    let nativeResult = runtime.actionExecutor.execute(
      action: nativeAction,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )
    let delegatedResult = runtime.actionExecutor.execute(
      action: openURL,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    XCTAssertTrue(nativeResult.success)
    XCTAssertEqual(nativeResult.metadata["native_tool_id"], AgentPhoneNativeToolCatalog.workspaceInitialize)
    XCTAssertEqual(nativeResult.metadata["idempotency_key"], "runtime-init")
    XCTAssertEqual(nativeResult.metadata["serialized_side_effect"], "true")
    XCTAssertTrue(
      (nativeResult.metadata["native_tool_output"] ?? "")
        .contains(AgentWorkspaceScope.id(conversationId: "runtime-conversation"))
    )
    XCTAssertTrue(delegatedResult.success)
    XCTAssertEqual(delegatedResult.metadata["serialized_side_effect"], "true")
    XCTAssertEqual(delegate.callCount, 1)
    XCTAssertEqual(delegatedAction?.id, "runtime-open")
    XCTAssertEqual(events.map(\.stage), [.started, .finished])
    XCTAssertEqual(events.map(\.toolId), [
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      AgentPhoneNativeToolCatalog.workspaceInitialize
    ])
    XCTAssertEqual(events.first?.stepId, "runtime-init")
    XCTAssertEqual(events.last?.status, .succeeded)
    XCTAssertEqual(notificationPublisher.notifications().map(\.phase), [.running, .succeeded, .running, .succeeded])
    let notificationIds = notificationPublisher.notifications().map(\.notificationId)
    XCTAssertEqual(notificationIds[0], notificationIds[1])
    XCTAssertEqual(notificationIds[2], notificationIds[3])
    XCTAssertNotEqual(notificationIds[0], notificationIds[2])
  }
}
