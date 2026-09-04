import XCTest
@testable import GalaxySSI

final class AgentTaskCenterTests: XCTestCase {
  func testTerminalTaskOffersCompleteTaskCenterActions() {
    XCTAssertEqual(
      AgentTaskCenterPolicy.actions(task(phase: .completed)),
      [.retry, .copy, .viewLog, .delete]
    )
  }

  func testActiveTaskCannotBeDuplicatedOrDeletedFromHistory() {
    XCTAssertEqual(
      AgentTaskCenterPolicy.actions(task(phase: .executing)),
      [.copy, .viewLog]
    )
  }

  func testRedactedGoalCannotBeRetried() {
    let actions = AgentTaskCenterPolicy.actions(
      task(goal: "Sensitive goal withheld", phase: .failed)
    )

    XCTAssertFalse(actions.contains(.retry))
    XCTAssertTrue(actions.contains(.delete))
  }

  func testDeleteRemovesOnlySelectedTask() {
    let first = task(taskId: "task-1", sessionId: "shared-session")
    let second = task(taskId: "task-2", sessionId: "shared-session")
    let store = InMemoryTaskStore([first, second])
    let center = AgentTaskCenter(store: store)

    XCTAssertTrue(center.deleteTask(first.taskId))
    XCTAssertNil(store.find(first.taskId))
    XCTAssertEqual(store.find(second.taskId), second)
    XCTAssertFalse(center.deleteTask(first.taskId))
  }

  private func task(
    taskId: String = "task",
    sessionId: String = "conversation",
    goal: String = "Summarize the file",
    phase: AgentPhase = .completed
  ) -> AgentTaskRecord {
    AgentTaskRecord(
      taskId: taskId,
      sessionId: sessionId,
      goal: goal,
      phase: phase,
      routeKind: .desktopAgent,
      targetTitle: "Codex",
      risk: .low,
      blocked: false
    )
  }

  private final class InMemoryTaskStore: AgentTaskStore {
    private var records: [String: AgentTaskRecord]

    init(_ initial: [AgentTaskRecord]) {
      records = Dictionary(uniqueKeysWithValues: initial.map { ($0.taskId, $0) })
    }

    func upsert(_ record: AgentTaskRecord) {
      records[record.taskId] = record
    }

    func recent(limit: Int) -> [AgentTaskRecord] {
      Array(records.values.prefix(limit))
    }

    func forSession(_ sessionId: String, limit: Int) -> [AgentTaskRecord] {
      Array(records.values.filter { $0.sessionId == sessionId }.prefix(limit))
    }

    func find(_ taskId: String) -> AgentTaskRecord? {
      records[taskId]
    }

    func search(query: String, limit: Int) -> [AgentTaskRecord] {
      Array(records.values.filter { $0.goal.contains(query) }.prefix(limit))
    }

    func rebindSession(sourceSessionId: String, targetSessionId: String) -> Int {
      0
    }

    func delete(_ taskIds: Set<String>) {
      records = records.filter { entry in
        !taskIds.contains(entry.key) && !taskIds.contains(entry.value.sessionId)
      }
    }

    func deleteTask(_ taskId: String) {
      records.removeValue(forKey: taskId)
    }

    func clear() {
      records.removeAll()
    }
  }
}
