import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
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
      screen: AgentScreenContext(foregroundApp: "SignalASI"),
      targets: [planFactoryTarget()],
      nativeTools: [try nativeToolDescriptor("signalasi.test.native")],
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

  func testAgentDynamicTeamCompilerBuildsVerifiedDagFromComplementaryAgents() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Research the latest API and implement a Python program with high quality",
        teamId: "dynamic-team"
      ),
      registrations: [
        networkRegistration(
          agentId: "hermes.office",
          displayName: "Hermes - Office PC",
          capabilities: [.chat, .reasoning, .research, .liveData, .toolUse],
          failureDomain: "desktop-office"
        ),
        networkRegistration(
          agentId: "codex.dev",
          displayName: "Codex - Development PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution, .toolUse],
          latency: .fast,
          failureDomain: "desktop-dev"
        ),
        networkRegistration(
          agentId: "claude-code.review",
          displayName: "Claude Code - Review PC",
          capabilities: [.chat, .reasoning, .code, .taskExecution],
          failureDomain: "desktop-review"
        ),
        networkRegistration(
          agentId: "auditor.independent",
          displayName: "Independent Auditor",
          capabilities: [.chat, .reasoning, .research],
          failureDomain: "cloud-audit"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(result.outcome, .team)
    XCTAssertEqual(result.primaryAgentId, "codex.dev")
    XCTAssertEqual(
      Set(result.assignments.map { $0.registration.agentId }),
      Set(["codex.dev", "hermes.office", "claude-code.review", "auditor.independent"])
    )
    let definition = try XCTUnwrap(result.definition)
    XCTAssertEqual(definition.members.filter { $0.deliveryMode == .respond }.count, 1)
    XCTAssertEqual(definition.collectiveCapabilities, Set([AgentCapability.liveData, AgentCapability.code]))
    let verifier = try XCTUnwrap(definition.members.first { $0.role == "independent verifier" })
    XCTAssertEqual(verifier.dependsOnAgentIds, Set(["hermes.office", "claude-code.review"]))
    let lead = try XCTUnwrap(definition.members.first { $0.agentId == result.primaryAgentId })
    XCTAssertEqual(
      lead.dependsOnAgentIds,
      Set(definition.members.filter { $0.deliveryMode == .observe }.map { $0.agentId })
    )
  }

  func testAgentDynamicTeamCompilerKeepsSimpleConversationSingleAgentAndHonorsPinnedIdentity() {
    let simple = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Hello"),
      registrations: [
        networkRegistration(agentId: "hermes", displayName: "Hermes", capabilities: [.chat, .reasoning])
      ],
      nowMillis: 1_000_000
    )
    let pinned = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Discuss the architecture",
        policy: AgentDynamicTeamPolicy(pinnedAgentIds: ["hermes.home"])
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.office",
          displayName: "Codex - Office PC",
          capabilities: [.chat, .reasoning],
          latency: .instant
        ),
        networkRegistration(
          agentId: "hermes.home",
          displayName: "Hermes - Home PC",
          capabilities: [.chat, .reasoning],
          latency: .normal
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(simple.outcome, .singleAgent)
    XCTAssertEqual(simple.primaryAgentId, "hermes")
    XCTAssertNil(simple.definition)
    XCTAssertEqual(pinned.primaryAgentId, "hermes.home")
    XCTAssertEqual(pinned.assignments.first?.registration.displayName, "Hermes - Home PC")
  }

  func testAgentDynamicTeamCompilerAppliesPrivacyVerifierAndRuntimeIdentityBoundaries() {
    let privateResult = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(goal: "Handle my private key locally only"),
      registrations: [
        networkRegistration(
          agentId: "phone.agent",
          displayName: "Phone Agent",
          location: .phone,
          trust: .phoneSystem,
          capabilities: [.chat, .reasoning],
          failureDomain: "phone"
        ),
        networkRegistration(
          agentId: "cloud.agent",
          displayName: "Cloud Agent",
          location: .cloud,
          trust: .cloudConfigured,
          capabilities: [.chat, .reasoning],
          failureDomain: "cloud"
        )
      ],
      nowMillis: 1_000_000
    )
    let sameDomain = [
      networkRegistration(
        agentId: "codex",
        displayName: "Codex",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      ),
      networkRegistration(
        agentId: "claude-code",
        displayName: "Claude Code",
        capabilities: [.chat, .code, .reasoning],
        failureDomain: "desktop-one"
      )
    ]
    let requiredVerifierRequest = AgentDynamicTeamRequest(
      goal: "Implement and verify a Python program",
      policy: AgentDynamicTeamPolicy(verificationMode: .required)
    )
    let blocked = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain,
      nowMillis: 1_000_000
    )
    let verified = AgentDynamicTeamCompiler().compile(
      request: requiredVerifierRequest,
      registrations: sameDomain + [
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let aliasBlocked = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        policy: AgentDynamicTeamPolicy(forceTeam: true)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex.alias-one",
          displayName: "Codex",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        ),
        networkRegistration(
          agentId: "codex.alias-two",
          displayName: "Codex Alias",
          capabilities: [.chat, .reasoning, .code],
          failureDomain: "desktop-one",
          runtimeFailureDomain: "desktop-one:codex"
        )
      ],
      nowMillis: 1_000_000
    )

    XCTAssertEqual(privateResult.primaryAgentId, "phone.agent")
    XCTAssertFalse(privateResult.assignments.contains { $0.registration.location == .cloud })
    XCTAssertEqual(blocked.outcome, .blocked)
    XCTAssertTrue(blocked.unfilledRoles.contains(.verifier))
    XCTAssertEqual(verified.outcome, .team)
    XCTAssertEqual(verified.assignments.first { $0.role == .verifier }?.failureDomain, "desktop-two")
    XCTAssertEqual(aliasBlocked.outcome, .blocked)
    XCTAssertEqual(aliasBlocked.assignments.count, 1)
  }

  func testAgentDynamicTeamCompilerModelsUseAndroidWireNames() throws {
    let result = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: "Implement and verify a Python program",
        teamId: "wire-team",
        policy: AgentDynamicTeamPolicy(verificationMode: .required)
      ),
      registrations: [
        networkRegistration(
          agentId: "codex",
          displayName: "Codex",
          capabilities: [.chat, .code, .reasoning],
          failureDomain: "desktop-one"
        ),
        networkRegistration(
          agentId: "auditor",
          displayName: "Auditor",
          capabilities: [.chat, .reasoning],
          failureDomain: "desktop-two"
        )
      ],
      nowMillis: 1_000_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    let definition = try XCTUnwrap(object["definition"] as? [String: Any])
    let members = try XCTUnwrap(definition["members"] as? [[String: Any]])

    XCTAssertEqual(object["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(object["estimated_cost_units"] as? Int, 0)
    XCTAssertNotNil(object["unfilled_roles"])
    XCTAssertEqual(definition["team_id"] as? String, "wire-team")
    XCTAssertEqual(definition["primary_agent_id"] as? String, "codex")
    XCTAssertEqual(definition["visibility_mode"] as? String, "BACKGROUND")
    XCTAssertEqual(members.first?["delivery_mode"] as? String, "RESPOND")
    XCTAssertNotNil(members.first?["depends_on_agent_ids"])
    XCTAssertNil(object["primaryAgentId"])
    XCTAssertNil(definition["primaryAgentId"])
  }

  func testAgentTeamPlanBridgeCompilesBranchedGraphIntoOneSupervisedTeamAction() throws {
    let research = teamActionWithAgentKnowledge(
      teamAgentAction("research", "researcher"),
      "research-only"
    )
    let review = teamAgentAction("review", "reviewer")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research", "review"],
      outputSources: ["research", "review"]
    )
    let synthesisWithKnowledge = teamActionWithAgentKnowledge(synthesis, "lead-only")

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, review, synthesisWithKnowledge),
      targets: teamTargets(),
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 1)
    let action = try XCTUnwrap(compiled.actions.first)
    XCTAssertTrue(action.id.hasPrefix("agent-team-"))
    XCTAssertTrue(Int64(action.parameters[agentTeamSourceParameter] ?? "0") ?? 0 > 0)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "lead")
    XCTAssertEqual(spec.definition.members.count, 3)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.deliveryMode, .respond)
    XCTAssertEqual(spec.definition.members.first { $0.agentId == "lead" }?.dependsOnAgentIds, Set(["researcher", "reviewer"]))
    XCTAssertTrue(spec.definition.members.filter { $0.agentId != "lead" }.allSatisfy { $0.deliveryMode == .observe })
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "researcher" }?.context["_signalasi_agent_knowledge_context"],
      "research-only"
    )
    XCTAssertEqual(
      spec.definition.members.first { $0.agentId == "lead" }?.context["_signalasi_agent_knowledge_context"],
      "lead-only"
    )
    XCTAssertTrue(compiled.validation.valid)
  }

  func testAgentTeamPlanBridgeRemapsDownstreamDependenciesAndRejectsUnsafeGraphs() {
    let research = teamAgentAction("research", "researcher")
    let synthesis = teamAgentAction(
      "synthesis",
      "lead",
      dependsOn: ["research"],
      outputSources: ["research"]
    )
    let downstream = teamConnectorAction(
      "publish",
      "cloud",
      kind: .model,
      dependsOn: ["synthesis"],
      outputSources: ["synthesis"]
    )
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(research, synthesis, downstream),
      targets: teamTargets() + [teamTarget("cloud", kind: .model)],
      enabled: true
    )

    XCTAssertEqual(compiled.actions.count, 2)
    let teamId = compiled.actions[0].id
    XCTAssertEqual(compiled.actions[1].parameters["depends_on"], teamId)
    XCTAssertEqual(compiled.actions[1].parameters["use_outputs_from"], teamId)
    XCTAssertTrue(compiled.validation.valid)

    let independent = teamBridgePlan(teamAgentAction("first", "researcher"), teamAgentAction("second", "lead"))
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: independent, targets: teamTargets(), enabled: true).actions,
      independent.actions
    )

    let external = teamBridgePlan(
      AgentAction(
        id: "phone-step",
        kind: .draftPlan,
        target: "phone",
        risk: .low,
        status: .pendingConfirmation,
        description: "Prepare phone evidence"
      ),
      teamAgentAction("research", "researcher", dependsOn: ["phone-step"]),
      teamAgentAction("synthesis", "lead", dependsOn: ["research"])
    )
    XCTAssertEqual(
      AgentTeamPlanCompiler.compile(plan: external, targets: teamTargets(), enabled: true).actions,
      external.actions
    )
  }

  func testAgentTeamPlanBridgeCompilesComplexSingleAgentPlanIntoDynamicTeam() throws {
    let original = teamBridgePlan(
      goal: "Implement and verify a Python API using current documentation",
      teamAgentAction("implement", "codex")
    )
    let targets = [
      AgentCallableTarget(
        id: "codex",
        title: "Codex - Development PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .code, .taskExecution],
        failureDomain: "desktop-development",
        adapterType: "codex-app-server"
      ),
      AgentCallableTarget(
        id: "hermes",
        title: "Hermes - Research PC",
        kind: .agent,
        status: .available,
        capabilities: [.chat, .reasoning, .research, .liveData, .knowledgeSearch],
        failureDomain: "desktop-research",
        adapterType: "hermes-cli"
      )
    ]
    let registrations = targets.map(teamRegistration)

    let compiled = AgentTeamPlanCompiler.compile(
      plan: original,
      targets: targets,
      enabled: true,
      registrations: registrations
    )

    let action = try XCTUnwrap(compiled.actions.first)
    let rawSpecObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data((action.parameters[agentTeamSpecParameter] ?? "").utf8)) as? [String: Any]
    )
    let rawMembers = try XCTUnwrap(rawSpecObject["members"] as? [[String: Any]])
    let codexContext = try XCTUnwrap(
      rawMembers.first { $0["agent_id"] as? String == "codex" }?["context"] as? [String: Any]
    )
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    XCTAssertEqual(spec.definition.primaryAgentId, "codex")
    XCTAssertEqual(Set(spec.definition.members.map(\.agentId)), Set(["codex", "hermes"]))
    XCTAssertEqual(spec.definition.collectiveCapabilities, Set([AgentCapability.code, AgentCapability.liveData, AgentCapability.knowledgeSearch]))
    XCTAssertEqual(codexContext["compiled_role"] as? String, "lead")
    XCTAssertTrue(compiled.validation.valid)

    let simple = teamBridgePlan(goal: "Hello", teamAgentAction("chat", "codex"))
    XCTAssertNil(AgentTeamPlanCompiler.compile(
      plan: simple,
      targets: targets,
      enabled: true,
      registrations: registrations
    ).actions.first?.parameters[agentTeamSpecParameter])
  }

  func testAgentTeamDispatchSpecRejectsMalformedAndRetryRekeysAttempt() throws {
    let valid = AgentTeamDispatchSpec(
      definition: AgentTeamDefinition(
        teamId: "team",
        primaryAgentId: "lead",
        members: [
          AgentTeamMember(
            agentId: "researcher",
            deliveryMode: .observe,
            requiredCapabilities: [],
            role: "research specialist",
            objective: "",
            dependsOnAgentIds: [],
            context: [:]
          ),
          AgentTeamMember(
            agentId: "lead",
            deliveryMode: .respond,
            requiredCapabilities: [],
            role: "lead synthesizer",
            objective: "",
            dependsOnAgentIds: ["researcher"],
            context: [:]
          )
        ],
        visibilityMode: .background,
        collectiveCapabilities: []
      ),
      supervisorRunId: "run"
    )
    let encoded = AgentTeamDispatchSpecCodec.encode(valid)
      .replacingOccurrences(of: "\"delivery_mode\":\"OBSERVE\"", with: "\"delivery_mode\":\"RESPOND\"")

    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(encoded))
    XCTAssertNil(AgentTeamDispatchSpecCodec.decode(#"{"version":1}"#))

    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let original = try XCTUnwrap(compiled.actions.first)
    let retry = AgentTeamPlanCompiler.rekeyAgentTeamForRetry(original)
    let originalSpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(original.parameters[agentTeamSpecParameter] ?? ""))
    let retrySpec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(retry.parameters[agentTeamSpecParameter] ?? ""))

    XCTAssertNotEqual(originalSpec.definition.teamId, retrySpec.definition.teamId)
    XCTAssertNotEqual(originalSpec.supervisorRunId, retrySpec.supervisorRunId)
    XCTAssertNotEqual(originalSpec.sourceMessageId, retrySpec.sourceMessageId)
    XCTAssertEqual(retry.parameters[agentTeamRunParameter], retrySpec.supervisorRunId)
    XCTAssertEqual(retry.parameters[agentTeamSourceParameter], String(retrySpec.sourceMessageId))
  }

  func testAgentTeamPlanBridgeModelsUseAndroidWireNames() throws {
    let compiled = AgentTeamPlanCompiler.compile(
      plan: teamBridgePlan(
        teamAgentAction("research", "researcher"),
        teamAgentAction("synthesis", "lead", dependsOn: ["research"])
      ),
      targets: teamTargets(),
      enabled: true
    )
    let action = try XCTUnwrap(compiled.actions.first)
    let spec = try XCTUnwrap(AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? ""))
    let specObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(AgentTeamDispatchSpecCodec.encode(spec).utf8)) as? [String: Any]
    )

    XCTAssertEqual(specObject["supervisor_run_id"] as? String, spec.supervisorRunId)
    XCTAssertEqual(specObject["team_id"] as? String, spec.definition.teamId)
    XCTAssertEqual(specObject["primary_agent_id"] as? String, "lead")
    XCTAssertEqual(specObject["visibility"] as? String, "BACKGROUND")
    XCTAssertNotNil(specObject["collective_capabilities"])
    XCTAssertEqual(action.parameters[agentTeamRunParameter], spec.supervisorRunId)
    XCTAssertEqual(action.parameters[agentTeamSourceParameter], String(spec.sourceMessageId))
    XCTAssertEqual(spec.responseContactId, "agent-team:\(spec.definition.teamId)")
    XCTAssertGreaterThanOrEqual(spec.sourceMessageId, Int64(1) << 62)
    XCTAssertNil(specObject["supervisorRunId"])
    XCTAssertNil(specObject["primaryAgentId"])
  }

}
