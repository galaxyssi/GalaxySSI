import Foundation

enum AgentSubagentFailurePolicy: String, Codable, CaseIterable, Identifiable {
  case `continue` = "CONTINUE"
  case failFast = "FAIL_FAST"

  var id: String { rawValue }
}

enum AgentSubagentDependencyPolicy: String, Codable, CaseIterable, Identifiable {
  case requireSuccess = "REQUIRE_SUCCESS"
  case allowTerminal = "ALLOW_TERMINAL"

  var id: String { rawValue }
}

enum AgentSubagentRunStatus: String, Codable, CaseIterable, Identifiable {
  case succeeded = "SUCCEEDED"
  case completedWithFailures = "COMPLETED_WITH_FAILURES"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }
}

struct AgentSubagentLimits: Codable, Equatable {
  static let defaultMaxChildren = 12
  static let defaultMaxDepth = 3
  static let defaultMaxConcurrency = 3
  static let defaultMaxContextCharacters = 8_000
  static let defaultMaxOutputCharacters = 16_000

  var maxChildren: Int
  var maxDepth: Int
  var maxConcurrency: Int
  var maxContextCharacters: Int
  var maxOutputCharacters: Int

  init(
    maxChildren: Int = Self.defaultMaxChildren,
    maxDepth: Int = Self.defaultMaxDepth,
    maxConcurrency: Int = Self.defaultMaxConcurrency,
    maxContextCharacters: Int = Self.defaultMaxContextCharacters,
    maxOutputCharacters: Int = Self.defaultMaxOutputCharacters
  ) {
    precondition(maxChildren > 0)
    precondition(maxDepth > 0)
    precondition(maxConcurrency > 0)
    precondition(maxContextCharacters >= 0)
    precondition(maxOutputCharacters >= 0)
    self.maxChildren = maxChildren
    self.maxDepth = maxDepth
    self.maxConcurrency = maxConcurrency
    self.maxContextCharacters = maxContextCharacters
    self.maxOutputCharacters = maxOutputCharacters
  }
}

struct AgentSubagentProvenance: Codable, Equatable {
  var source: String
  var sourceId: String
  var traceId: String
  var metadata: [String: String]

  init(
    source: String = "unspecified",
    sourceId: String = "",
    traceId: String = "",
    metadata: [String: String] = [:]
  ) {
    self.source = source
    self.sourceId = sourceId
    self.traceId = traceId
    self.metadata = metadata
  }
}

struct AgentSubagentChild: Codable, Equatable, Identifiable {
  var childId: String
  var parentId: String?
  var dependencies: Set<String>
  var dependencyPolicy: AgentSubagentDependencyPolicy
  var context: String
  var provenance: AgentSubagentProvenance

  var id: String { childId }

  init(
    childId: String,
    parentId: String? = nil,
    dependencies: Set<String> = [],
    dependencyPolicy: AgentSubagentDependencyPolicy = .requireSuccess,
    context: String = "",
    provenance: AgentSubagentProvenance = AgentSubagentProvenance()
  ) {
    self.childId = childId
    self.parentId = parentId
    self.dependencies = dependencies
    self.dependencyPolicy = dependencyPolicy
    self.context = context
    self.provenance = provenance
  }
}

struct AgentSubagentPlan: Codable, Equatable {
  var supervisorId: String
  var children: [AgentSubagentChild]
  var failurePolicy: AgentSubagentFailurePolicy
  var provenance: AgentSubagentProvenance

  init(
    supervisorId: String,
    children: [AgentSubagentChild],
    failurePolicy: AgentSubagentFailurePolicy = .continue,
    provenance: AgentSubagentProvenance = AgentSubagentProvenance()
  ) {
    self.supervisorId = supervisorId
    self.children = children
    self.failurePolicy = failurePolicy
    self.provenance = provenance
  }
}

struct AgentSubagentDependencyHandoff: Codable, Equatable, Identifiable {
  var childId: String
  var status: AgentSubagentStatus
  var output: String
  var outputTruncated: Bool
  var errorMessage: String
  var provenance: AgentSubagentProvenance

  var id: String { childId }
}

struct AgentSubagentContextHandoff: Codable, Equatable {
  var context: String
  var dependencies: [AgentSubagentDependencyHandoff]
  var usedCharacters: Int
  var maxCharacters: Int
  var truncated: Bool
}

