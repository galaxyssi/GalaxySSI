import XCTest
@testable import GalaxySSI

final class AgentSkillExecutionTests: XCTestCase {
  func testAgentSkillExecutionEngineInvokesExpandedStepsAndRecordsUse() throws {
    let toolId = "galaxyssi.test.echo"
    let descriptor = try nativeDescriptor(
      toolId,
      requiredPermissions: [AgentNativePermissionRequirement(id: "native.echo", required: true)]
    )
    let registry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: descriptor, executorId: "test.executor"),
      executor: { invocation in
        .success(output: [
          "value": invocation.input["value"] ?? .null,
          "permission_granted": .bool(invocation.context.grantedPermissions.contains("native.echo")),
          "skill_id": .string(invocation.context.attributes["skill_id"] ?? "")
        ])
      }
    ))
    let runtime = AgentSkillRuntime(availableNativeToolIds: [toolId], clock: { 1_000 })
    let installation = try runtime.install(manifest(toolId: toolId))
    let match = AgentSkillMatch(
      installation: installation,
      confidence: 1,
      parameters: ["request": .string("hello")],
      explicit: true
    )

    let result = AgentSkillExecutionEngine(runtime: runtime, registry: registry)
      .execute(match: match, conversationId: "conversation", turnId: "turn")

    XCTAssertTrue(result.success)
    XCTAssertEqual(result.toolResults.singleValue().output["value"], .string("hello"))
    XCTAssertEqual(result.toolResults.singleValue().output["permission_granted"], .bool(true))
    XCTAssertEqual(result.toolResults.singleValue().output["skill_id"], .string(installation.id))
    XCTAssertEqual(runtime.get(id: installation.id, version: installation.version)?.useCount, Int64(1))
  }

  func testAgentSkillExecutionEngineFallsBackBeforeUnsafeInvocation() throws {
    let missingRuntime = AgentSkillRuntime(clock: { 1_000 })
    let missingInstallation = try missingRuntime.install(manifest(toolId: "galaxyssi.test.missing"))
    let missing = AgentSkillExecutionEngine(runtime: missingRuntime, registry: try AgentNativeToolRegistry())
      .execute(match: AgentSkillMatch(
        installation: missingInstallation,
        confidence: 1,
        parameters: ["request": .string("hello")],
        explicit: false
      ))

    XCTAssertFalse(missing.success)
    XCTAssertTrue(missing.message.contains("Missing tool"))
    XCTAssertTrue(missing.toolResults.isEmpty)
    XCTAssertEqual(missingRuntime.get(id: missingInstallation.id, version: missingInstallation.version)?.useCount, Int64(0))

    var executions = 0
    let highRiskId = "galaxyssi.test.highrisk"
    let highRiskDescriptor = try nativeDescriptor(highRiskId, risk: .high)
    let highRiskRegistry = try AgentNativeToolRegistry().registerExecutable(AgentNativeToolExecutableDefinition(
      definition: AgentPhoneNativeToolDefinition(descriptor: highRiskDescriptor, executorId: "test.executor"),
      executor: { _ in
        executions += 1
        return .success()
      }
    ))
    let highRiskRuntime = AgentSkillRuntime(availableNativeToolIds: [highRiskId], clock: { 1_000 })
    let highRiskInstallation = try highRiskRuntime.install(manifest(toolId: highRiskId))
    let blocked = AgentSkillExecutionEngine(runtime: highRiskRuntime, registry: highRiskRegistry)
      .execute(match: AgentSkillMatch(
        installation: highRiskInstallation,
        confidence: 1,
        parameters: ["request": .string("hello")],
        explicit: false
      ))

    XCTAssertFalse(blocked.success)
    XCTAssertTrue(blocked.message.contains("interactive authorization"))
    XCTAssertEqual(executions, 0)
    XCTAssertEqual(highRiskRuntime.get(id: highRiskInstallation.id, version: highRiskInstallation.version)?.useCount, Int64(0))
  }

  func testAgentSkillVersionManagerBuildsUpgradeAndRollsBack() throws {
    let toolId = "galaxyssi.test.echo"
    let runtime = AgentSkillRuntime(availableNativeToolIds: [toolId], clock: { 1_000 })
    let installed = try runtime.install(manifest(toolId: toolId))
    let corrected = AgentRecordedRun(
      runId: "corrected",
      conversationId: "conversation",
      taskThreadId: "thread",
      originalRequest: "Run the workflow with the local source",
      renderSpec: ["view": .string("compact")],
      userFeedback: ["Use the local source instead"],
      activeSkillId: installed.id,
      status: .completed
    )
    let manager = AgentSkillVersionManager(runtime)

    let proposal = try manager.buildUpgrade(base: installed, improvedRuns: [corrected])
    XCTAssertEqual(proposal.version, "1.1.0")
    XCTAssertTrue(proposal.instructions.contains("Use the local source instead"))
    XCTAssertEqual(proposal.renderSpec["view"], .string("compact"))
    XCTAssertNil(runtime.get(id: installed.id, version: proposal.version))

    let upgraded = try manager.upgrade(base: installed, improvedRuns: [corrected])
    let rolledBack = try manager.rollback(id: installed.id, currentVersion: upgraded.version)

    XCTAssertEqual(upgraded.version, "1.1.0")
    XCTAssertEqual(rolledBack.version, "1.0.0")
    XCTAssertTrue(runtime.get(id: installed.id, version: "1.0.0")?.enabled == true)
    XCTAssertTrue(runtime.get(id: installed.id, version: "1.1.0")?.enabled == false)
  }

  private func manifest(toolId: String) -> AgentSkillManifest {
    AgentSkillManifest(
      id: "example.echo",
      name: "Echo",
      version: "1.0.0",
      summary: "Echo a request",
      instructions: "Echo the request using a native tool.",
      nativeTools: [toolId],
      permissions: ["skill.permission"],
      parameters: .objectSchema(
        properties: ["request": .string(minLength: 0, maxLength: 1_024)],
        required: []
      ),
      steps: [
        AgentSkillStep(id: "run", toolId: toolId, input: ["value": .string("{{parameters.request}}")])
      ],
      autoInvoke: true,
      triggerExamples: ["Echo this"]
    )
  }

  private func nativeDescriptor(
    _ id: String,
    risk: AgentNativeToolRisk = .low,
    requiredPermissions: [AgentNativePermissionRequirement] = []
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: "Echo",
      description: "Echoes bounded input.",
      location: .application,
      risk: risk,
      requiredPermissions: requiredPermissions
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
