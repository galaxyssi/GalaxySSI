import Foundation

protocol AgentRecordedRunStoring: AnyObject {
  func runs(for conversationId: String) -> [AgentRecordedRun]
  func upsert(_ run: AgentRecordedRun)
  func clear()
}

final class UserDefaultsAgentRecordedRunStore: AgentRecordedRunStoring {
  static let defaultKey = "galaxyssi-ios-agent-recorded-runs-v1"

  private let defaults: UserDefaults
  private let key: String
  private let evalLifecycleObserver: ((AgentRecordedRun, AgentRecordedRun?) -> Void)?
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentRecordedRunStore.defaultKey,
    evalLifecycleObserver: ((AgentRecordedRun, AgentRecordedRun?) -> Void)? = nil
  ) {
    self.defaults = defaults
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
  func recordNativeAction(
    action: AgentAction,
    result: AgentActionResult,
    task: AgentTaskRecord,
    outgoing: ChatMessage,
    final: Bool
  ) {
    let now = max(task.updatedAtMillis, Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    let runId = task.taskId.ifBlank(outgoing.turnId.ifBlank(outgoing.id.uuidString))
    let toolId = action.parameters["tool_id"] ?? action.target
    let call = AgentToolCallRecord(
      id: runId + "-" + toolId + "-" + String(task.executionLog.count),
      toolName: toolId,
      status: result.success ? .succeeded : .failed,
      arguments: inputObject(from: action),
      result: resultObject(from: result),
      errorMessage: result.success ? "" : result.message,
      startedAtMillis: max(0, now),
      completedAtMillis: max(0, now)
    )
    var run = runs(for: outgoing.conversationId).first { $0.runId == runId }
      ?? AgentRecordedRun(
        runId: runId,
        conversationId: outgoing.conversationId,
        taskThreadId: task.sessionId.ifBlank(runId),
        originalRequest: task.goal.ifBlank(outgoing.content),
        createdAtMillis: max(0, task.createdAtMillis)
      )
    run.toolCalls = Array((run.toolCalls + [call]).suffix(AgentSkillLimits.maxToolCalls))
    run.finalOutput = ["message": .string(String(result.message.prefix(2_000)))]
    run.status = final ? (result.success ? .completed : .failed) : .running
    run.completedAtMillis = final ? max(0, now) : 0
    upsert(run)
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

  private func inputObject(from action: AgentAction) -> AgentMcpJSONObject {
    guard let raw = action.parameters["input_json"],
          let data = raw.data(using: .utf8),
          let input = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return [:]
    }
    return input
  }

  private func resultObject(from result: AgentActionResult) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "success": .bool(result.success),
      "message": .string(String(result.message.prefix(2_000)))
    ]
    if let raw = result.metadata["native_tool_output"],
       let data = raw.data(using: .utf8),
       let output = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) {
      object["output"] = .object(output)
    }
    return object
  }
}