struct AgentSubagentExecutionContext {
  var supervisorId: String
  var childId: String
  var parentId: String
  var depth: Int
  var handoff: AgentSubagentContextHandoff
  var provenance: AgentSubagentProvenance

  func ensureActive() throws {
    try Task.checkCancellation()
  }

  func dependency(_ childId: String) -> AgentSubagentDependencyHandoff? {
    handoff.dependencies.first { $0.childId == childId.trimmingCharacters(in: .whitespacesAndNewlines) }
  }
}

struct AgentSubagentOutput: Codable, Equatable {
  var content: String

  init(content: String = "") {
    self.content = content
  }
}

protocol AgentSubagentWorker {
  func execute(context: AgentSubagentExecutionContext) async throws -> AgentSubagentOutput
}

struct ClosureAgentSubagentWorker: AgentSubagentWorker {
  let body: (AgentSubagentExecutionContext) async throws -> AgentSubagentOutput

  init(_ body: @escaping (AgentSubagentExecutionContext) async throws -> AgentSubagentOutput) {
    self.body = body
  }

  func execute(context: AgentSubagentExecutionContext) async throws -> AgentSubagentOutput {
    try await body(context)
  }
}

struct AgentSubagentChildResult: Codable, Equatable, Identifiable {
  static let maxErrorCharacters = 1_024

  var supervisorId: String
  var childId: String
  var parentId: String
  var depth: Int
  var status: AgentSubagentStatus
  var output: String
  var outputTruncated: Bool
  var errorMessage: String
  var provenance: AgentSubagentProvenance
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  var id: String { childId }

  init(
    supervisorId: String,
    childId: String,
    parentId: String,
    depth: Int,
    status: AgentSubagentStatus,
    output: String = "",
    outputTruncated: Bool = false,
    errorMessage: String = "",
    provenance: AgentSubagentProvenance = AgentSubagentProvenance(),
    startedAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0
  ) {
    self.supervisorId = supervisorId
    self.childId = childId
    self.parentId = parentId
    self.depth = max(depth, 0)
    self.status = status
    self.output = output
    self.outputTruncated = outputTruncated
    self.errorMessage = String(errorMessage.prefix(Self.maxErrorCharacters))
    self.provenance = provenance
    self.startedAtMillis = max(startedAtMillis, 0)
    self.completedAtMillis = max(completedAtMillis, 0)
  }
}

struct AgentSubagentRunResult: Codable, Equatable {
  var supervisorId: String
  var status: AgentSubagentRunStatus
  var results: [AgentSubagentChildResult]
  var provenance: AgentSubagentProvenance
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  subscript(childId: String) -> AgentSubagentChildResult? {
    results.first { $0.childId == childId.trimmingCharacters(in: .whitespacesAndNewlines) }
  }
}

enum AgentSubagentEventKinds {
  static let supervisorStarted = "subagent.supervisor.started"
  static let supervisorSucceeded = "subagent.supervisor.succeeded"
  static let supervisorCompletedWithFailures = "subagent.supervisor.completed_with_failures"
  static let supervisorFailed = "subagent.supervisor.failed"
  static let supervisorCancelled = "subagent.supervisor.cancelled"
  static let childQueued = "subagent.child.queued"
  static let childRunning = "subagent.child.running"
  static let childSucceeded = "subagent.child.succeeded"
  static let childFailed = "subagent.child.failed"
  static let childCancelled = "subagent.child.cancelled"
  static let childSkipped = "subagent.child.skipped"
}

struct AgentSubagentEvent: Codable, Equatable, Identifiable {
  var sequence: Int64
  var supervisorId: String
  var childId: String
  var kind: String
  var childStatus: AgentSubagentStatus?
  var runStatus: AgentSubagentRunStatus?
  var message: String
  var provenance: AgentSubagentProvenance
  var result: AgentSubagentChildResult?
  var timestampMillis: Int64

  var id: String { "\(supervisorId):\(sequence)" }
}

protocol AgentSubagentEventHook {
  func append(_ event: AgentSubagentEvent) async throws
}

struct NoOpAgentSubagentEventHook: AgentSubagentEventHook {
  func append(_ event: AgentSubagentEvent) async throws {}
}

