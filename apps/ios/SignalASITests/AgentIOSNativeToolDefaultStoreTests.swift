import XCTest

extension SignalASIStoreTests {
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
        screenProvider: { _ in AgentScreenContext(foregroundApp: "SignalASI", pageTitle: "Agent") },
        capabilityStatuses: readyPhoneCapabilityStatuses(),
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
}
