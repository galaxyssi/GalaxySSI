import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSDesktopRemoteNativeToolCatalogAndExecutorForwardsVerifiedDesktopCalls() throws {
    final class FakeDesktopRemoteProvider: AgentIOSDesktopRemoteToolProviding {
      var implementationId = "fake.ios.desktop_remote"
      var transportId = "galaxyssi-link-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var verificationStatus = "passed"
      var invokedKinds: [AgentIOSDesktopRemoteToolKind] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(kind: AgentIOSDesktopRemoteToolKind) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        kind: AgentIOSDesktopRemoteToolKind,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedKinds.append(kind)
        capturedInputs.append(input)
        return AgentNativeToolExecutionResult.success(
          output: output(kind: kind, input: input),
          message: "Desktop \(kind.rawValue) completed",
          metadata: [
            "desktop_id": .string(input["desktop_id"]?.stringValue ?? "desktop-1"),
            "remote_verification_status": .string(verificationStatus),
            "remote_verification_evidence": .object([
              "tool_id": .string(invocation.descriptor.id),
              "observed": .bool(true)
            ])
          ]
        )
      }

      private func output(kind: AgentIOSDesktopRemoteToolKind, input: AgentMcpJSONObject) -> AgentMcpJSONObject {
        switch kind {
        case .systemStatus:
          return ["os": .string("Windows"), "memory_used_bytes": .int(1_024)]
        case .processList:
          return ["processes": .array([.object(["pid": .int(7), "name": .string("GalaxySSI.exe")])])]
        case .fileReadText:
          return [
            "path": input["path"] ?? .string("notes/readme.txt"),
            "text": .string("desktop text"),
            "size_bytes": .int(12)
          ]
        case .terminalRun:
          return [
            "argv": input["argv"] ?? .array([]),
            "exit_code": .int(0),
            "stdout": .string("ok"),
            "stderr": .string("")
          ]
        case .fileList, .fileWriteText, .fileSha256, .archiveCreate, .officeInspect, .officeConvert:
          return ["kind": .string(kind.rawValue)]
        }
      }
    }

    let provider = FakeDesktopRemoteProvider()
    let definitions = AgentIOSDesktopRemoteNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: provider)
    )
    let linkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSDesktopRemoteNativeToolCatalog.linkPermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "desktop-terminal-1",
      idempotencyKey: "desktop-key-1",
      grantedPermissions: [
        AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
        AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
      ],
      grantedConsents: [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent],
      attributes: ["workspace_id": "desktop-workspace-1"]
    )

    XCTAssertEqual(Set(AgentIOSDesktopRemoteNativeToolCatalog.orderedToolIds), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map { $0.descriptor.version }), [AgentIOSDesktopRemoteNativeToolCatalog.version])
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSDesktopRemoteNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .desktop)
      XCTAssertFalse(definition.descriptor.capabilities.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["transport"], "galaxyssi-link-v1")
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentDesktopRemoteNativeTools")
    }
    let terminalDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.terminalRun })
    let writeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText })
    let readDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSDesktopRemoteNativeToolCatalog.fileReadText })
    XCTAssertEqual(terminalDescriptor.descriptor.risk, .high)
    XCTAssertEqual(terminalDescriptor.descriptor.timeoutMillis, 185_000)
    XCTAssertEqual(terminalDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSDesktopRemoteNativeToolCatalog.executeConsent])
    XCTAssertEqual(terminalDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(writeDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(readDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertTrue(AgentIOSDesktopRemoteNativeToolCatalog.alwaysConfirmToolIds.contains(AgentIOSDesktopRemoteNativeToolCatalog.terminalRun))

    let missingWorkspace = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ]
      )
    )
    let read = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileReadText,
      input: [
        "desktop_id": .string("desktop-1"),
        "path": .string("notes/readme.txt")
      ],
      context: workspaceContext
    )
    let deniedTerminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: AgentNativeToolInvocationContext(
        idempotencyKey: "desktop-key-2",
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let missingWriteKey = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.fileWriteText,
      input: [
        "path": .string("notes/readme.txt"),
        "content": .string("updated"),
        "mode": .string("overwrite")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSDesktopRemoteNativeToolCatalog.linkPermission,
          AgentIOSDesktopRemoteNativeToolCatalog.workspacePermission
        ],
        attributes: ["workspace_id": "desktop-workspace-1"]
      )
    )
    let terminal = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.terminalRun,
      input: ["argv": .array([.string("python"), .string("--version")])],
      context: workspaceContext
    )
    provider.verificationStatus = "failed"
    let verificationFailed = registry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.processList,
      input: ["query": .string("GalaxySSI")],
      context: linkContext
    )
    let unavailableProvider = FakeDesktopRemoteProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Waiting for Desktop manifest"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.desktopRemoteExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSDesktopRemoteNativeToolCatalog.systemStatus,
      input: [:],
      context: linkContext
    )

    XCTAssertEqual(missingWorkspace.status, .failed)
    XCTAssertEqual(missingWorkspace.error?.code, "desktop_workspace_unavailable")
    XCTAssertTrue(read.isSuccess)
    XCTAssertEqual(read.output["desktop_id"], .string("desktop-1"))
    XCTAssertEqual(read.output["workspace_id"], .string("desktop-workspace-1"))
    XCTAssertEqual(read.output["remote_artifacts"], .array([]))
    XCTAssertEqual(read.verification?.status, .passed)
    XCTAssertEqual(deniedTerminal.status, .rejected)
    XCTAssertEqual(deniedTerminal.error?.code, "missing_consents")
    XCTAssertEqual(missingWriteKey.status, .rejected)
    XCTAssertEqual(missingWriteKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(terminal.isSuccess)
    XCTAssertEqual(terminal.output["remote_forwarded"], .bool(true))
    XCTAssertEqual(terminal.metadata["transport"], .string("galaxyssi-link-v1"))
    XCTAssertEqual(verificationFailed.status, .verificationFailed)
    XCTAssertEqual(verificationFailed.error?.code, "verification_failed")
    XCTAssertEqual(provider.invokedKinds, [.fileReadText, .terminalRun, .processList])
    XCTAssertEqual(provider.capturedInputs.first?["path"], .string("notes/readme.txt"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedKinds.isEmpty)
  }

}