final class AgentSubagentRunHandle {
  let supervisorId: String
  private let task: Task<AgentSubagentRunResult, Error>
  private let control: AgentSubagentRunControl

  fileprivate init(
    supervisorId: String,
    task: Task<AgentSubagentRunResult, Error>,
    control: AgentSubagentRunControl
  ) {
    self.supervisorId = supervisorId
    self.task = task
    self.control = control
  }

  var isActive: Bool { control.isActive }

  func wait() async throws -> AgentSubagentRunResult {
    try await task.value
  }

  @discardableResult
  func cancel(reason: String = "Subagent supervisor cancellation requested") -> Bool {
    control.requestCancellation(reason)
  }
}

final class AgentSubagentRuntime {
  private let limits: AgentSubagentLimits
  private let eventHook: AgentSubagentEventHook
  private let clock: () -> Int64
  private let lock = NSRecursiveLock()
  private var closed = false
  private var activeRuns: [String: AgentSubagentRunControl] = [:]

  init(
    limits: AgentSubagentLimits = AgentSubagentLimits(),
    eventHook: AgentSubagentEventHook = NoOpAgentSubagentEventHook(),
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.limits = limits
    self.eventHook = eventHook
    self.clock = clock
  }

  var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !closed
  }

  func activeSupervisorIds() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return Set(activeRuns.keys)
  }

  func start(
    plan: AgentSubagentPlan,
    worker: AgentSubagentWorker
  ) throws -> AgentSubagentRunHandle {
    let normalized = try normalizeAndValidate(plan)
    lock.lock()
    guard !closed else {
      lock.unlock()
      throw AgentSubagentRuntimeError.closed
    }
    guard activeRuns[normalized.supervisorId] == nil else {
      lock.unlock()
      throw AgentSubagentRuntimeError.duplicateSupervisor(normalized.supervisorId)
    }
    let control = AgentSubagentRunControl(supervisorId: normalized.supervisorId)
    let task = Task { [weak self, weak control] in
      guard let self, let control else {
        throw AgentSubagentRuntimeError.closed
      }
      defer { self.removeActiveRun(control.supervisorId, control: control) }
      return try await self.orchestrate(control: control, plan: normalized, worker: worker)
    }
    control.setTask(task)
    activeRuns[normalized.supervisorId] = control
    lock.unlock()
    return AgentSubagentRunHandle(
      supervisorId: normalized.supervisorId,
      task: task,
      control: control
    )
  }

  func execute(
    plan: AgentSubagentPlan,
    worker: AgentSubagentWorker
  ) async throws -> AgentSubagentRunResult {
    try await start(plan: plan, worker: worker).wait()
  }

  func close() {
    lock.lock()
    guard !closed else {
      lock.unlock()
      return
    }
    closed = true
    let controls = Array(activeRuns.values)
    lock.unlock()
    controls.forEach { $0.requestCancellation("Subagent runtime closed") }
  }

  func shutdown() async {
    lock.lock()
    let controls = Array(activeRuns.values)
    lock.unlock()
    close()
    for control in controls {
      await control.wait()
    }
  }

  private func orchestrate(
    control: AgentSubagentRunControl,
    plan: NormalizedPlan,
    worker: AgentSubagentWorker
  ) async throws -> AgentSubagentRunResult {
    let startedAt = now()
    let emitter = AgentSubagentEventEmitter(hook: eventHook, clock: clock)
    var results: [String: AgentSubagentChildResult] = [:]
    var remaining = Set(plan.children.map(\.childId))

    do {
      try await emitter.emit(
        supervisorId: plan.supervisorId,
        kind: AgentSubagentEventKinds.supervisorStarted,
        provenance: plan.provenance
      )
      for child in plan.children {
        try await emitter.emit(
          supervisorId: plan.supervisorId,
          childId: child.childId,
          kind: AgentSubagentEventKinds.childQueued,
          childStatus: .queued,
          provenance: child.provenance
        )
      }

      while !remaining.isEmpty {
        try Task.checkCancellation()
        let ready = plan.children.filter { child in
          remaining.contains(child.childId) && child.dependencies.allSatisfy { results[$0] != nil }
        }
        guard !ready.isEmpty else {
          throw AgentSubagentRuntimeError.invalid("Subagent dependency graph could not make progress")
        }
        let batch = Array(ready.prefix(limits.maxConcurrency))
        let batchResults = try await withThrowingTaskGroup(of: AgentSubagentChildResult.self) { group in
          for child in batch {
            let dependencies = child.dependencies.compactMap { results[$0] }
            group.addTask {
              try await self.executeChild(
                control: control,
                plan: plan,
                child: child,
                dependencies: dependencies,
                worker: worker,
                emitter: emitter
              )
            }
          }
          var collected: [AgentSubagentChildResult] = []
          for try await result in group {
            collected.append(result)
          }
          return collected
        }
        for result in batchResults {
          results[result.childId] = result
          remaining.remove(result.childId)
        }
        if plan.failurePolicy == .failFast,
          batchResults.contains(where: { $0.status == .failed }) {
          break
        }
      }

      if !remaining.isEmpty {
        for child in plan.children where remaining.contains(child.childId) {
          let result = terminalResult(
            plan: plan,
            child: child,
            status: .cancelled,
            errorMessage: control.cancellationMessage,
            startedAt: now()
          )
          results[child.childId] = result
          try? await emitter.emit(
            supervisorId: plan.supervisorId,
            childId: child.childId,
            kind: AgentSubagentEventKinds.childCancelled,
            childStatus: .cancelled,
            message: result.errorMessage,
            provenance: child.provenance,
            result: result
          )
        }
      }
      let result = aggregate(
        control: control,
        plan: plan,
        results: results,
        startedAt: startedAt,
        forceCancelled: control.isCancellationRequested
      )
      try await emitRunFinished(emitter: emitter, plan: plan, result: result)
      control.markCompleted()
      return result
    } catch is CancellationError {
      control.requestCancellation(control.cancellationMessage)
      for child in plan.children where results[child.childId] == nil {
        results[child.childId] = terminalResult(
          plan: plan,
          child: child,
          status: .cancelled,
          errorMessage: control.cancellationMessage,
          startedAt: now()
        )
      }
      let result = aggregate(control: control, plan: plan, results: results, startedAt: startedAt, forceCancelled: true)
      try? await emitRunFinished(emitter: emitter, plan: plan, result: result)
      control.markCompleted()
      return result
    } catch {
      control.markCompleted()
      throw error
    }
  }

  private func executeChild(
    control: AgentSubagentRunControl,
    plan: NormalizedPlan,
    child: NormalizedChild,
    dependencies: [AgentSubagentChildResult],
    worker: AgentSubagentWorker,
    emitter: AgentSubagentEventEmitter
  ) async throws -> AgentSubagentChildResult {
    let startedAt = now()
    try Task.checkCancellation()
    let unsuccessful = dependencies.filter { $0.status != .succeeded }
    if !unsuccessful.isEmpty && child.dependencyPolicy == .requireSuccess {
      let failedIds = unsuccessful.map(\.childId).sorted().joined(separator: ",")
      let result = terminalResult(
        plan: plan,
        child: child,
        status: .skipped,
        errorMessage: "Dependencies did not succeed: \(failedIds)",
        startedAt: startedAt
      )
      try await emitter.emit(
        supervisorId: plan.supervisorId,
        childId: child.childId,
        kind: AgentSubagentEventKinds.childSkipped,
        childStatus: .skipped,
        message: result.errorMessage,
        provenance: child.provenance,
        result: result
      )
      return result
    }

    try await emitter.emit(
      supervisorId: plan.supervisorId,
      childId: child.childId,
      kind: AgentSubagentEventKinds.childRunning,
      childStatus: .running,
      provenance: child.provenance
    )
    do {
      let output = try await worker.execute(context: AgentSubagentExecutionContext(
        supervisorId: plan.supervisorId,
        childId: child.childId,
        parentId: child.parentId,
        depth: child.depth,
        handoff: buildHandoff(child: child, dependencies: dependencies),
        provenance: child.provenance
      ))
      try Task.checkCancellation()
      let bounded = String(output.content.prefix(limits.maxOutputCharacters))
      let result = terminalResult(
        plan: plan,
        child: child,
        status: .succeeded,
        output: bounded,
        outputTruncated: bounded.count < output.content.count,
        startedAt: startedAt
      )
      try await emitter.emit(
        supervisorId: plan.supervisorId,
        childId: child.childId,
        kind: AgentSubagentEventKinds.childSucceeded,
        childStatus: .succeeded,
        provenance: child.provenance,
        result: result
      )
      return result
    } catch is CancellationError {
      let result = terminalResult(
        plan: plan,
        child: child,
        status: .cancelled,
        errorMessage: control.cancellationMessage,
        startedAt: startedAt
      )
      try? await emitter.emit(
        supervisorId: plan.supervisorId,
        childId: child.childId,
        kind: AgentSubagentEventKinds.childCancelled,
        childStatus: .cancelled,
        message: result.errorMessage,
        provenance: child.provenance,
        result: result
      )
      return result
    } catch {
      let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("Subagent failed")
      let result = terminalResult(
        plan: plan,
        child: child,
        status: .failed,
        errorMessage: message,
        startedAt: startedAt
      )
      try await emitter.emit(
        supervisorId: plan.supervisorId,
        childId: child.childId,
        kind: AgentSubagentEventKinds.childFailed,
        childStatus: .failed,
        message: result.errorMessage,
        provenance: child.provenance,
        result: result
      )
      return result
    }
  }

  private func buildHandoff(
    child: NormalizedChild,
    dependencies: [AgentSubagentChildResult]
  ) -> AgentSubagentContextHandoff {
    var remaining = limits.maxContextCharacters
    var truncated = false
    let context = String(child.context.prefix(max(remaining, 0)))
    remaining -= context.count
    truncated = context.count < child.context.count
    let handoffs = dependencies.sorted { $0.childId < $1.childId }.map { result in
      let output = String(result.output.prefix(max(remaining, 0)))
      remaining -= output.count
      let outputTruncated = result.outputTruncated || output.count < result.output.count
      truncated = truncated || outputTruncated
      return AgentSubagentDependencyHandoff(
        childId: result.childId,
        status: result.status,
        output: output,
        outputTruncated: outputTruncated,
        errorMessage: String(result.errorMessage.prefix(AgentSubagentChildResult.maxErrorCharacters)),
        provenance: result.provenance
      )
    }
    return AgentSubagentContextHandoff(
      context: context,
      dependencies: handoffs,
      usedCharacters: limits.maxContextCharacters - remaining,
      maxCharacters: limits.maxContextCharacters,
      truncated: truncated
    )
  }

  private func terminalResult(
    plan: NormalizedPlan,
    child: NormalizedChild,
    status: AgentSubagentStatus,
    output: String = "",
    outputTruncated: Bool = false,
    errorMessage: String = "",
    startedAt: Int64
  ) -> AgentSubagentChildResult {
    AgentSubagentChildResult(
      supervisorId: plan.supervisorId,
      childId: child.childId,
      parentId: child.parentId,
      depth: child.depth,
      status: status,
      output: output,
      outputTruncated: outputTruncated,
      errorMessage: errorMessage,
      provenance: child.provenance,
      startedAtMillis: startedAt,
      completedAtMillis: now()
    )
  }

  private func aggregate(
    control: AgentSubagentRunControl,
    plan: NormalizedPlan,
    results: [String: AgentSubagentChildResult],
    startedAt: Int64,
    forceCancelled: Bool
  ) -> AgentSubagentRunResult {
    let values = results.values.sorted { $0.childId < $1.childId }
    let status: AgentSubagentRunStatus
    if forceCancelled || control.isCancellationRequested {
      status = .cancelled
    } else if plan.failurePolicy == .failFast && values.contains(where: { $0.status == .failed }) {
      status = .failed
    } else if values.contains(where: { $0.status == .cancelled }) {
      status = .cancelled
    } else if values.contains(where: { $0.status == .failed || $0.status == .skipped }) {
      status = .completedWithFailures
    } else {
      status = .succeeded
    }
    return AgentSubagentRunResult(
      supervisorId: plan.supervisorId,
      status: status,
      results: values,
      provenance: plan.provenance,
      startedAtMillis: startedAt,
      completedAtMillis: now()
    )
  }

  private func emitRunFinished(
    emitter: AgentSubagentEventEmitter,
    plan: NormalizedPlan,
    result: AgentSubagentRunResult
  ) async throws {
    let kind: String
    switch result.status {
    case .succeeded: kind = AgentSubagentEventKinds.supervisorSucceeded
    case .completedWithFailures: kind = AgentSubagentEventKinds.supervisorCompletedWithFailures
    case .failed: kind = AgentSubagentEventKinds.supervisorFailed
    case .cancelled: kind = AgentSubagentEventKinds.supervisorCancelled
    }
    try await emitter.emit(
      supervisorId: plan.supervisorId,
      kind: kind,
      runStatus: result.status,
      provenance: plan.provenance
    )
  }

  private func normalizeAndValidate(_ plan: AgentSubagentPlan) throws -> NormalizedPlan {
    let supervisorId = try normalizeId(plan.supervisorId, field: "supervisorId")
    guard plan.children.count <= limits.maxChildren else {
      throw AgentSubagentRuntimeError.invalid("Supervisor \(supervisorId) exceeds maxChildren=\(limits.maxChildren)")
    }
    let children = try plan.children.map { child in
      let childId = try normalizeId(child.childId, field: "childId")
      guard childId != supervisorId else {
        throw AgentSubagentRuntimeError.invalid("Child ID must differ from supervisor ID")
      }
      let parentId = try child.parentId.map { try normalizeId($0, field: "parentId") } ?? supervisorId
      let dependencies = try child.dependencies.map { try normalizeId($0, field: "dependencyId") }.sorted()
      guard !dependencies.contains(childId) else {
        throw AgentSubagentRuntimeError.invalid("Child \(childId) cannot depend on itself")
      }
      return NormalizedChild(
        childId: childId,
        parentId: parentId,
        dependencies: dependencies,
        dependencyPolicy: child.dependencyPolicy,
        context: child.context,
        provenance: normalizeProvenance(child.provenance)
      )
    }.sorted { $0.childId < $1.childId }
    let byId = Dictionary(uniqueKeysWithValues: children.map { ($0.childId, $0) })
    guard byId.count == children.count else {
      throw AgentSubagentRuntimeError.invalid("Child IDs must be unique")
    }
    for child in children {
      guard child.parentId == supervisorId || byId[child.parentId] != nil else {
        throw AgentSubagentRuntimeError.invalid("Parent \(child.parentId) for child \(child.childId) does not exist")
      }
      for dependency in child.dependencies where byId[dependency] == nil {
        throw AgentSubagentRuntimeError.invalid("Dependency \(dependency) for child \(child.childId) does not exist")
      }
    }
    let depths = try calculateDepths(supervisorId: supervisorId, children: byId)
    try validateDependencyDAG(children: byId)
    return NormalizedPlan(
      supervisorId: supervisorId,
      children: children.map { $0.withDepth(depths[$0.childId] ?? 0) },
      failurePolicy: plan.failurePolicy,
      provenance: normalizeProvenance(plan.provenance)
    )
  }

  private func calculateDepths(
    supervisorId: String,
    children: [String: NormalizedChild]
  ) throws -> [String: Int] {
    var depths: [String: Int] = [:]
    var visiting: Set<String> = []
    func depth(_ childId: String) throws -> Int {
      if let value = depths[childId] { return value }
      guard visiting.insert(childId).inserted else {
        throw AgentSubagentRuntimeError.invalid("Subagent parent hierarchy contains a cycle at \(childId)")
      }
      guard let child = children[childId] else {
        throw AgentSubagentRuntimeError.invalid("Child \(childId) does not exist")
      }
      let value = child.parentId == supervisorId ? 1 : try depth(child.parentId) + 1
      visiting.remove(childId)
      guard value <= limits.maxDepth else {
        throw AgentSubagentRuntimeError.invalid("Child \(childId) exceeds maxDepth=\(limits.maxDepth)")
      }
      depths[childId] = value
      return value
    }
    for childId in children.keys.sorted() {
      _ = try depth(childId)
    }
    return depths
  }

  private func validateDependencyDAG(children: [String: NormalizedChild]) throws {
    var state: [String: Int] = [:]
    func visit(_ childId: String) throws {
      if state[childId] == 1 {
        throw AgentSubagentRuntimeError.invalid("Subagent dependency graph contains a cycle at \(childId)")
      }
      if state[childId] == 2 { return }
      state[childId] = 1
      for dependency in children[childId]?.dependencies ?? [] {
        try visit(dependency)
      }
      state[childId] = 2
    }
    for childId in children.keys.sorted() {
      try visit(childId)
    }
  }

  private func normalizeId(_ value: String, field: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw AgentSubagentRuntimeError.invalid("\(field) must not be blank")
    }
    guard normalized.count <= 160 else {
      throw AgentSubagentRuntimeError.invalid("\(field) exceeds 160 characters")
    }
    return normalized
  }

  private func normalizeProvenance(_ provenance: AgentSubagentProvenance) -> AgentSubagentProvenance {
    AgentSubagentProvenance(
      source: provenance.source.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("unspecified"),
      sourceId: provenance.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
      traceId: provenance.traceId.trimmingCharacters(in: .whitespacesAndNewlines),
      metadata: provenance.metadata
    )
  }

  private func now() -> Int64 {
    max(clock(), 0)
  }

  private func removeActiveRun(_ supervisorId: String, control: AgentSubagentRunControl) {
    lock.lock()
    if activeRuns[supervisorId] === control {
      activeRuns.removeValue(forKey: supervisorId)
    }
    lock.unlock()
  }
}

