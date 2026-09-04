import XCTest
@testable import GalaxySSI

final class GlobalAutonomousSkillHostTests: XCTestCase {
  func testDescriptorsProjectEnabledAutoInvocableSkillsOnly() throws {
    let toolId = "galaxyssi.test.echo"
    let runtime = AgentSkillRuntime(
      availableNativeToolIds: [toolId, "galaxyssi.agent.orchestrate"],
      clock: { 1_000 }
    )
    let auto = try runtime.install(manifest(id: "example.auto", toolIds: [toolId], autoInvoke: true))
    _ = try runtime.install(manifest(id: "example.manual", toolIds: [toolId], autoInvoke: false))
    _ = try runtime.install(manifest(id: "example.disabled", toolIds: [toolId], autoInvoke: true), enabled: false)
    _ = try runtime.install(manifest(
      id: "example.orchestration",
      toolIds: ["galaxyssi.agent.orchestrate"],
      autoInvoke: true
    ))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: nativeDescriptor(toolId), executorId: "test.executor")
    ])
    let host = GlobalAutonomousSkillHost { _ in runtime }

    let descriptors = host.descriptors(nativeRegistry: registry)

    XCTAssertEqual(descriptors.map(\.id), [host.toolId(skillId: auto.id, version: auto.version)])
    XCTAssertTrue(host.isSkillToolId(descriptors.singleValue().id))
  }

  func testDescriptorInheritsStrongestSafetyContract() throws {
    let low = try nativeDescriptor(
      "galaxyssi.test.read",
      risk: .low,
      requiredPermissions: [AgentNativePermissionRequirement(id: "native.read", required: true)],
      timeoutMillis: 40_000
    )
    let high = try nativeDescriptor(
      "galaxyssi.test.write",
      risk: .high,
      requiredPermissions: [AgentNativePermissionRequirement(id: "native.write", required: false)],
      requiredConsents: [AgentNativeConsentRequirement(id: "native.write.confirm", required: true)],
      timeoutMillis: 45_000
    )
    let runtime = AgentSkillRuntime(availableNativeToolIds: [low.id, high.id], clock: { 1_000 })
    let installed = try runtime.install(manifest(id: "example.strong", toolIds: [low.id, high.id]))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: low, executorId: "test.executor"),
      AgentPhoneNativeToolDefinition(descriptor: high, executorId: "test.executor")
    ])
    let host = GlobalAutonomousSkillHost { _ in runtime }

    let descriptor = try XCTUnwrap(host.descriptor(
      toolId: host.toolId(skillId: installed.id, version: installed.version),
      nativeRegistry: registry
    ))

    XCTAssertEqual(descriptor.risk, .high)
    XCTAssertEqual(Set(descriptor.requiredPermissions.map(\.id)), ["native.read", "native.write"])
    XCTAssertTrue(descriptor.requiredPermissions.first { $0.id == "native.read" }?.required == true)
    XCTAssertTrue(descriptor.requiredPermissions.first { $0.id == "native.write" }?.required == false)
    XCTAssertEqual(descriptor.requiredConsents.map(\.id), ["native.write.confirm"])
    XCTAssertEqual(descriptor.timeoutMillis, 85_000)
    XCTAssertEqual(descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertTrue(descriptor.capabilities.contains("skill.workflow"))
  }

  func testValidateInputUsesExactSkillParameterSchema() throws {
    let toolId = "galaxyssi.test.echo"
    let runtime = AgentSkillRuntime(availableNativeToolIds: [toolId], clock: { 1_000 })
    let installed = try runtime.install(manifest(id: "example.params", toolIds: [toolId]))
    let registry = try AgentNativeToolRegistry(definitions: [
      AgentPhoneNativeToolDefinition(descriptor: nativeDescriptor(toolId), executorId: "test.executor")
    ])
    let host = GlobalAutonomousSkillHost { _ in runtime }
    let skillToolId = host.toolId(skillId: installed.id, version: installed.version)

    XCTAssertTrue(host.validateInput(
      toolId: skillToolId,
      input: ["request": .string("hello")],
      nativeRegistry: registry
    ).isValid)
    XCTAssertFalse(host.validateInput(
      toolId: skillToolId,
      input: [:],
      nativeRegistry: registry
    ).isValid)
    XCTAssertFalse(host.validateInput(
      toolId: skillToolId,
      input: ["request": .string("hello"), "extra": .string("nope")],
      nativeRegistry: registry
    ).isValid)
  }

  func testInvokeRunsOrderedStepsWithReceiptsAndRecordsUse() throws {
    let first = try nativeDescriptor(
      "galaxyssi.test.first",
      requiredPermissions: [AgentNativePermissionRequirement(id: "native.echo", required: true)]
    )
    let second = try nativeDescriptor("galaxyssi.test.second")
    var order: [String] = []
    let registry = try AgentNativeToolRegistry().registerExecutables([
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: first, executorId: "test.first"),
        executor: { invocation in
          order.append(invocation.descriptor.id)
          return .success(output: [
            "value": invocation.input["value"] ?? .null,
            "permission_granted": .bool(invocation.context.grantedPermissions.contains("native.echo"))
          ], message: "first")
        }
      ),
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: second, executorId: "test.second"),
        executor: { invocation in
          order.append(invocation.descriptor.id)
          return .success(output: ["step": .string(invocation.descriptor.id)], message: "second")
        }
      )
    ])
    let runtime = AgentSkillRuntime(availableNativeToolIds: [first.id, second.id], clock: { 1_000 })
    let installed = try runtime.install(manifest(id: "example.workflow", toolIds: [first.id, second.id]))
    let host = GlobalAutonomousSkillHost { _ in runtime }
    let skillToolId = host.toolId(skillId: installed.id, version: installed.version)
    let skillDescriptor = try XCTUnwrap(host.descriptor(toolId: skillToolId, nativeRegistry: registry))
    let context = AgentNativeToolInvocationContext(
      invocationId: "skill-run",
      idempotencyKey: "skill-run-key",
      grantedPermissions: Set(skillDescriptor.requiredPermissions.filter(\.required).map(\.id))
    )

    let result = host.invoke(
      toolId: skillToolId,
      input: ["request": .string("hello")],
      nativeRegistry: registry,
      context: context,
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 2_000 })
    )

    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(order, [first.id, second.id])
    XCTAssertEqual(result.output["completed_steps"], .int(2))
    XCTAssertEqual(result.output["total_steps"], .int(2))
    XCTAssertEqual(result.output["steps"]?.arrayValue?.count, 2)
    XCTAssertEqual(result.output["final_output"]?.objectValue?["step"], .string(second.id))
    XCTAssertEqual(result.verification?.status, .passed)
    XCTAssertEqual(result.provenance.metadata["skill_id"], installed.id)
    XCTAssertEqual(runtime.get(id: installed.id, version: installed.version)?.useCount, Int64(1))
  }

  func testInvokeStopsAtFirstFailedStepWithoutRecordingUse() throws {
    let first = try nativeDescriptor("galaxyssi.test.fail")
    let second = try nativeDescriptor("galaxyssi.test.never")
    var order: [String] = []
    let registry = try AgentNativeToolRegistry().registerExecutables([
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: first, executorId: "test.first"),
        executor: { invocation in
          order.append(invocation.descriptor.id)
          return .failure(code: "boom", message: "boom")
        }
      ),
      AgentNativeToolExecutableDefinition(
        definition: AgentPhoneNativeToolDefinition(descriptor: second, executorId: "test.second"),
        executor: { invocation in
          order.append(invocation.descriptor.id)
          return .success()
        }
      )
    ])
    let runtime = AgentSkillRuntime(availableNativeToolIds: [first.id, second.id], clock: { 1_000 })
    let installed = try runtime.install(manifest(id: "example.fail", toolIds: [first.id, second.id]))
    let host = GlobalAutonomousSkillHost { _ in runtime }

    let result = host.invoke(
      toolId: host.toolId(skillId: installed.id, version: installed.version),
      input: ["request": .string("hello")],
      nativeRegistry: registry,
      context: AgentNativeToolInvocationContext(invocationId: "skill-run", idempotencyKey: "skill-run-key"),
      hooks: AgentNativeToolInvocationHooks(nowMillis: { 2_000 })
    )

    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "boom")
    XCTAssertEqual(result.output["completed_steps"], .int(1))
    XCTAssertEqual(order, [first.id])
    XCTAssertEqual(runtime.get(id: installed.id, version: installed.version)?.useCount, Int64(0))
  }

  func testUnavailableSkillDependencyIsInspectableButNotCatalogSelected() throws {
    let missingToolId = "galaxyssi.test.missing"
    let runtime = AgentSkillRuntime(availableNativeToolIds: [missingToolId], clock: { 1_000 })
    let installed = try runtime.install(manifest(id: "example.missing", toolIds: [missingToolId]))
    let host = GlobalAutonomousSkillHost { _ in runtime }
    let registry = try AgentNativeToolRegistry()

    let descriptor = try XCTUnwrap(host.descriptor(
      toolId: host.toolId(skillId: installed.id, version: installed.version),
      nativeRegistry: registry
    ))
    let selected = GlobalAutonomousToolCatalogPolicy.select(
      descriptors: [descriptor],
      goal: "Run missing workflow",
      maximumTools: 8
    )

    XCTAssertEqual(descriptor.availability.status, .unavailable)
    XCTAssertEqual(descriptor.risk, .high)
    XCTAssertTrue(selected.isEmpty)
  }

  private func manifest(
    id: String,
    toolIds: [String],
    autoInvoke: Bool = true
  ) -> AgentSkillManifest {
    let steps = toolIds.enumerated().map { index, toolId in
      AgentSkillStep(
        id: "step\(index + 1)",
        toolId: toolId,
        input: ["value": .string("{{parameters.request}}")],
        dependsOn: index == 0 ? [] : ["step\(index)"]
      )
    }
    return AgentSkillManifest(
      id: id,
      name: "Example Workflow",
      version: "1.0.0",
      summary: "Run a host-validated workflow.",
      instructions: "Use the declared native tools in order.",
      nativeTools: Set(toolIds),
      permissions: ["skill.permission"],
      parameters: .objectSchema(
        properties: ["request": .string(minLength: 1, maxLength: 128)],
        required: ["request"],
        additionalProperties: false
      ),
      steps: steps,
      autoInvoke: autoInvoke,
      triggerExamples: ["Run the workflow"]
    )
  }

  private func nativeDescriptor(
    _ id: String,
    risk: AgentNativeToolRisk = .low,
    requiredPermissions: [AgentNativePermissionRequirement] = [],
    requiredConsents: [AgentNativeConsentRequirement] = [],
    timeoutMillis: Int64 = AgentNativeToolDescriptor.defaultTimeoutMillis
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id.components(separatedBy: ".").last ?? "Tool",
      description: "Test native tool \(id).",
      location: .application,
      risk: risk,
      capabilities: [id],
      requiredPermissions: requiredPermissions,
      requiredConsents: requiredConsents,
      timeoutMillis: timeoutMillis
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
