import Foundation

enum AgentIOSSelfEvolutionOperation: String, Codable, CaseIterable, Identifiable {
  case status
  case tasksList = "tasks.list"
  case tasksCreate = "tasks.create"
  case candidatePrepare = "candidate.prepare"
  case candidatePatch = "candidate.patch"
  case candidateRollback = "candidate.rollback"

  var id: String { rawValue }
}

protocol AgentIOSSelfEvolutionToolProviding {
  var implementationId: String { get }
  func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSSelfEvolutionOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableSelfEvolutionToolProvider: AgentIOSSelfEvolutionToolProviding {
  var implementationId: String = "galaxyssi.ios.self_evolution_unconfigured"

  func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: AgentIOSSelfEvolutionNativeToolCatalog.requiresRuntime(operation)
        ? "iOS self-evolution runtime is not connected"
        : "iOS self-evolution task store is not connected"
    )
  }

  func invoke(
    operation: AgentIOSSelfEvolutionOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "self_evolution_provider_unavailable",
      message: "iOS self-evolution provider is not connected",
      retryable: true
    )
  }
}

enum AgentIOSSelfEvolutionNativeToolCatalog {
  static let status = "galaxyssi.evolution.status"
  static let tasksList = "galaxyssi.evolution.tasks.list"
  static let tasksCreate = "galaxyssi.evolution.tasks.create"
  static let candidatePrepare = "galaxyssi.evolution.candidate.prepare"
  static let candidatePatch = "galaxyssi.evolution.candidate.patch"
  static let candidateRollback = "galaxyssi.evolution.candidate.rollback"

  static let protocolId = "galaxyssi.evolution-task.v1"
  static let executorId = "galaxyssi.ios_self_evolution"
  static let storePermission = "galaxyssi.scope.self_evolution_store"
  static let workspacePermission = "galaxyssi.scope.self_evolution_workspace"
  static let runtimePermission = "galaxyssi.scope.signed_self_evolution_runtime"
  static let selfEvolutionConsent = "galaxyssi.consent.self_evolution"
  static let noAdditionalConsent = "galaxyssi.consent.none"

  static let maxPatchBytes: Int64 = 160 * 1_024
  static let orderedToolIds = [
    status,
    tasksList,
    tasksCreate,
    candidatePrepare,
    candidatePatch,
    candidateRollback
  ]
  static let toolIds: Set<String> = Set(orderedToolIds)

  static func definitions(
    provider: AgentIOSSelfEvolutionToolProviding = AgentIOSUnavailableSelfEvolutionToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSSelfEvolutionOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSSelfEvolutionOperation? {
    switch toolId {
    case status:
      return .status
    case tasksList:
      return .tasksList
    case tasksCreate:
      return .tasksCreate
    case candidatePrepare:
      return .candidatePrepare
    case candidatePatch:
      return .candidatePatch
    case candidateRollback:
      return .candidateRollback
    default:
      return nil
    }
  }

  static func toolId(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return status
    case .tasksList:
      return tasksList
    case .tasksCreate:
      return tasksCreate
    case .candidatePrepare:
      return candidatePrepare
    case .candidatePatch:
      return candidatePatch
    case .candidateRollback:
      return candidateRollback
    }
  }

