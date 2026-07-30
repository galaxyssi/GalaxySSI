import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
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
        AgentIOSOnDeviceRuntimeNativeToolCatalog.packInstallPermission
      ]
    )

    XCTAssertEqual(Set(AgentIOSOnDeviceRuntimeNativeToolCatalog.orderedToolIds), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds.contains("signalasi.runtime.workspace.status"))
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
    XCTAssertEqual(statusDescriptor.descriptor.risk, .low)
    XCTAssertEqual(installDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.packManagerExecutorId)
    XCTAssertEqual(installDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(executeDescriptor.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    XCTAssertEqual(executeDescriptor.descriptor.risk, .medium)
    XCTAssertEqual(executeDescriptor.descriptor.timeoutMillis, 30 * 60_000)

    let status = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], context: runtimeContext)
    let packs = registry.invoke(AgentIOSOnDeviceRuntimeNativeToolCatalog.listPacks, input: [:], context: runtimeContext)
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
    XCTAssertTrue(workspace.isSuccess)
    XCTAssertEqual(workspace.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(deniedInstall.status, .rejected)
    XCTAssertEqual(deniedInstall.error?.code, "missing_permissions")
    XCTAssertTrue(install.isSuccess)
    XCTAssertEqual(install.output["requested_pack"], .string("python-uv"))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["workspace_disposition"], .string("rolled_back"))
    XCTAssertEqual(invalidExecute.status, .rejected)
    XCTAssertEqual(invalidExecute.error?.code, "invalid_input")
    XCTAssertTrue(execute.isSuccess)
    XCTAssertEqual(execute.output["workspace_id"], .string("runtime-workspace-1"))
    XCTAssertEqual(execute.output["workspace_disposition"], .string("preserved"))
    XCTAssertEqual(execute.output["artifacts"], .array([]))
    XCTAssertEqual(execute.metadata["network_default"], .string("disabled"))
    XCTAssertEqual(provider.invokedOperations, [.status, .listPacks, .workspaceStatus, .installPack, .workspaceRollback, .execute])
    XCTAssertEqual(provider.capturedInputs.last?["language"], .string("python"))
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

}
