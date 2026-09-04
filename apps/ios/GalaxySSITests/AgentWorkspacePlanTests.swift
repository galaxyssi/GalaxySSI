import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentWorkspaceNativeToolExecutorWritesTextBatchAtomically() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 1_500 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "batch",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
    )

    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("batch")],
      context: context
    )
    let batch = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteTextBatch,
      input: [
        "workspace_id": .string("batch"),
        "files": .array([
          .object(["path": .string("project/README.md"), "text": .string("hello")]),
          .object(["path": .string("project/Sources/main.swift"), "text": .string("print(\"Hi\")")])
        ])
      ],
      context: context
    )
    let duplicate = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteTextBatch,
      input: [
        "workspace_id": .string("batch"),
        "files": .array([
          .object(["path": .string("project/README.md"), "text": .string("changed")]),
          .object(["path": .string("project/README.md"), "text": .string("duplicate")])
        ])
      ],
      context: context
    )
    let parentConflict = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteTextBatch,
      input: [
        "workspace_id": .string("batch"),
        "files": .array([
          .object(["path": .string("project/new.swift"), "text": .string("file")]),
          .object(["path": .string("project/new.swift/child.txt"), "text": .string("child")])
        ])
      ],
      context: context
    )
    let read = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: ["workspace_id": .string("batch"), "path": .string("project/README.md")],
      context: AgentNativeToolInvocationContext(
        invocationId: "batch-read",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )
    let rejectedFile = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: ["workspace_id": .string("batch"), "path": .string("project/new.swift")],
      context: AgentNativeToolInvocationContext(
        invocationId: "batch-rejected-read",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )

    XCTAssertTrue(batch.isSuccess)
    XCTAssertEqual((batch.output["files"]?.arrayValue ?? []).count, 2)
    XCTAssertEqual(batch.output["affected_entries"], .int(2))
    XCTAssertEqual(batch.output["affected_bytes"], .int(16))
    XCTAssertFalse(duplicate.isSuccess)
    XCTAssertFalse(parentConflict.isSuccess)
    XCTAssertEqual(read.output["text"], .string("hello"))
    XCTAssertFalse(rejectedFile.isSuccess)
  }

  func testAgentWorkspaceNativeToolExecutorRunsCoreFileWorkflowThroughRegistry() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 1_234 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "workspace-call",
      idempotencyKey: "workspace-key",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [
        AgentPhoneNativeToolCatalog.workspaceReadConsent,
        AgentPhoneNativeToolCatalog.workspaceWriteConsent
      ]
    )

    let initialized = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("alpha")],
      context: context
    )
    let created = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "text": .string("hello"),
        "create_parents": .bool(true)
      ],
      context: context
    )
    let appended = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceAppendText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "text": .string(" world")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "append",
        idempotencyKey: "append-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let read = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt")
      ],
      context: context
    )
    let listing = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceList,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs"),
        "recursive": .bool(true)
      ],
      context: context
    )
    let patched = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceApplyExactPatch,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt"),
        "expected_text": .string("world"),
        "replacement_text": .string("iOS")
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "patch",
        idempotencyKey: "patch-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let digest = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceSha256,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs/note.txt")
      ],
      context: context
    )
    let search = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceSearchText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("docs"),
        "query": .string("ios")
      ],
      context: context
    )

    XCTAssertTrue(initialized.isSuccess)
    XCTAssertEqual(initialized.output["kind"], .string("initialize"))
    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(created.output["affected_entries"], .int(1))
    XCTAssertTrue(appended.isSuccess)
    XCTAssertEqual(read.output["text"], .string("hello world"))
    XCTAssertEqual(read.output["size_bytes"], .int(11))
    XCTAssertEqual((listing.output["entries"]?.arrayValue ?? []).count, 2)
    XCTAssertEqual(patched.output["replacements"], .int(1))
    XCTAssertEqual(digest.output["algorithm"], .string("SHA-256"))
    XCTAssertEqual(digest.output["hex"]?.stringValue?.count, 64)
    XCTAssertEqual((search.output["matches"]?.arrayValue ?? []).count, 1)
  }

  func testAgentWorkspaceNativeToolExecutorSupportsBytesMoveCopyDeleteAndErrors() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 2_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let context = AgentNativeToolInvocationContext(
      invocationId: "bytes",
      idempotencyKey: "bytes-key",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [
        AgentPhoneNativeToolCatalog.workspaceReadConsent,
        AgentPhoneNativeToolCatalog.workspaceWriteConsent
      ]
    )
    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("binary")],
      context: context
    )
    let created = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("data/blob.bin"),
        "base64": .string(Data([1, 2, 3]).base64EncodedString()),
        "create_parents": .bool(true)
      ],
      context: context
    )
    let read = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadBytes,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("data/blob.bin")
      ],
      context: context
    )
    let copied = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCopy,
      input: [
        "workspace_id": .string("binary"),
        "source_path": .string("data/blob.bin"),
        "destination_path": .string("copy/blob.bin"),
        "create_parents": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "copy",
        idempotencyKey: "copy-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let moved = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceMove,
      input: [
        "workspace_id": .string("binary"),
        "source_path": .string("copy/blob.bin"),
        "destination_path": .string("moved/blob.bin"),
        "create_parents": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "move",
        idempotencyKey: "move-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let deleted = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceDelete,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("moved"),
        "recursive": .bool(true)
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "delete",
        idempotencyKey: "delete-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let escaped = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: [
        "workspace_id": .string("binary"),
        "path": .string("../escape.txt"),
        "text": .string("bad")
      ],
      context: context
    )

    XCTAssertTrue(created.isSuccess)
    XCTAssertEqual(read.output["base64"], .string(Data([1, 2, 3]).base64EncodedString()))
    XCTAssertEqual(copied.output["affected_entries"], .int(1))
    XCTAssertEqual(moved.output["affected_entries"], .int(1))
    XCTAssertEqual(deleted.output["affected_entries"], .int(2))
    XCTAssertEqual(escaped.status, .failed)
    XCTAssertEqual(escaped.error?.code, "workspace_file_error")
    XCTAssertEqual(escaped.error?.details["workspace_error"]?.objectValue?["code"], .string("PATH_ESCAPE"))
  }

  func testAgentWorkspaceNativeToolExecutorGatesConsentAndReportsInvalidZip() throws {
    let store = AgentWorkspaceNativeToolExecutor()
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    let missingConsent = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceWriteText,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("note.txt"),
        "text": .string("hello")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission]
      )
    )
    let createdBadZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("alpha"),
        "path": .string("bundle.zip"),
        "base64": .string(Data("not a zip".utf8).base64EncodedString())
      ],
      context: AgentNativeToolInvocationContext(
        invocationId: "bad-zip-create",
        idempotencyKey: "bad-zip-key",
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    )
    let invalidZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("alpha"),
        "archive_path": .string("bundle.zip")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
      )
    )

    XCTAssertEqual(Set(registry.ids()), Set(AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store).map(\.id)))
    XCTAssertEqual(missingConsent.status, .rejected)
    XCTAssertEqual(missingConsent.error?.code, "missing_consents")
    XCTAssertTrue(createdBadZip.isSuccess)
    XCTAssertEqual(invalidZip.status, .failed)
    XCTAssertEqual(invalidZip.error?.details["workspace_error"]?.objectValue?["code"], .string("INVALID_ARCHIVE"))
  }

  func testAgentWorkspaceNativeToolExecutorCreatesListsAndExtractsZipArchives() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 5_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    func writeContext(_ invocationId: String, _ idempotencyKey: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    }
    let readContext = AgentNativeToolInvocationContext(
      invocationId: "zip-read",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
    )

    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("zip")],
      context: writeContext("zip-init", "zip-init-key")
    )
    let firstFile = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("docs/a.txt"),
        "text": .string("alpha"),
        "create_parents": .bool(true)
      ],
      context: writeContext("zip-first-file", "zip-first-key")
    )
    let secondFile = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("docs/nested/b.txt"),
        "text": .string("beta"),
        "create_parents": .bool(true)
      ],
      context: writeContext("zip-second-file", "zip-second-key")
    )
    let createdZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipCreate,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip"),
        "source_paths": .array([.string("docs")])
      ],
      context: writeContext("zip-create", "zip-create-key")
    )
    let listedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip")
      ],
      context: readContext
    )
    let extractedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipExtract,
      input: [
        "workspace_id": .string("zip"),
        "archive_path": .string("bundle.zip"),
        "destination_path": .string("unpacked")
      ],
      context: writeContext("zip-extract", "zip-extract-key")
    )
    let unpackedFirst = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("unpacked/docs/a.txt")
      ],
      context: readContext
    )
    let unpackedSecond = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip"),
        "path": .string("unpacked/docs/nested/b.txt")
      ],
      context: readContext
    )

    let createdEntries = createdZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []
    let listedEntries = listedZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []

    XCTAssertTrue(firstFile.isSuccess)
    XCTAssertTrue(secondFile.isSuccess)
    XCTAssertTrue(createdZip.isSuccess)
    XCTAssertGreaterThan(createdZip.output["archive_bytes"]?.intValue ?? 0, 0)
    XCTAssertEqual(createdZip.output["total_compressed_bytes"], .int(9))
    XCTAssertEqual(createdZip.output["total_uncompressed_bytes"], .int(9))
    XCTAssertEqual(createdEntries.compactMap { $0["path"]?.stringValue }, [
      "docs",
      "docs/a.txt",
      "docs/nested",
      "docs/nested/b.txt"
    ])
    XCTAssertEqual(createdEntries.filter { $0["directory"]?.boolValue == false }.count, 2)
    XCTAssertTrue(createdEntries.allSatisfy { $0["last_modified_epoch_ms"] != nil })
    XCTAssertTrue(listedZip.isSuccess)
    XCTAssertEqual(listedZip.output["archive_bytes"], createdZip.output["archive_bytes"])
    XCTAssertEqual(listedEntries.compactMap { $0["path"]?.stringValue }, createdEntries.compactMap { $0["path"]?.stringValue })
    XCTAssertTrue(extractedZip.isSuccess)
    XCTAssertEqual(extractedZip.output["extracted_entries"], .int(4))
    XCTAssertEqual(extractedZip.output["extracted_bytes"], .int(9))
    XCTAssertEqual(unpackedFirst.output["text"], .string("alpha"))
    XCTAssertEqual(unpackedSecond.output["text"], .string("beta"))
  }

  func testAgentWorkspaceNativeToolExecutorExtractsDeflatedZipArchives() throws {
    let store = AgentWorkspaceNativeToolExecutor(nowMillis: { 6_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.workspaceExecutableDefinitions(store: store)
    )
    func writeContext(_ invocationId: String, _ idempotencyKey: String) -> AgentNativeToolInvocationContext {
      AgentNativeToolInvocationContext(
        invocationId: invocationId,
        idempotencyKey: idempotencyKey,
        grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
        grantedConsents: [AgentPhoneNativeToolCatalog.workspaceWriteConsent]
      )
    }
    let readContext = AgentNativeToolInvocationContext(
      invocationId: "zip-deflate-read",
      grantedPermissions: [AgentPhoneNativeToolCatalog.workspacePrivatePermission],
      grantedConsents: [AgentPhoneNativeToolCatalog.workspaceReadConsent]
    )

    _ = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceInitialize,
      input: ["workspace_id": .string("zip-deflate")],
      context: writeContext("zip-deflate-init", "zip-deflate-init-key")
    )
    let createdZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceCreateBytes,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("bundle.zip"),
        "base64": .string(deflatedZipArchive(
          ("docs/a.txt", "alpha"),
          ("docs/nested/b.txt", "beta")
        ).base64EncodedString())
      ],
      context: writeContext("zip-deflate-create", "zip-deflate-create-key")
    )
    let listedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipList,
      input: [
        "workspace_id": .string("zip-deflate"),
        "archive_path": .string("bundle.zip")
      ],
      context: readContext
    )
    let extractedZip = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceZipExtract,
      input: [
        "workspace_id": .string("zip-deflate"),
        "archive_path": .string("bundle.zip"),
        "destination_path": .string("unpacked")
      ],
      context: writeContext("zip-deflate-extract", "zip-deflate-extract-key")
    )
    let unpackedFirst = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("unpacked/docs/a.txt")
      ],
      context: readContext
    )
    let unpackedSecond = registry.invoke(
      AgentPhoneNativeToolCatalog.workspaceReadText,
      input: [
        "workspace_id": .string("zip-deflate"),
        "path": .string("unpacked/docs/nested/b.txt")
      ],
      context: readContext
    )

    let listedEntries = listedZip.output["entries"]?.arrayValue?.compactMap(\.objectValue) ?? []

    XCTAssertTrue(createdZip.isSuccess)
    XCTAssertTrue(listedZip.isSuccess)
    XCTAssertEqual(listedEntries.compactMap { $0["path"]?.stringValue }, ["docs/a.txt", "docs/nested/b.txt"])
    XCTAssertEqual(listedZip.output["total_uncompressed_bytes"], .int(9))
    XCTAssertTrue(extractedZip.isSuccess)
    XCTAssertEqual(extractedZip.output["extracted_entries"], .int(2))
    XCTAssertEqual(extractedZip.output["extracted_bytes"], .int(9))
    XCTAssertEqual(unpackedFirst.output["text"], .string("alpha"))
    XCTAssertEqual(unpackedSecond.output["text"], .string("beta"))
  }

  func testAgentPlanFactoryCollapsesDuplicateConnectorCallsAndRemapsDependencies() {
    let first = planConnectorAction(id: "codex-1", connectorId: "desktop:codex")
    let duplicate = planConnectorAction(id: "codex-2", connectorId: "desktop:codex")
    let dependent = AgentAction(
      id: "finish",
      kind: .createNotification,
      target: "phone",
      risk: .low,
      status: .pendingConfirmation,
      description: "Notify when complete",
      parameters: ["depends_on": duplicate.id]
    )

    let plan = AgentPlanFactory.actions(request: planFactoryRequest(), [first, duplicate, dependent])

    XCTAssertEqual(plan.actions.map(\.id), ["codex-1", "finish"])
    XCTAssertEqual(plan.actions.last?.parameters["depends_on"], "codex-1")
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryKeepsDifferentConnectorsIndependent() {
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(
        targets: [
          planFactoryTarget(id: "desktop:codex", title: "Codex"),
          planFactoryTarget(id: "desktop:hermes", title: "Hermes")
        ]
      ),
      [
        planConnectorAction(id: "codex", connectorId: "desktop:codex", target: "Codex"),
        planConnectorAction(id: "hermes", connectorId: "desktop:hermes", target: "Hermes")
      ]
    )

    XCTAssertEqual(plan.actions.map(\.id), ["codex", "hermes"])
    XCTAssertEqual(plan.selectedAgentOrModel, "Multiple Executors")
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryRewritesHomeAssistantControlDeviceToNativeTool() throws {
    let tool = try nativeToolDescriptor(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      risk: .medium,
      idempotency: .idempotencyKeyRequired
    )
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(
        targets: [
          planFactoryTarget(
            id: "home-assistant",
            title: "Home Assistant",
            kind: .device,
            capabilities: [.deviceControl]
          )
        ],
        nativeTools: [tool]
      ),
      [
        AgentAction(
          id: "control-office-light",
          kind: .controlDevice,
          target: "Home Assistant",
          risk: .low,
          status: .pendingConfirmation,
          description: "Turn on the office light",
          parameters: [
            "connector_id": "home-assistant",
            "prompt": "Turn on light.office"
          ]
        )
      ]
    )
    let action = try XCTUnwrap(plan.actions.first)
    let inputJson = try XCTUnwrap(action.parameters["input_json"])
    let input = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(inputJson.utf8)) as? [String: Any]
    )

    XCTAssertEqual(action.kind, .callNativeTool)
    let expectedInput = AgentHomeAssistantServiceCallRequest(
      serviceDomain: "homeassistant",
      service: "turn_on",
      entityId: "light.office"
    ).nativeToolInput
    XCTAssertEqual(action.id, "home-assistant-service-\(AgentMcpJSONCodec.sha256(expectedInput).prefix(16))")
    XCTAssertEqual(action.target, "light.office")
    XCTAssertEqual(action.risk, .medium)
    XCTAssertEqual(action.parameters["tool_id"], AgentIOSHomeAssistantNativeToolCatalog.serviceCall)
    XCTAssertEqual(action.parameters["connector_id"], "home-assistant")
    XCTAssertEqual(action.parameters["source_action_kind"], AgentActionKind.controlDevice.rawValue)
    XCTAssertEqual(input["service_domain"] as? String, "homeassistant")
    XCTAssertEqual(input["service"] as? String, "turn_on")
    XCTAssertEqual(input["entity_id"] as? String, "light.office")
    XCTAssertTrue(input["service_data"] is [String: Any])
    XCTAssertEqual(plan.route.kind, .localSystem)
    XCTAssertEqual(plan.expectedResult, "The selected phone-native tool returns a locally verified receipt.")
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryKeepsHomeAssistantControlDeviceWhenNativeToolCannotRun() throws {
    let unavailableTool = try nativeToolDescriptor(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      availability: AgentNativeToolAvailability(status: .requiresSetup)
    )
    let action = AgentAction(
      id: "control-office-light",
      kind: .controlDevice,
      target: "Home Assistant",
      risk: .medium,
      status: .pendingConfirmation,
      description: "Turn on the office light",
      parameters: [
        "connector_id": "home-assistant",
        "prompt": "Turn on light.office"
      ]
    )
    let unavailablePlan = AgentPlanFactory.actions(
      request: planFactoryRequest(
        targets: [
          planFactoryTarget(id: "home-assistant", title: "Home Assistant", kind: .device, capabilities: [.deviceControl])
        ],
        nativeTools: [unavailableTool]
      ),
      [action]
    )
    let missingEntityPlan = AgentPlanFactory.actions(
      request: planFactoryRequest(
        targets: [
          planFactoryTarget(id: "home-assistant", title: "Home Assistant", kind: .device, capabilities: [.deviceControl])
        ],
        nativeTools: [try nativeToolDescriptor(AgentIOSHomeAssistantNativeToolCatalog.serviceCall)]
      ),
      [AgentAction(
        id: "control-unspecified-light",
        kind: .controlDevice,
        target: "Home Assistant",
        risk: .medium,
        status: .pendingConfirmation,
        description: "Turn on the office light",
        parameters: ["connector_id": "home-assistant", "prompt": "Turn on the office light"]
      )]
    )

    XCTAssertEqual(unavailablePlan.actions.first?.kind, .controlDevice)
    XCTAssertEqual(unavailablePlan.route.kind, .deviceConnector)
    XCTAssertEqual(missingEntityPlan.actions.first?.kind, .controlDevice)
    XCTAssertNil(missingEntityPlan.actions.first?.parameters["tool_id"])
    XCTAssertTrue(unavailablePlan.validation.valid)
    XCTAssertTrue(missingEntityPlan.validation.valid)
  }

  func testAgentPlanFactoryEmptyPlanFallsBackToAvailableReasoningConnector() {
    let plan = AgentPlanFactory.actions(request: planFactoryRequest(), [])
    let action = plan.actions.first

    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(action?.kind, .callConnector)
    XCTAssertEqual(action?.parameters["connector_id"], "desktop:codex")
    XCTAssertEqual(action?.parameters["planner_fallback"], "empty_action_plan")
    XCTAssertFalse(plan.actions.contains { $0.target == "local-agent-runtime" })
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryEmptyPlanWithoutProviderFailsExplicitly() {
    let plan = AgentPlanFactory.actions(request: planFactoryRequest(targets: []), [])
    let action = plan.actions.first

    XCTAssertEqual(plan.actions.count, 1)
    XCTAssertEqual(action?.kind, .callConnector)
    XCTAssertEqual(action?.parameters["connector_id"], AgentPlanFactory.unavailableReasoningConnectorId)
    XCTAssertFalse(plan.actions.contains { $0.target == "local-agent-runtime" })
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanFactoryKeepsRecoveringConnectorAuthorizedDuringHeartbeat() {
    let recovering = planFactoryTarget(
      id: "desktop:codex",
      title: "Codex",
      status: .disconnected,
      capabilities: [.chat, .reasoning]
    )
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(targets: [recovering]),
      [planConnectorAction(id: "codex", connectorId: recovering.id, target: recovering.title)]
    )

    XCTAssertEqual(plan.requiredPermissions.single { $0.id == "paired_contact" }?.granted, true)
    XCTAssertEqual(plan.route.kind, .desktopAgent)
  }

  func testAgentPlanFactoryDoesNotAuthorizeConnectorThatNeedsSetup() {
    let unavailable = planFactoryTarget(
      id: "desktop:codex",
      title: "Codex",
      status: .needsSetup,
      capabilities: [.chat, .reasoning]
    )
    let plan = AgentPlanFactory.actions(
      request: planFactoryRequest(targets: [unavailable]),
      [planConnectorAction(id: "codex", connectorId: unavailable.id, target: unavailable.title)]
    )

    XCTAssertEqual(plan.requiredPermissions.single { $0.id == "paired_contact" }?.granted, false)
    XCTAssertTrue(plan.validation.valid)
  }

  func testAgentPlanRequestModelsUseAndroidWireNames() throws {
    let request = AgentPlanRequest(
      goal: "Convert the file",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      targets: [planFactoryTarget()],
      nativeTools: [try nativeToolDescriptor("galaxyssi.test.native")],
      contextDigest: "digest"
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )

    XCTAssertEqual(object["context_digest"] as? String, "digest")
    XCTAssertNotNil(object["native_tools"])
    XCTAssertNil(object["contextDigest"])
    XCTAssertNil(object["nativeTools"])
  }

}
