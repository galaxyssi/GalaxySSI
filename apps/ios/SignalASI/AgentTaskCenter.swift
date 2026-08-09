import Foundation

enum AgentTaskCenterAction: String, Codable, CaseIterable, Identifiable {
  case cancel = "CANCEL"
  case resume = "RESUME"
  case retry = "RETRY"
  case rollback = "ROLLBACK"
  case copy = "COPY"
  case viewLog = "VIEW_LOG"
  case delete = "DELETE"

  var id: String { rawValue }
}

protocol AgentTaskStore: AnyObject {
  func upsert(_ record: AgentTaskRecord)
  func recent(limit: Int) -> [AgentTaskRecord]
  func forSession(_ sessionId: String, limit: Int) -> [AgentTaskRecord]
  func find(_ taskId: String) -> AgentTaskRecord?
  func search(query: String, limit: Int) -> [AgentTaskRecord]
  func rebindSession(sourceSessionId: String, targetSessionId: String) -> Int
  func delete(_ taskIds: Set<String>)
  func deleteTask(_ taskId: String)
  func clear()
}

enum AgentTaskCenterPolicy {
  static func actions(_ task: AgentTaskRecord) -> [AgentTaskCenterAction] {
    var actions: [AgentTaskCenterAction] = []
    if resumable(task) {
      actions.append(.resume)
    }
    if cancellable(task) {
      actions.append(.cancel)
    }
    if terminalPhases.contains(task.phase), isReusableGoal(task.goal) {
      actions.append(.retry)
    }
    if rollbackAvailable(task) {
      actions.append(.rollback)
    }
    actions.append(.copy)
    actions.append(.viewLog)
    if terminalPhases.contains(task.phase) {
      actions.append(.delete)
    }
    return actions
  }

  static func cancellable(_ task: AgentTaskRecord) -> Bool {
    cancellablePhases.contains(task.phase) &&
      (task.pendingAction != nil || !task.pendingActions.isEmpty)
  }

  static func resumable(_ task: AgentTaskRecord) -> Bool {
    task.phase == .paused &&
      (task.pendingAction != nil || !task.pendingActions.isEmpty)
  }

  static func pauseable(_ task: AgentTaskRecord) -> Bool {
    [.planning, .waitingConfirmation, .executing, .verifying].contains(task.phase) &&
      (task.pendingAction != nil || !task.pendingActions.isEmpty)
  }

  static func isReusableGoal(_ goal: String) -> Bool {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    return !clean.isEmpty && clean != sensitiveGoalPlaceholder
  }

  static func rollbackAvailable(_ task: AgentTaskRecord) -> Bool {
    terminalPhases.contains(task.phase) && task.nativeRollbackAction != nil
  }

  private static let terminalPhases: Set<AgentPhase> = [.completed, .failed, .cancelled, .blocked]
  private static let cancellablePhases: Set<AgentPhase> = [
    .observing,
    .waitingConfirmation,
    .executing,
    .verifying,
    .waitingResponse,
    .paused
  ]
  private static let sensitiveGoalPlaceholder = "Sensitive goal withheld"
}

final class AgentTaskCenter {
  private let store: AgentTaskStore

  init(store: AgentTaskStore) {
    self.store = store
  }

  func deleteTask(_ taskId: String) -> Bool {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty, store.find(cleanTaskId) != nil else {
      return false
    }
    store.deleteTask(cleanTaskId)
    return store.find(cleanTaskId) == nil
  }
}