  static func title(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return "Inspect local self-evolution"
    case .tasksList:
      return "List local evolution tasks"
    case .tasksCreate:
      return "Create a local evolution task"
    case .candidatePrepare:
      return "Prepare an isolated local candidate"
    case .candidatePatch:
      return "Apply and validate a local evolution patch"
    case .candidateRollback:
      return "Discard a local evolution candidate"
    }
  }

  static func requiresRuntime(_ operation: AgentIOSSelfEvolutionOperation) -> Bool {
    switch operation {
    case .candidatePrepare, .candidatePatch:
      return true
    case .status, .tasksList, .tasksCreate, .candidateRollback:
      return false
    }
  }

  private static func definition(
    provider: AgentIOSSelfEvolutionToolProviding,
    operation: AgentIOSSelfEvolutionOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(),
      risk: risk(operation),
      capabilities: capabilities(operation),
      requiredPermissions: permissionRequirements(operation),
      requiredConsents: consentRequirements(operation),
      timeoutMillis: timeoutMillis(operation),
      idempotency: operation == .candidatePatch ? .idempotencyKeyRequired : .nonIdempotent,
      availability: provider.availability(operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "platform": "ios_phone",
        "protocol": protocolId,
        "compatibility_source": "AgentSelfEvolutionNativeTools",
        "isolation": "ios_disposable_candidate_workspace",
        "production_mutation": "disabled",
        "patch_content_retained": "false"
      ]
    )
  }

  private static func description(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status:
      return "Reports iOS-local evolution tasks, candidate state, and runtime readiness using Android-compatible output fields."
    case .tasksList:
      return "Lists bounded iOS-local evolution tasks and their immutable quality-gate receipts."
    case .tasksCreate:
      return "Creates a scoped self-improvement task without changing source or the running app."
    case .candidatePrepare:
      return "Prepares a disposable iOS-local candidate workspace and pins its base revision before any patch is applied."
    case .candidatePatch:
      return "Applies one unified diff in the disposable candidate, enforces scope, runs quality gates, and returns a review-only candidate receipt."
    case .candidateRollback:
      return "Deletes only the disposable iOS-local candidate and preserves the running app and stable source."
    }
  }

  private static func risk(_ operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolRisk {
    switch operation {
    case .status, .tasksList, .tasksCreate:
      return .low
    case .candidatePrepare, .candidateRollback:
      return .medium
    case .candidatePatch:
      return .high
    }
  }

  private static func capabilities(_ operation: AgentIOSSelfEvolutionOperation) -> Set<String> {
    var result: Set<String> = [
      "evolution.self",
      "evolution.worktree",
      "evolution.quality_gates",
      "runtime.ios_local",
      "source.review_only"
    ]
    if requiresRuntime(operation) {
      result.formUnion(["runtime.sandboxed", "runtime.signed"])
    }
    if operation == .candidatePatch {
      result.insert("patch.unified_diff")
    }
    return result
  }

  private static func permissionRequirements(_ operation: AgentIOSSelfEvolutionOperation) -> [AgentNativePermissionRequirement] {
    var requirements = [
      AgentNativePermissionRequirement(
        id: storePermission,
        title: "Self-evolution task store",
        description: "Limits self-evolution task state to GalaxySSI's local encrypted store."
      )
    ]
    if operation == .candidatePrepare || operation == .candidatePatch || operation == .candidateRollback {
      requirements.append(
        AgentNativePermissionRequirement(
          id: workspacePermission,
          title: "Disposable candidate workspace",
          description: "Allows source changes only inside a disposable candidate workspace."
        )
      )
    }
    if requiresRuntime(operation) {
      requirements.append(
        AgentNativePermissionRequirement(
          id: runtimePermission,
          title: "Signed self-evolution runtime",
          description: "Requires a signed local runtime for candidate preparation and quality gates."
        )
      )
    }
    return requirements.sorted { $0.id < $1.id }
  }

  private static func consentRequirements(_ operation: AgentIOSSelfEvolutionOperation) -> [AgentNativeConsentRequirement] {
    switch operation {
    case .candidatePrepare, .candidatePatch, .candidateRollback:
      return [
        AgentNativeConsentRequirement(
          id: selfEvolutionConsent,
          title: "Modify an isolated GalaxySSI candidate",
          description: "Allows source changes only inside a disposable candidate workspace."
        )
      ]
    case .status, .tasksList, .tasksCreate:
      return [
        AgentNativeConsentRequirement(
          id: noAdditionalConsent,
          title: "No additional consent",
          description: "This self-evolution task-store operation does not modify source code.",
          required: false
        )
      ]
    }
  }

  private static func timeoutMillis(_ operation: AgentIOSSelfEvolutionOperation) -> Int64 {
    switch operation {
    case .candidatePrepare:
      return 15 * 60_000
    case .candidatePatch:
      return 30 * 60_000
    case .status, .tasksList, .tasksCreate, .candidateRollback:
      return 30_000
    }
  }

  private static func inputSchema(_ operation: AgentIOSSelfEvolutionOperation) -> AgentMcpJSONObject {
    switch operation {
    case .status:
      return objectSchema([:])
    case .tasksList:
      return objectSchema([
        "limit": integerSchema(minimum: 1, maximum: 500)
      ])
    case .tasksCreate:
      return objectSchema([
        "problem": stringSchema(minLength: 4, maxLength: 4_000),
        "scope": stringArraySchema(minItems: 1, maxItems: 64, maxLength: 512),
        "acceptance": stringArraySchema(minItems: 1, maxItems: 40, maxLength: 1_000),
        "reproduction_steps": stringArraySchema(minItems: 0, maxItems: 20, maxLength: 1_000),
        "risk_level": stringSchema(enumValues: ["low", "medium", "high", "critical"]),
        "max_attempts": integerSchema(minimum: 1, maximum: 5)
      ], required: ["problem", "scope", "acceptance"])
    case .candidatePrepare, .candidateRollback:
      return taskIdSchema()
    case .candidatePatch:
      return objectSchema([
        "task_id": stringSchema(minLength: 1, maxLength: 96),
        "unified_diff": stringSchema(minLength: 1, maxLength: maxPatchBytes)
      ], required: ["task_id", "unified_diff"])
    }
  }

  private static func outputSchema() -> AgentMcpJSONObject {
    objectSchema([
      "protocol": stringSchema(enumValues: [protocolId]),
      "operation": stringSchema(enumValues: AgentIOSSelfEvolutionOperation.allCases.map(\.rawValue)),
      "execution_target": stringSchema(enumValues: ["ios"]),
      "runtime_ready": boolSchema(),
      "runtime_reason": stringSchema(maxLength: 2_048),
      "task_count": integerSchema(minimum: 0),
      "active_tasks": integerSchema(minimum: 0),
      "status": stringSchema(enumValues: [
        "completed",
        "proposed",
        "preparing",
        "running",
        "validating",
        "waiting_approval",
        "publishing",
        "published",
        "failed",
        "blocked",
        "cancelled",
        "rolled_back",
        "partial"
      ]),
      "task": objectSchema(additionalProperties: true),
      "tasks": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 500),
      "health": objectSchema(additionalProperties: true),
      "candidate_workspace_id": stringSchema(maxLength: 128),
      "candidate_source_root": stringSchema(maxLength: 64),
      "production_mutation": boolSchema(),
      "observed_at_epoch_ms": integerSchema(minimum: 0)
    ], additionalProperties: true)
  }

  private static func taskIdSchema() -> AgentMcpJSONObject {
    objectSchema([
      "task_id": stringSchema(minLength: 1, maxLength: 96)
    ], required: ["task_id"])
  }

  private static func objectSchema(
    _ properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(
    minLength: Int64? = nil,
    maxLength: Int64? = nil,
    enumValues: [String] = []
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(minLength) }
    if let maxLength { schema["maxLength"] = .int(maxLength) }
    if !enumValues.isEmpty {
      schema["enum"] = .array(enumValues.map(AgentMcpJSONValue.string))
    }
    return schema
  }

  private static func integerSchema(minimum: Int64, maximum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("integer"),
      "minimum": .int(minimum)
    ]
    if let maximum { schema["maximum"] = .int(maximum) }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  private static func stringArraySchema(
    minItems: Int64,
    maxItems: Int64,
    maxLength: Int64
  ) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(stringSchema(minLength: 1, maxLength: maxLength)),
      "minItems": .int(minItems),
      "maxItems": .int(maxItems)
    ]
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSSelfEvolutionNativeToolExecutor {
  var provider: AgentIOSSelfEvolutionToolProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSSelfEvolutionToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.nowMillis = nowMillis
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let operation = AgentIOSSelfEvolutionNativeToolCatalog.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "self_evolution_unknown_tool",
        message: "Unknown self-evolution native tool."
      )
    }
    try invocation.reportProgress(
      stage: "evolution",
      message: AgentIOSSelfEvolutionNativeToolCatalog.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    var metadata = execution.metadata
    output.removeValue(forKey: "unified_diff")
    metadata.removeValue(forKey: "unified_diff")
    output["protocol"] = output["protocol"] ?? .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId)
    output["operation"] = output["operation"] ?? .string(operation.rawValue)
    output["execution_target"] = output["execution_target"] ?? .string("ios")
    output["status"] = output["status"] ?? .string(defaultStatus(operation))
    output["production_mutation"] = output["production_mutation"] ?? .bool(false)
    output["observed_at_epoch_ms"] = output["observed_at_epoch_ms"] ?? .int(max(0, nowMillis()))
    metadata["protocol"] = metadata["protocol"] ?? .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId)
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    metadata["production_mutation"] = metadata["production_mutation"] ?? .bool(false)
    metadata["patch_content_retained"] = metadata["patch_content_retained"] ?? .bool(false)
    metadata["review_only_candidate"] = metadata["review_only_candidate"] ?? .bool(true)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentIOSSelfEvolutionNativeToolCatalog.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }

  private func defaultStatus(_ operation: AgentIOSSelfEvolutionOperation) -> String {
    switch operation {
    case .status, .tasksList:
      return "completed"
    case .tasksCreate:
      return "proposed"
    case .candidatePrepare:
      return "running"
    case .candidatePatch:
      return "waiting_approval"
    case .candidateRollback:
      return "rolled_back"
    }
  }
}
