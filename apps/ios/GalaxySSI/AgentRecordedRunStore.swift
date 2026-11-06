import Foundation

final class AgentCompletionWorkQueue: @unchecked Sendable {
  static let shared = AgentCompletionWorkQueue()
  private let lock = NSLock()
  private var pending: Set<String> = []
  private var tail: Task<Void, Never>?

  @discardableResult
  func enqueue(runID: String, work: @escaping @Sendable () async throws -> Void) -> Bool {
    guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    lock.lock()
    defer { lock.unlock() }
    guard pending.insert(runID).inserted else { return false }
    let previous = tail
    tail = Task.detached(priority: .utility) { [self] in
      await previous?.value
      defer { finished(runID) }
      // Learning is advisory: a failed observation must not fail the completed tool result
      // or prevent later observations from running.
      do { try await work() } catch { }
    }
    return true
  }

  private func finished(_ runID: String) {
    lock.lock()
    defer { lock.unlock() }
    pending.remove(runID)
    if pending.isEmpty { tail = nil }
  }
}

protocol AgentRecordedRunStoring: AnyObject {
  func runs(for conversationId: String) -> [AgentRecordedRun]
  func upsert(_ run: AgentRecordedRun)
  func clear()
}

final class UserDefaultsAgentRecordedRunStore: AgentRecordedRunStoring {
  static let defaultKey = "galaxyssi-ios-agent-recorded-runs-v1"

  private let defaults: UserDefaults
  private let runEvents: UserDefaultsAgentRunEventStore
  private let key: String
  private let evalLifecycleObserver: ((AgentRecordedRun, AgentRecordedRun?) -> Void)?
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentRecordedRunStore.defaultKey,
    evalLifecycleObserver: ((AgentRecordedRun, AgentRecordedRun?) -> Void)? = nil
  ) {
    self.defaults = defaults
    self.runEvents = UserDefaultsAgentRunEventStore(defaults: defaults)
    self.key = key
    self.evalLifecycleObserver = evalLifecycleObserver
  }

  func runs(for conversationId: String = "") -> [AgentRecordedRun] {
    locked {
      let requested = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
      let all = decode(defaults.string(forKey: key) ?? "[]")
      return all
        .filter { requested.isEmpty || $0.conversationId == requested }
        .sorted { $0.completedAtMillis < $1.completedAtMillis }
    }
  }

  func upsert(_ run: AgentRecordedRun) {
    let previous = locked { () -> AgentRecordedRun? in
      let current = decode(defaults.string(forKey: key) ?? "[]")
      let previous = current.first { $0.runId == run.runId }
      let replaced = current.filter { $0.runId != run.runId }
      defaults.set(encode(Array((replaced + [run]).suffix(Self.maxRuns))), forKey: key)
      return previous
    }
    evalLifecycleObserver?(run, previous)
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: key)
    }
  }

  private func decode(_ raw: String) -> [AgentRecordedRun] {
    guard let data = raw.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([AgentRecordedRun].self, from: data)) ?? []
  }

  private func encode(_ runs: [AgentRecordedRun]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(runs) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  private static let maxRuns = 128
}

extension UserDefaultsAgentRecordedRunStore {
  func recordNativeExecution(
    _ observations: [AgentRecordedExecutionEvidence.Observation] = [],
    task: AgentTaskRecord,
    outgoing: ChatMessage,
    status: AgentRecordedRunStatus,
    events: AgentRunEventPersistence? = nil
  ) {
    let events = events ?? runEvents
    let now = max(task.updatedAtMillis, Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    let runId = task.taskId.ifBlank(outgoing.turnId.ifBlank(outgoing.id.uuidString))
    let scope = AgentPlanContinuationScope(conversationId: outgoing.conversationId,
      turnId: outgoing.turnId.ifBlank(outgoing.id.uuidString))
    let previous = runs().first { $0.runId == runId }
    guard outgoing.isMine, !scope.conversationId.isBlank,
          task.sessionId.isBlank || task.sessionId == scope.conversationId,
          task.taskId.isBlank || task.taskId == scope.turnId || task.taskId == outgoing.id.uuidString,
          previous == nil || previous?.conversationId == scope.conversationId
    else { return }
    let projection = AgentRecordedExecutionEvidence.project(task: task, scope: scope,
      previous: previous?.toolCalls ?? [], observations: observations, now: now)
    guard !projection.calls.isEmpty else { return }
    var run = previous
      ?? AgentRecordedRun(
        runId: runId,
        conversationId: scope.conversationId,
        taskThreadId: task.sessionId.ifBlank(runId),
        originalRequest: task.goal.ifBlank(outgoing.content),
        createdAtMillis: max(0, task.createdAtMillis)
      )
    run.agentPlan = projection.plan
    run.toolCalls = projection.calls
    run.finalOutput = ["message": .string(String(task.result.prefix(2_000)))]
    let unresolved = projection.calls.contains { $0.result["outcome_unverified"]?.boolValue == true }
    run.status = unresolved && status != .cancelled ? .running : status
    run.completedAtMillis = run.status == .running ? 0 :
      (previous?.status == run.status ? previous?.completedAtMillis ?? now : now)
    let missing = AgentRecordedExecutionEvidence.missingLifecycle(for: projection.calls,
      events: events.events(runId: runId), scope: scope)
    if !missing.isEmpty { _ = events.appendNextAll(missing) }
    if previous != run { upsert(run) }
  }

  func recordSkillExecution(
    match: AgentSkillMatch,
    result: AgentSkillExecutionResult,
    request: String,
    conversationId: String,
    taskId: String,
    nowMillis: Int64 = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  ) {
    let runId = taskId.ifBlank(UUID().uuidString)
    let calls = result.toolResults.enumerated().map { index, toolResult in
      AgentToolCallRecord(
        id: runId + "-skill-" + String(index + 1),
        toolName: toolResult.provenance.toolId,
        status: toolResult.isSuccess ? .succeeded : .failed,
        arguments: [:],
        result: toolResult.output,
        errorMessage: toolResult.isSuccess ? "" : toolResult.message,
        startedAtMillis: max(0, nowMillis),
        completedAtMillis: max(0, nowMillis)
      )
    }
    upsert(AgentRecordedRun(
      runId: runId,
      conversationId: conversationId,
      taskThreadId: taskId.ifBlank(runId),
      originalRequest: request,
      toolCalls: calls,
      finalOutput: ["message": .string(String(result.message.prefix(2_000)))],
      activeSkillId: match.installation.id,
      status: result.success ? .completed : .failed,
      createdAtMillis: max(0, nowMillis),
      completedAtMillis: max(0, nowMillis)
    ))
  }
}
