import Foundation

struct AgentIOSDefaultSelfEvolutionProvider: AgentIOSSelfEvolutionToolProviding {
  var implementationId: String = "galaxyssi.ios.default_self_evolution_store"

  private let store: AgentIOSSelfEvolutionTaskStoring
  private let runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding
  private let nowMillis: () -> Int64
  private let idFactory: () -> String

  init(
    store: AgentIOSSelfEvolutionTaskStoring = AgentIOSFileSelfEvolutionTaskStore(),
    runtimeProvider: AgentIOSOnDeviceRuntimeToolProviding = AgentIOSDefaultOnDeviceRuntimeProvider(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    idFactory: @escaping () -> String = AgentIOSSelfEvolutionPolicy.taskId
  ) {
    self.store = store
    self.runtimeProvider = runtimeProvider
    self.nowMillis = nowMillis
    self.idFactory = idFactory
  }

  func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
    switch operation {
    case .status, .tasksList, .tasksCreate, .candidateRollback:
      return .available
    case .candidatePrepare, .candidatePatch:
      let runtime = runtimeProvider.availability(operation: .execute)
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: runtime.reason.ifBlank("Signed iOS self-evolution runtime is not connected")
      )
    }
  }

  func invoke(
    operation: AgentIOSSelfEvolutionOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    switch operation {
    case .status:
      return status()
    case .tasksList:
      return tasksList(input)
    case .tasksCreate:
      return tasksCreate(input)
    case .candidatePrepare, .candidatePatch:
      return runtimeRequiresSetup(operation: operation)
    case .candidateRollback:
      return candidateRollback(input)
    }
  }

  private func status() -> AgentNativeToolExecutionResult {
    do {
      let tasks = try store.list(limit: 500)
      let health = AgentIOSSelfEvolutionHealthAnalyzer.summarize(tasks: tasks, nowMillis: now())
      let runtime = runtimeProvider.availability(operation: .execute)
      return AgentNativeToolExecutionResult.success(
        output: [
          "execution_target": .string("ios"),
          "runtime_ready": .bool(runtime.status == .available),
          "runtime_reason": .string(runtime.reason),
          "task_count": .int(Int64(tasks.count)),
          "active_tasks": .int(Int64(health.activeTasks)),
          "health": .object(health.publicValue())
        ],
        message: "iOS-local self-evolution inspected",
        metadata: baseMetadata()
      )
    } catch {
      return failure(
        "self_evolution_status_failed",
        error.localizedDescription.ifBlank("iOS self-evolution status could not be read"),
        error: error
      )
    }
  }

  private func tasksList(_ input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    do {
      let limit = Int(input["limit"]?.intValue ?? 100).clamped(to: 1...500)
      let tasks = try store.list(limit: limit)
      let health = AgentIOSSelfEvolutionHealthAnalyzer.summarize(
        tasks: try store.list(limit: 500),
        nowMillis: now()
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "tasks": .array(tasks.map { .object($0.publicValue()) }),
          "health": .object(health.publicValue())
        ],
        message: "iOS-local evolution tasks listed",
        metadata: baseMetadata()
      )
    } catch {
      return failure(
        "self_evolution_list_failed",
        error.localizedDescription.ifBlank("iOS self-evolution tasks could not be listed"),
        error: error
      )
    }
  }

  private func tasksCreate(_ input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    do {
      let problem = boundedString(input["problem"]?.stringValue, maxLength: 4_000)
      guard problem.count >= 4 else {
        return AgentNativeToolExecutionResult.failure(
          code: "invalid_self_evolution_task",
          message: "Evolution task problem is too short"
        )
      }
      let scope = try AgentIOSSelfEvolutionPolicy.normalizedScope(
        AgentIOSSelfEvolutionPolicy.boundedStrings(
          input["scope"]?.arrayValue ?? [],
          maxItems: 64,
          maxLength: 512
        )
      )
      let acceptance = AgentIOSSelfEvolutionPolicy.boundedStrings(
        input["acceptance"]?.arrayValue ?? [],
        maxItems: 40,
        maxLength: 1_000
      )
      guard !acceptance.isEmpty else {
        return AgentNativeToolExecutionResult.failure(
          code: "invalid_self_evolution_task",
          message: "Evolution acceptance criteria are required"
        )
      }
      let reproductionSteps = AgentIOSSelfEvolutionPolicy.boundedStrings(
        input["reproduction_steps"]?.arrayValue ?? [],
        maxItems: 20,
        maxLength: 1_000
      )
      let task = AgentIOSSelfEvolutionTask(
        taskId: validTaskId(idFactory()),
        problem: problem,
        reproductionSteps: reproductionSteps,
        scope: scope,
        acceptance: acceptance,
        risk: AgentIOSSelfEvolutionRisk.fromWireValue(input["risk_level"]?.stringValue),
        maxAttempts: Int(input["max_attempts"]?.intValue ?? 3),
        createdAtMillis: now(),
        updatedAtMillis: now()
      )
      try store.save(task)
      return AgentNativeToolExecutionResult.success(
        output: taskToolValue(task),
        message: "Evolution task created",
        metadata: baseMetadata([
          "task_id": .string(task.taskId)
        ])
      )
    } catch {
      return failure(
        "self_evolution_create_failed",
        error.localizedDescription.ifBlank("iOS self-evolution task could not be created"),
        error: error
      )
    }
  }

  private func candidateRollback(_ input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    let taskId = boundedString(input["task_id"]?.stringValue, maxLength: 96)
    guard AgentIOSSelfEvolutionPolicy.isValidTaskId(taskId) else {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_self_evolution_task",
        message: "Evolution task id is invalid"
      )
    }
    do {
      guard var task = try store.get(taskId) else {
        return AgentNativeToolExecutionResult.failure(
          code: "self_evolution_task_not_found",
          message: "Evolution task was not found"
        )
      }
      task.status = .rolledBack
      task.updatedAtMillis = now()
      task.lastErrorCode = ""
      task.lastError = ""
      try store.save(task)
      return AgentNativeToolExecutionResult.success(
        output: taskToolValue(task),
        message: "Evolution candidate rolled back",
        metadata: baseMetadata([
          "task_id": .string(task.taskId),
          "candidate_workspace_id": .string(task.candidateWorkspaceId())
        ])
      )
    } catch {
      return failure(
        "self_evolution_rollback_failed",
        error.localizedDescription.ifBlank("iOS self-evolution candidate could not be rolled back"),
        error: error
      )
    }
  }

  private func runtimeRequiresSetup(
    operation: AgentIOSSelfEvolutionOperation
  ) -> AgentNativeToolExecutionResult {
    let runtime = runtimeProvider.availability(operation: .execute)
    let message = runtime.reason.ifBlank("Signed iOS self-evolution runtime is not connected")
    return AgentNativeToolExecutionResult.failure(
      code: "self_evolution_runtime_requires_setup",
      message: message,
      retryable: true,
      details: baseMetadata([
        "operation": .string(operation.rawValue),
        "runtime_availability": .string(runtime.status.rawValue)
      ])
    )
  }

  private func taskToolValue(_ task: AgentIOSSelfEvolutionTask) -> AgentMcpJSONObject {
    [
      "task": .object(task.publicValue()),
      "candidate_workspace_id": .string(task.candidateWorkspaceId()),
      "candidate_source_root": .string(task.candidateSourceRoot())
    ]
  }

  private func failure(
    _ code: String,
    _ message: String,
    error: Error
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: code,
      message: message,
      details: baseMetadata([
        "error_type": .string(String(describing: type(of: error)))
      ])
    )
  }

  private func baseMetadata(_ extra: AgentMcpJSONObject = [:]) -> AgentMcpJSONObject {
    [
      "implementation": .string(implementationId),
      "protocol": .string(AgentIOSSelfEvolutionNativeToolCatalog.protocolId),
      "execution_target": .string("ios"),
      "production_mutation": .bool(false),
      "patch_content_retained": .bool(false),
      "review_only_candidate": .bool(true)
    ].merging(extra) { _, new in new }
  }

  private func boundedString(_ value: String?, maxLength: Int) -> String {
    String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
  }

  private func validTaskId(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if AgentIOSSelfEvolutionPolicy.isValidTaskId(trimmed) {
      return trimmed
    }
    return AgentIOSSelfEvolutionPolicy.taskId()
  }

  private func now() -> Int64 {
    max(0, nowMillis())
  }
}
