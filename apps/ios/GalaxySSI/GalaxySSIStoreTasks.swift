import Foundation

extension GalaxySSIStore {
  func recentAgentTasks(limit: Int = 20) -> [AgentTaskRecord] {
    mergedAgentTaskRecords()
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func refreshAgentRuntimeState() {
    objectWillChange.send()
  }

  func searchAgentTasks(_ query: String, limit: Int = 50) -> [AgentTaskRecord] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return recentAgentTasks(limit: limit)
    }
    return mergedAgentTaskRecords()
      .filter { task in
        [
          task.goal,
          task.taskId,
          task.sessionId,
          task.targetTitle,
          task.routeKind.rawValue,
          task.phase.rawValue,
          task.result,
          task.verification,
          task.outputFiles.joined(separator: " "),
          task.executionLog.joined(separator: " ")
        ].contains {
          $0.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func agentTasks(forSession sessionId: String, limit: Int = 50) -> [AgentTaskRecord] {
    let clean = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return mergedAgentTaskRecords()
      .filter { $0.sessionId == clean }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func agentTask(id taskId: String) -> AgentTaskRecord? {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return mergedAgentTaskRecords().first { $0.taskId == clean }
  }
}