enum AgentSubagentRuntimeError: LocalizedError, Equatable {
  case closed
  case duplicateSupervisor(String)
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .closed: return "Agent subagent runtime is closed"
    case .duplicateSupervisor(let id): return "Supervisor \(id) already has an active run"
    case .invalid(let message): return message
    }
  }
}

private struct NormalizedPlan {
  var supervisorId: String
  var children: [NormalizedChild]
  var failurePolicy: AgentSubagentFailurePolicy
  var provenance: AgentSubagentProvenance
}

private struct NormalizedChild {
  var childId: String
  var parentId: String
  var dependencies: [String]
  var dependencyPolicy: AgentSubagentDependencyPolicy
  var context: String
  var provenance: AgentSubagentProvenance
  var depth: Int = 0

  func withDepth(_ value: Int) -> NormalizedChild {
    var copy = self
    copy.depth = value
    return copy
  }
}

fileprivate final class AgentSubagentRunControl {
  let supervisorId: String
  private let lock = NSRecursiveLock()
  private var task: Task<AgentSubagentRunResult, Error>?
  private var completed = false
  private var cancellationReason = ""

  init(supervisorId: String) {
    self.supervisorId = supervisorId
  }

  var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !completed
  }

  var isCancellationRequested: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !cancellationReason.isEmpty
  }

  var cancellationMessage: String {
    lock.lock()
    defer { lock.unlock() }
    return cancellationReason.ifBlank("Subagent child was cancelled")
  }

  func setTask(_ task: Task<AgentSubagentRunResult, Error>) {
    lock.lock()
    self.task = task
    lock.unlock()
  }

  @discardableResult
  func requestCancellation(_ reason: String) -> Bool {
    lock.lock()
    let firstRequest = cancellationReason.isEmpty
    if firstRequest {
      cancellationReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("Subagent supervisor cancellation requested")
    }
    let task = self.task
    lock.unlock()
    task?.cancel()
    return firstRequest
  }

  func markCompleted() {
    lock.lock()
    completed = true
    lock.unlock()
  }

  func wait() async {
    _ = try? await task?.value
  }
}

private actor AgentSubagentEventEmitter {
  private let hook: AgentSubagentEventHook
  private let clock: () -> Int64
  private var sequence: Int64 = 0

  init(hook: AgentSubagentEventHook, clock: @escaping () -> Int64) {
    self.hook = hook
    self.clock = clock
  }

  func emit(
    supervisorId: String,
    childId: String = "",
    kind: String,
    childStatus: AgentSubagentStatus? = nil,
    runStatus: AgentSubagentRunStatus? = nil,
    message: String = "",
    provenance: AgentSubagentProvenance,
    result: AgentSubagentChildResult? = nil
  ) async throws {
    sequence += 1
    try await hook.append(AgentSubagentEvent(
      sequence: sequence,
      supervisorId: supervisorId,
      childId: childId,
      kind: kind,
      childStatus: childStatus,
      runStatus: runStatus,
      message: String(message.prefix(AgentSubagentChildResult.maxErrorCharacters)),
      provenance: provenance,
      result: result,
      timestampMillis: max(clock(), 0)
    ))
  }
}
