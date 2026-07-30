import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSSelfEvolutionNativeToolCatalogAndExecutorMirrorsAndroidWireProtocol() throws {
    final class FakeSelfEvolutionProvider: AgentIOSSelfEvolutionToolProviding {
      var implementationId = "fake.ios.self_evolution"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSSelfEvolutionOperation] = []
      var capturedInputs: [AgentMcpJSONObject] = []

      func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSSelfEvolutionOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        capturedInputs.append(input)
        switch operation {
        case .status:
          return AgentNativeToolExecutionResult.success(
            output: [
              "execution_target": .string("ios"),
              "runtime_ready": .bool(true),
              "runtime_reason": .string("ready"),
              "task_count": .int(1),
              "active_tasks": .int(0),
              "health": .object(["total_tasks": .int(1), "active_tasks": .int(0)])
            ],
            message: "iOS-local self-evolution inspected"
          )
        case .tasksList:
          return AgentNativeToolExecutionResult.success(
            output: [
              "tasks": .array([.object(taskValue(status: "proposed"))]),
              "health": .object(["total_tasks": .int(1)])
            ],
            message: "iOS-local evolution tasks listed"
          )
        case .tasksCreate:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "proposed")),
              "candidate_workspace_id": .string(""),
              "candidate_source_root": .string("")
            ],
            message: "Evolution task created"
          )
        case .candidatePrepare:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "running")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source")
            ],
            message: "Evolution candidate prepared"
          )
        case .candidatePatch:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "waiting_approval")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("source"),
              "unified_diff": .string("diff --git a/secret b/secret")
            ],
            message: "Evolution candidate validated",
            metadata: ["unified_diff": .string("diff --git a/secret b/secret")]
          )
        case .candidateRollback:
          return AgentNativeToolExecutionResult.success(
            output: [
              "task": .object(taskValue(status: "rolled_back")),
              "candidate_workspace_id": .string("evolve-ios-a1"),
              "candidate_source_root": .string("")
            ],
            message: "Evolution candidate rolled back"
          )
        }
      }

      private func taskValue(status: String) -> AgentMcpJSONObject {
        [
          "protocol": .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId),
          "task_id": .string("evolve-ios-1"),
          "problem": .string("Mirror Android self-evolution tools on iOS"),
          "reproduction_steps": .array([.string("Open iOS agent tool catalog")]),
          "scope": .array([.string("apps/ios")]),
          "acceptance": .array([.string("Android wire-compatible tool ids are registered")]),
          "risk_level": .string("medium"),
          "max_attempts": .int(3),
          "status": .string(status),
          "execution_target": .string("ios"),
          "base_commit": .string("base"),
          "candidate_commit": .string(status == "waiting_approval" ? "candidate" : ""),
          "candidate_branch": .string(status == "waiting_approval" ? "evolution/evolve-ios-1-a1" : ""),
          "approval_hash": .string(status == "waiting_approval" ? "approval" : ""),
          "attempts": .array([]),
          "last_error_code": .string(""),
          "last_error": .string(""),
          "created_at_millis": .int(1_000),
          "updated_at_millis": .int(2_000)
        ]
      }
    }

    let provider = FakeSelfEvolutionProvider()
    let definitions = AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: provider, nowMillis: { 44_000 })
    )
    let readContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSSelfEvolutionNativeToolCatalog.storePermission]
    )
    let candidateContext = AgentNativeToolInvocationContext(
      invocationId: "evolution-patch-1",
      idempotencyKey: "patch-key-1",
      grantedPermissions: [
        AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
        AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
      ],
      grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
    )

    XCTAssertEqual(Set(AgentIOSSelfEvolutionNativeToolCatalog.orderedToolIds), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    XCTAssertTrue(AgentIOSSelfEvolutionNativeToolCatalog.toolIds.contains("signalasi.evolution.candidate.patch"))
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSSelfEvolutionNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .application)
      XCTAssertTrue(definition.descriptor.capabilities.contains("evolution.self"))
      XCTAssertEqual(definition.provenanceMetadata["compatibility_source"], "AgentSelfEvolutionNativeTools")
      XCTAssertEqual(definition.provenanceMetadata["production_mutation"], "disabled")
    }
    let prepareDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare })
    let patchDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch })
    let createDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate })
    XCTAssertEqual(createDescriptor.descriptor.risk, .low)
    XCTAssertEqual(createDescriptor.descriptor.requiredConsents.first?.required, false)
    XCTAssertEqual(prepareDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent])
    XCTAssertEqual(patchDescriptor.descriptor.risk, .high)
    XCTAssertEqual(patchDescriptor.descriptor.timeoutMillis, 30 * 60_000)
    XCTAssertEqual(patchDescriptor.descriptor.idempotency, .idempotencyKeyRequired)

    let status = registry.invoke(AgentIOSSelfEvolutionNativeToolCatalog.status, input: [:], context: readContext)
    let list = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksList,
      input: ["limit": .int(2)],
      context: readContext
    )
    let create = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.tasksCreate,
      input: [
        "problem": .string("Mirror Android self-evolution tools on iOS"),
        "scope": .array([.string("apps/ios")]),
        "acceptance": .array([.string("Tool ids match Android")])
      ],
      context: readContext
    )
    let deniedPrepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ]
      )
    )
    let missingPatchKey = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [
          AgentIOSSelfEvolutionNativeToolCatalog.storePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.workspacePermission,
          AgentIOSSelfEvolutionNativeToolCatalog.runtimePermission
        ],
        grantedConsents: [AgentIOSSelfEvolutionNativeToolCatalog.selfEvolutionConsent]
      )
    )
    let prepare = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePrepare,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let patch = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/apps/ios/a b/apps/ios/a")
      ],
      context: candidateContext
    )
    let rollback = registry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidateRollback,
      input: ["task_id": .string("evolve-ios-1")],
      context: candidateContext
    )
    let unavailableProvider = FakeSelfEvolutionProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Install signed self-evolution runtime"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSSelfEvolutionNativeToolCatalog.candidatePatch,
      input: [
        "task_id": .string("evolve-ios-1"),
        "unified_diff": .string("diff --git a/a b/a")
      ],
      context: candidateContext
    )

    XCTAssertTrue(status.isSuccess)
    XCTAssertEqual(status.output["protocol"], .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId))
    XCTAssertEqual(status.output["runtime_ready"], .bool(true))
    XCTAssertTrue(list.isSuccess)
    XCTAssertEqual(provider.capturedInputs[1]["limit"], .int(2))
    XCTAssertTrue(create.isSuccess)
    XCTAssertEqual(create.output["status"], .string("proposed"))
    XCTAssertEqual(deniedPrepare.status, .rejected)
    XCTAssertEqual(deniedPrepare.error?.code, "missing_consents")
    XCTAssertEqual(missingPatchKey.status, .rejected)
    XCTAssertEqual(missingPatchKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(prepare.isSuccess)
    XCTAssertEqual(prepare.output["candidate_source_root"], .string("source"))
    XCTAssertTrue(patch.isSuccess)
    XCTAssertEqual(patch.output["status"], .string("waiting_approval"))
    XCTAssertNil(patch.output["unified_diff"])
    XCTAssertNil(patch.metadata["unified_diff"])
    XCTAssertEqual(patch.metadata["patch_content_retained"], .bool(false))
    XCTAssertTrue(rollback.isSuccess)
    XCTAssertEqual(rollback.output["status"], .string("rolled_back"))
    XCTAssertEqual(provider.invokedOperations, [.status, .tasksList, .tasksCreate, .candidatePrepare, .candidatePatch, .candidateRollback])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

}
