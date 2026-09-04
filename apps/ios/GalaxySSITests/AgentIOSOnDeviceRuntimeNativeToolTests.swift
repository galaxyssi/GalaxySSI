import CryptoKit
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentIOSOnDeviceRuntimeNativeToolCatalogAndExecutorMirrorsAndroidRuntimeTools() throws {
    final class FakeRuntimeProvider: AgentIOSOnDeviceRuntimeToolProviding {
      var implementationId = "fake.ios.runtime"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSOnDeviceRuntimeToolOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "backend": .string("ios_local"),
              "backend_ready": .bool(true),
              "reason": .string("ready"),
              "packs": .array([packValue("linux-base", state: "ready")]),
              "languages": .array([
                .object(["id": .string("python"), "ready": .bool(true)])
              ])
            ],
            message: "On-device runtime inspected"
          )
        case .workspaceStatus:
          return AgentNativeToolExecutionResult.success(
            output: [
              "workspace_file_count": .int(3),
              "workspace_bytes": .int(1_024),
              "checkpoints": .array([.object(["checkpoint_id": .string("cp-1")])])
            ],
            message: "On-device project workspace inspected"
          )
        case .workspaceRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "checkpoint_id": input["checkpoint_id"] ?? .string("cp-1"),
              "workspace_file_count": .int(2),
              "workspace_bytes": .int(512),
              "workspace_disposition": .string("rolled_back")
            ],
            message: "On-device project checkpoint restored"
          )
        case .listPacks:
          return AgentNativeToolExecutionResult.success(
            output: ["packs": .array([packValue("linux-base", state: "ready"), packValue("python-uv", state: "ready")])],
            message: "On-device runtime packs listed"
          )
        case .installPack:
          return AgentNativeToolExecutionResult.success(
            output: [
              "requested_pack": input["pack_id"] ?? .string("python-uv"),
              "installed": .array([
                .object(["pack_id": .string("python-uv"), "version": .string("1.0.0"), "state": .string("ready")])
              ])
            ],
            message: "Trusted runtime pack is ready"
          )
        case .softwareCatalog:
          return AgentNativeToolExecutionResult.success(
            output: [
              "architecture": .string("arm64"),
              "linux_ready": .bool(false),
              "sources": .array([.object(["id": .string("runtime_pack")])]),
              "software": .array([softwareValue("linux-base", state: "ready")])
            ],
            message: "Compatible iOS runtime software listed"
          )
        case .softwareSearch:
          return AgentNativeToolExecutionResult.success(
            output: [
              "query": input["query"] ?? .string("python"),
              "results": .array([softwareValue("python-uv", state: "ready")]),
              "source_errors": .array([])
            ],
            message: "Compatible iOS runtime software searched"
          )
        case .softwareInspect:
          return AgentNativeToolExecutionResult.success(
            output: softwareValue(input["software_id"]?.stringValue ?? "python-uv", state: "ready").objectValue ?? [:],
            message: "Compatible iOS runtime software inspected"
          )
        case .softwareInstall:
          return AgentNativeToolExecutionResult.success(
            output: [
              "software_id": input["software_id"] ?? .string("python-uv"),
              "source": .string("runtime_pack"),
              "installed": .array([.object(["pack_id": .string("python-uv"), "state": .string("ready")])])
            ],
            message: "Compatible iOS runtime software installed and verified"
          )
        case .softwareRemove:
          return AgentNativeToolExecutionResult.failure(
            code: "ios_linux_package_management_unavailable",
            message: "Unmanaged Linux package removal is unavailable on iOS"
          )
        case .execute:
          return AgentNativeToolExecutionResult.success(
            output: [
              "exit_code": .int(0),
              "stdout": .string("ok"),
              "stderr": .string(""),
              "duration_ms": .int(25),
              "workspace_file_count": .int(4),
              "workspace_bytes": .int(2_048),
              "checkpoint_id": .string("cp-2"),
              "execution_receipt": .object(["request_id": .string(invocation.context.invocationId)])
            ],
            message: "On-device runtime completed"
          )
        }
      }

      private func packValue(_ id: String, state: String) -> AgentMcpJSONValue {
        .object([
          "id": .string(id),
          "state": .string(state),
          "reason": .string(""),
          "version": .string("1.0.0"),
          "architecture": .string("arm64"),
          "capabilities": .array([.string("shell.execute")]),
          "installed_size_bytes": .int(2_048),
          "license": .string("Apache-2.0")
        ])
      }

      private func softwareValue(_ id: String, state: String) -> AgentMcpJSONValue {
        .object([
          "software_id": .string(id),
          "source": .string("runtime_pack"),
          "version": .string("1.0.0"),
          "installed": .bool(state == "ready"),
          "compatible": .bool(true),
          "state": .string(state),
          "capabilities": .array([.string("shell.execute")])
        ])
      }
    }

    let provider = FakeRuntimeProvider()
    let definitions = AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: provider)
    )
    let runtimeContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "runtime-execute-1",
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission
      ],
      attributes: ["workspace_id": "runtime-workspace-1"]
    )
    let packContext = AgentNativeToolInvocationContext(
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.packInstallPermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstallPermission
      ]
    )

    XCTAssertEqual(Set(AgentIOSOnDeviceRuntimeNativeToolCatalog.orderedToolIds), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds.contains("galaxyssi.runtime.workspace.status"))
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.requiredPacks.contains("python-uv"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("runtime.ios_local"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertEqual(definition.descriptor.requiredConsents.first?.required, false)
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentOnDeviceRuntimeTools")
      XCTAssertEqual(definition.provenanceMetadata["platform"], "ios")
    }
    let installDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack })
    let executeDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute })
    let statusDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.status })
    let softwareInstallDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall })
    XCTAssertEqual(statusDescriptor.descriptor.risk, .low)
    XCTAssertEqual(installDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.packManagerExecutorId)
    XCTAssertEqual(installDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(softwareInstallDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    XCTAssertEqual(
      softwareInstallDescriptor.descriptor.requiredPermissions.map(\.id),
      [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstallPermission
      ]
    )
    XCTAssertEqual(executeDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    XCTAssertEqual(executeDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(executeDescriptor.descriptor.timeoutMillis, 30 * 60_000)

    let status = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], context: runtimeContext)
    let packs = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks, input: [:], context: runtimeContext)
    let softwareCatalog = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareCatalog, input: [:], context: runtimeContext)
    let softwareSearch = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSearch,
      input: ["query": .string("python")],
      context: runtimeContext
    )
    let softwareInspect = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInspect,
      input: ["software_id": .string("python-uv")],
      context: runtimeContext
    )
    let workspace = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceStatus, input: [:], context: workspaceContext)
    let deniedInstall = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: runtimeContext
    )
    let install = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.installPack,
      input: ["pack_id": .string("python-uv")],
      context: packContext
    )
    let deniedSoftwareInstall = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall,
      input: ["software_id": .string("python-uv")],
      context: runtimeContext
    )
    let softwareInstall = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInstall,
      input: ["software_id": .string("python-uv")],
      context: packContext
    )
    let softwareRemove = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareRemove,
      input: ["software_id": .string("python-uv")],
      context: runtimeContext
    )
    let rollback = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback,
      input: ["checkpoint_id": .string("cp-1")],
      context: workspaceContext
    )
    let invalidExecute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("swift"),
        "source": .string("print(\"no\")")
      ],
      context: workspaceContext
    )
    let execute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')"),
        "timeout_ms": .int(1_000),
        "artifact_paths": .array([.string("out/result.txt")])
      ],
      context: workspaceContext
    )
    let unavailableProvider = FakeRuntimeProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install runtime backend"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("python"),
        "source": .string("print('ok')")
      ],
      context: workspaceContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["backend"], .string("ios_local"))
    XCTAssertTrue(packs.isSuccess)
    if case .array(let packValues)? = packs.output["packs"] {
      XCTAssertEqual(packValues.count, 2)
    } else {
      XCTFail("Expected runtime packs array")
    }
    XCTAssertTrue(softwareCatalog.isSuccess)
    XCTAssertEqual(softwareCatalog.output["linux_ready"], .bool(false))
    XCTAssertTrue(softwareSearch.isSuccess)
    XCTAssertEqual(softwareSearch.output["query"], .string("python"))
    XCTAssertTrue(softwareInspect.isSuccess)
    XCTAssertEqual(softwareInspect.output["software_id"], .string("python-uv"))
    XCTAssertTrue(workspace.isSuccess)
    XCTAssertEqual(workspace.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(deniedInstall.status, .rejected)
    XCTAssertEqual(deniedInstall.error?.code, "missing_permissions")
    XCTAssertTrue(install.isSuccess)
    XCTAssertEqual(install.output["requested_pack"], .string("python-uv"))
    XCTAssertEqual(deniedSoftwareInstall.status, .rejected)
    XCTAssertEqual(deniedSoftwareInstall.error?.code, "missing_permissions")
    XCTAssertTrue(softwareInstall.isSuccess)
    XCTAssertEqual(softwareInstall.output["software_id"], .string("python-uv"))
    XCTAssertEqual(softwareRemove.status, .failed)
    XCTAssertEqual(softwareRemove.error?.code, "ios_linux_package_management_unavailable")
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["workspace_disposition"], .string("rolled_back"))
    XCTAssertEqual(invalidExecute.status, .rejected)
    XCTAssertEqual(invalidExecute.error?.code, "invalid_input")
    XCTAssertTrue(execute.isSuccess)
    XCTAssertEqual(execute.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(execute.output["workspace_disposition"], .string("preserved"))
    XCTAssertEqual(execute.output["artifacts"], .array([]))
    XCTAssertEqual(execute.metadata["network_default"], .string("disabled"))
    XCTAssertEqual(
      provider.invokedOperations,
      [
        .status, .listPacks, .softwareCatalog, .softwareSearch, .softwareInspect,
        .workspaceStatus, .installPack, .softwareInstall, .softwareRemove,
        .workspaceRollback, .execute
      ]
    )
    XCTAssertEqual(provider.capturedInputs.last?["language"], .string("python"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

  func testAgentIOSDefaultOnDeviceRuntimeProviderReportsPacksWorkspaceAndSetupBoundary() throws {
    let root = try temporaryDirectory("ios-default-runtime-provider")
    defer { try? FileManager.default.removeItem(at: root) }
    let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
    let projectsRoot = root.appendingPathComponent("projects", isDirectory: true)
    let workspaceManager = AgentRuntimeProjectWorkspaceManager(
      runtimeRoot: runtimeRoot.appendingPathComponent("runs", isDirectory: true),
      projectRoot: projectsRoot,
      nowMillis: { 44_000 }
    )
    try installRuntimePackManifest("linux-base", under: runtimeRoot)
    let project = projectsRoot.appendingPathComponent("runtime-workspace-2", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("stable".utf8).write(to: project.appendingPathComponent("README.md"))
    _ = try workspaceManager.checkpoint(
      workspaceId: "runtime-workspace-2",
      checkpointId: "stable-snapshot",
      byteLimit: 8 * 1_024 * 1_024
    )
    try Data("changed".utf8).write(to: project.appendingPathComponent("README.md"))

    let provider = AgentIOSDefaultOnDeviceRuntimeProvider(
      runtimeRootURL: runtimeRoot,
      workspaceManager: workspaceManager,
      nowMillis: { 55_000 },
      signatureVerifier: { _ in true }
    )
    let definitions = AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: provider)
    )
    let runtimeContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission]
    )
    let workspaceContext = AgentNativeToolInvocationContext(
      invocationId: "ios-runtime-workspace",
      grantedPermissions: [
        AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission,
        AgentIOSOnDeviceRuntimeNativeToolCatalog.workspacePermission
      ],
      attributes: ["workspace_id": "runtime-workspace-2"]
    )

    let statusDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.status })
    let executeDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute })
    let softwareRemoveDefinition = try XCTUnwrap(definitions.first { $0.id == AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareRemove })
    let status = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], context: runtimeContext)
    let packs = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks, input: [:], context: runtimeContext)
    let softwareCatalog = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareCatalog, input: [:], context: runtimeContext)
    let softwareSearch = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareSearch,
      input: ["query": .string("shell")],
      context: runtimeContext
    )
    let softwareInspect = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInspect,
      input: ["software_id": .string("linux-base")],
      context: runtimeContext
    )
    let softwareRemove = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareRemove,
      input: ["software_id": .string("linux-base")],
      context: runtimeContext
    )
    let unavailableLinuxPackage = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.softwareInspect,
      input: ["software_id": .string("git")],
      context: runtimeContext
    )
    let workspace = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceStatus, input: [:], context: workspaceContext)
    let execute = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
      input: [
        "language": .string("shell"),
        "source": .string("echo ready")
      ],
      context: workspaceContext
    )
    let rollback = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.workspaceRollback,
      input: ["checkpoint_id": .string("stable-snapshot")],
      context: workspaceContext
    )

    XCTAssertEqual(provider.implementationId, "galaxyssi.ios.default_runtime_status")
    XCTAssertEqual(statusDefinition.descriptor.availability.status, .available)
    XCTAssertEqual(executeDefinition.descriptor.availability.status, .requiresSetup)
    XCTAssertEqual(softwareRemoveDefinition.descriptor.availability.status, .requiresSetup)
    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["backend"], .string("none"))
    XCTAssertEqual(status.output["backend_ready"], .bool(false))
    XCTAssertEqual(status.output["observed_at_epoch_ms"], .int(55_000))
    XCTAssertEqual(status.metadata["implementation"], .string("galaxyssi.ios.default_runtime_status"))
    let linuxSystem = try XCTUnwrap(status.output["linux_system"]?.objectValue)
    XCTAssertEqual(linuxSystem["distribution"], .string("paired jailbreak Linux runtime"))
    XCTAssertEqual(linuxSystem["execution_principal"], .string("configured_jailbreak_linux_prefix"))
    XCTAssertEqual(linuxSystem["persistent"], .bool(true))
    XCTAssertEqual(linuxSystem["package_manager_ready"], .bool(false))
    XCTAssertEqual(linuxSystem["base_version"], .string(""))
    XCTAssertEqual(linuxSystem["package_management"], .string("runtime_broker_managed"))
    let statusPacks = try XCTUnwrap(status.output["packs"]?.arrayValue?.compactMap(\.objectValue))
    let linuxBase = try XCTUnwrap(statusPacks.first { $0["id"] == .string("linux-base") })
    let python = try XCTUnwrap(statusPacks.first { $0["id"] == .string("python-uv") })
    XCTAssertEqual(linuxBase["state"], .string("ready"))
    XCTAssertEqual(python["state"], .string("not_installed"))
    let shellLanguage = try XCTUnwrap(
      status.output["languages"]?.arrayValue?
        .compactMap(\.objectValue)
        .first { $0["id"] == .string("shell") }
    )
    XCTAssertEqual(shellLanguage["pack_ready"], .bool(true))
    XCTAssertEqual(shellLanguage["ready"], .bool(false))
    XCTAssertTrue(packs.isSuccess)
    XCTAssertEqual(try XCTUnwrap(packs.output["packs"]?.arrayValue).count, AgentRuntimePackCatalogPolicy.requiredPacks.count)
    XCTAssertTrue(softwareCatalog.isSuccess)
    XCTAssertEqual(softwareCatalog.output["linux_ready"], .bool(false))
    XCTAssertTrue(softwareSearch.isSuccess)
    XCTAssertEqual(softwareSearch.output["query"], .string("shell"))
    XCTAssertEqual(
      try XCTUnwrap(softwareSearch.output["results"]?.arrayValue?.first?.objectValue?["software_id"]),
      .string("linux-base")
    )
    XCTAssertTrue(softwareInspect.isSuccess)
    XCTAssertEqual(softwareInspect.output["software_id"], .string("linux-base"))
    XCTAssertEqual(unavailableLinuxPackage.status, .failed)
    XCTAssertEqual(unavailableLinuxPackage.error?.code, "ios_linux_package_management_unavailable")
    XCTAssertEqual(softwareRemove.status, .unavailable)
    XCTAssertEqual(softwareRemove.error?.code, "tool_unavailable")
    XCTAssertTrue(workspace.isSuccess)
    XCTAssertEqual(workspace.output["workspace_id"], .string("runtime-workspace-2"))
    XCTAssertEqual(try XCTUnwrap(workspace.output["checkpoints"]?.arrayValue).count, 1)
    XCTAssertEqual(execute.status, .unavailable)
    XCTAssertEqual(execute.error?.code, "tool_unavailable")
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["workspace_disposition"], .string("rolled_back"))
    XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("README.md")), "stable")
  }

  func testDefaultRuntimeProviderUsesPairedBrokerWithoutSyntheticPacks() throws {
    struct ReadyBroker: AgentIOSRuntimeBrokerProviding {
      var implementationId: String { "ready-runtime-broker" }

      func availability() -> AgentNativeToolAvailability { .available }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        context: AgentNativeToolInvocationContext,
        deadlineEpochMillis: Int64
      ) throws -> AgentMcpJSONObject {
        ["backend_ready": .bool(true)]
      }
    }

    let root = try temporaryDirectory("ios-default-runtime-base-readiness")
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = AgentIOSDefaultOnDeviceRuntimeProvider(
      runtimeRootURL: root,
      broker: ReadyBroker(),
      signatureVerifier: { _ in true }
    )

    XCTAssertEqual(provider.availability(operation: .execute).status, .available)
  }

  func testDefaultRuntimeProviderUsesCachedLifecycleForStatusWithoutBrokerProbe() throws {
    final class ProbeCountingBroker: AgentIOSRuntimeBrokerProviding {
      var implementationId: String { "probe-counting-runtime-broker" }
      private(set) var invokedOperations: [AgentIOSOnDeviceRuntimeToolOperation] = []

      func availability() -> AgentNativeToolAvailability { .available }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        context: AgentNativeToolInvocationContext,
        deadlineEpochMillis: Int64
      ) throws -> AgentMcpJSONObject {
        invokedOperations.append(operation)
        return ["backend_ready": .bool(true)]
      }
    }

    let root = try temporaryDirectory("ios-runtime-cached-status")
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "AgentIOSRuntimeCachedStatusTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let lifecycle = AgentIOSRuntimeBrokerLifecycleStore(defaults: defaults, nowMillis: { 90_000 })
    _ = lifecycle.ready()
    let broker = ProbeCountingBroker()
    let provider = AgentIOSDefaultOnDeviceRuntimeProvider(
      runtimeRootURL: root,
      nowMillis: { 91_000 },
      broker: broker,
      lifecycleStore: lifecycle,
      signatureVerifier: { _ in true }
    )
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: provider)
    )
    let result = registry.invoke(
      AgentIOSOnDeviceRuntimeNativeToolCatalog.status,
      input: [:],
      context: AgentNativeToolInvocationContext(
        invocationId: "cached-runtime-status",
        grantedPermissions: [AgentIOSOnDeviceRuntimeNativeToolCatalog.runtimePermission]
      )
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["backend"], .string("ios_runtime_broker"))
    XCTAssertEqual(result.output["backend_ready"], .bool(true))
    XCTAssertEqual(result.output["status_source"], .string("cached_lifecycle"))
    XCTAssertEqual(result.metadata["status_source"], .string("cached_lifecycle"))
    XCTAssertTrue(broker.invokedOperations.isEmpty)
  }

  func testDefaultRuntimeProviderRejectsAnOutdatedLinuxBrokerBeforeExecution() throws {
    struct OutdatedBroker: AgentIOSRuntimeBrokerProviding {
      var implementationId: String { "outdated-runtime-broker" }

      func availability() -> AgentNativeToolAvailability { .available }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        context: AgentNativeToolInvocationContext,
        deadlineEpochMillis: Int64
      ) throws -> AgentMcpJSONObject {
        switch operation {
        case .status:
          return [
            "backend_ready": .bool(true),
            "linux_base_version": .string("1.3.8")
          ]
        default:
          XCTFail("Outdated broker must not receive \(operation.rawValue)")
          return [:]
        }
      }
    }

    let root = try temporaryDirectory("ios-default-runtime-outdated-broker")
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = AgentIOSDefaultOnDeviceRuntimeProvider(
      runtimeRootURL: root,
      broker: OutdatedBroker(),
      signatureVerifier: { _ in true }
    )
    let result = provider.invoke(
      operation: .execute,
      input: ["command": .string("echo should-not-run")],
      invocation: AgentNativeToolInvocation(
        descriptor: try AgentNativeToolDescriptor(
          id: "ios.runtime.execute",
          version: "1.0.0",
          title: "Execute runtime command",
          description: "Executes a Linux command through the paired runtime broker.",
          location: .phone,
          risk: .high
        ),
        input: [:],
        context: AgentNativeToolInvocationContext(invocationId: "outdated-linux-broker"),
        startedAtEpochMillis: 0,
        deadlineEpochMillis: 100,
        nowMillis: { 0 },
        cancellationRequested: { false },
        progressReporter: { _, _ in }
      )
    )

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.error?.code, "runtime_broker_linux_base_incompatible")
    XCTAssertEqual(result.error?.message, "Linux 1.3.9 or later is required (broker reports 1.3.8).")
  }

  func testAgentIOSRuntimeBrokerClientSignsLoopbackStatusRequests() throws {
    final class StubTransport: AgentIOSRuntimeBrokerTransport {
      var capturedFrame = Data()
      var capturedHost = ""
      var capturedPort: UInt16 = 0
      var response = Data()

      func exchange(frame: Data, host: String, port: UInt16, timeoutMillis: Int64) throws -> Data {
        capturedFrame = frame
        capturedHost = host
        capturedPort = port
        return response
      }
    }

    let suite = "AgentIOSRuntimeBrokerClientTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let configurationStore = AgentIOSRuntimeBrokerConfigurationStore(defaults: defaults)
    try configurationStore.save(AgentIOSRuntimeBrokerConfiguration(
      enabled: true,
      host: AgentIOSRuntimeBrokerConfiguration.defaultHost,
      port: AgentIOSRuntimeBrokerConfiguration.defaultPort
    ))
    let secretStore = InMemorySecretStore()
    let key = Data(repeating: 7, count: 32)
    try secretStore.setString(key.base64EncodedString(), account: AgentIOSRuntimeBrokerCredentials.sessionKeyAccount)
    let transport = StubTransport()
    let now: Int64 = 88_000
    var response: AgentMcpJSONObject = [
      "protocol_version": .int(AgentIOSRuntimeBrokerClient.protocolVersion),
      "timestamp_epoch_ms": .int(now),
      "ok": .bool(true),
      "result": .object([
        "backend": .string("ios_runtime_broker"),
        "backend_ready": .bool(true)
      ])
    ]
    let responseKey = SymmetricKey(data: key)
    let responsePayload = Data(AgentMcpJSONCodec.stringify(response).utf8)
    response["mac"] = .string(
      Data(HMAC<SHA256>.authenticationCode(for: responsePayload, using: responseKey)).base64EncodedString()
    )
    transport.response = try JSONEncoder().encode(response)
    let client = AgentIOSRuntimeBrokerClient(
      configurationStore: configurationStore,
      credentials: AgentIOSRuntimeBrokerCredentials(secretStore: secretStore),
      transport: transport,
      nowMillis: { now },
      requestId: { "broker-request-1" }
    )

    let result = try client.invoke(
      operation: .status,
      input: [:],
      context: AgentNativeToolInvocationContext(
        invocationId: "invoke-1",
        conversationId: "conversation-1",
        turnId: "turn-1"
      ),
      deadlineEpochMillis: now + 15_000
    )

    XCTAssertEqual(client.availability().status, .available)
    XCTAssertEqual(result["backend"], .string("ios_runtime_broker"))
    XCTAssertEqual(transport.capturedHost, AgentIOSRuntimeBrokerConfiguration.defaultHost)
    XCTAssertEqual(transport.capturedPort, UInt16(AgentIOSRuntimeBrokerConfiguration.defaultPort))
    let request = try JSONDecoder().decode(AgentMcpJSONObject.self, from: transport.capturedFrame)
    XCTAssertEqual(request["operation"], .string(AgentIOSOnDeviceRuntimeToolOperation.status.rawValue))
    XCTAssertEqual(request["request_id"], .string("broker-request-1"))
    XCTAssertNotNil(request["mac"]?.stringValue)
    XCTAssertEqual(request["context"]?.objectValue?["workspace_id"], .string("conversation-1"))
  }

  func testRuntimeBrokerHealthRequiresAReadyStatusHandshake() throws {
    struct StubBroker: AgentIOSRuntimeBrokerProviding {
      let availabilityValue: AgentNativeToolAvailability
      let result: Result<AgentMcpJSONObject, Error>

      var implementationId: String { "stub-runtime-broker" }

      func availability() -> AgentNativeToolAvailability {
        availabilityValue
      }

      func invoke(
        operation: AgentIOSOnDeviceRuntimeToolOperation,
        input: AgentMcpJSONObject,
        context: AgentNativeToolInvocationContext,
        deadlineEpochMillis: Int64
      ) throws -> AgentMcpJSONObject {
        try result.get()
      }
    }

    let context = AgentNativeToolInvocationContext(invocationId: "runtime-health")
    let unconfigured = AgentIOSRuntimeBrokerHealthChecker.check(
      broker: StubBroker(
        availabilityValue: AgentNativeToolAvailability(status: .requiresSetup, reason: "Pair the broker"),
        result: .success(["backend_ready": .bool(true)])
      ),
      deadlineEpochMillis: 100,
      context: context
    )
    let unavailable = AgentIOSRuntimeBrokerHealthChecker.check(
      broker: StubBroker(
        availabilityValue: .available,
        result: .success(["backend_ready": .bool(false), "reason": .string("Guest stopped")])
      ),
      deadlineEpochMillis: 100,
      context: context
    )
    let ready = AgentIOSRuntimeBrokerHealthChecker.check(
      broker: StubBroker(
        availabilityValue: .available,
        result: .success([
          "backend_ready": .bool(true),
          "reason": .string("Guest ready"),
          "linux_base_version": .string("1.3.9")
        ])
      ),
      deadlineEpochMillis: 100,
      context: context
    )

    XCTAssertEqual(unconfigured, .notConfigured("Pair the broker"))
    XCTAssertEqual(unavailable, .unavailable("Guest stopped"))
    XCTAssertEqual(ready, .ready("Guest ready"))

    let outdated = AgentIOSRuntimeBrokerHealthChecker.check(
      broker: StubBroker(
        availabilityValue: .available,
        result: .success([
          "backend_ready": .bool(true),
          "linux_system": .object(["base_version": .string("1.3.8")])
        ])
      ),
      deadlineEpochMillis: 100,
      context: context
    )
    let missingVersion = AgentIOSRuntimeBrokerHealthChecker.check(
      broker: StubBroker(
        availabilityValue: .available,
        result: .success(["backend_ready": .bool(true)])
      ),
      deadlineEpochMillis: 100,
      context: context
    )

    XCTAssertEqual(outdated, .unavailable("Linux 1.3.9 or later is required (broker reports 1.3.8)."))
    XCTAssertEqual(missingVersion, .unavailable("The local Linux runtime broker did not report its Linux base version."))
  }

  func testRuntimeBrokerLifecycleBacksOffThenRecovers() throws {
    let suite = "AgentIOSRuntimeBrokerLifecycleTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var now: Int64 = 10_000
    let store = AgentIOSRuntimeBrokerLifecycleStore(defaults: defaults, nowMillis: { now })

    let firstFailure = store.failed(reason: "Broker unavailable")
    XCTAssertEqual(firstFailure.phase, "backing_off")
    XCTAssertEqual(firstFailure.consecutiveFailures, 1)
    XCTAssertEqual(firstFailure.nextAttemptAtMillis, 11_000)

    now = 11_000
    let secondFailure = store.failed(reason: "Broker unavailable")
    XCTAssertEqual(secondFailure.consecutiveFailures, 2)
    XCTAssertEqual(secondFailure.nextAttemptAtMillis, 13_000)

    now = 14_000
    let ready = store.ready()
    XCTAssertEqual(ready.phase, "ready")
    XCTAssertEqual(ready.consecutiveFailures, 0)
    XCTAssertEqual(ready.lastReadyAtMillis, 14_000)
    XCTAssertEqual(store.snapshot(), ready)
  }

  func testEmbeddedDebianSoftwareScriptsAndRecordsMirrorAndroidPackageContract() throws {
    let searchInput = try AgentIOSQemuLinuxSoftware.executionInput(
      operation: .softwareSearch,
      input: ["query": .string("git's client"), "limit": .int(99)]
    )
    let searchScript = try XCTUnwrap(searchInput["source"]?.stringValue)
    XCTAssertTrue(searchScript.contains("apt-cache search --names-only"))
    XCTAssertTrue(searchScript.contains("head -n 50"))
    XCTAssertTrue(searchScript.contains("'git'\"'\"'s client'"))
    XCTAssertEqual(searchInput["network_enabled"], .bool(true))

    let searchResult = try AgentIOSQemuLinuxSoftware.result(
      operation: .softwareSearch,
      input: ["query": .string("git")],
      guestResult: [
        "exit_code": .int(0),
        "stdout": .string("git\\t1:2.47.1-1\\tinstalled\\tfast, scalable revision control system\\ninvalid id\\t1\\tinstalled\\tignored"),
        "stderr": .string("")
      ]
    )
    let records = try XCTUnwrap(searchResult["results"]?.arrayValue)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.objectValue?["software_id"], .string("git"))
    XCTAssertEqual(records.first?.objectValue?["source"], .string("linux_package"))
    XCTAssertEqual(records.first?.objectValue?["installed"], .bool(true))

    XCTAssertThrowsError(
      try AgentIOSQemuLinuxSoftware.executionInput(
        operation: .softwareInstall,
        input: ["software_id": .string("git; rm -rf /")]
      )
    )
  }

  private func installRuntimePackManifest(_ packId: String, under runtimeRoot: URL) throws {
    let image = Data("\(packId)-runtime-image".utf8)
    let manifest = AgentRuntimePackManifest(
      id: packId,
      version: packId == "linux-base" ? "1.3.9" : "1.0.0",
      architecture: AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first ?? "arm64",
      imageFile: "\(packId).img",
      imageSha256: SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined(),
      capabilities: Array(AgentRuntimePackCatalogPolicy.requiredPackCapabilities[packId] ?? []).sorted(),
      dependencies: [],
      installedSizeBytes: 4_096,
      license: "Apache-2.0",
      signatureKeyId: String(repeating: "b", count: 64),
      signature: "test-signature",
      archiveSizeBytes: 1
    )
    let packRoot = runtimeRoot
      .appendingPathComponent("packs", isDirectory: true)
      .appendingPathComponent(packId, isDirectory: true)
    try FileManager.default.createDirectory(at: packRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(manifest)
      .write(to: packRoot.appendingPathComponent("manifest.json"), options: [.atomic])
    try image.write(to: packRoot.appendingPathComponent(manifest.imageFile), options: [.atomic])
  }

}
