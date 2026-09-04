import BackgroundTasks
import Combine
import Foundation

struct AgentProactiveBackgroundExecution: Equatable {
  let task: AgentProactiveTask
  let runId: String
  let scheduledForMillis: Int64
}

@MainActor
final class AgentProactiveBackgroundScheduler: ObservableObject {
  static let taskIdentifier = "com.galaxyssi.chat.ios.agent-refresh"

  private let store: GalaxySSIStore
  private let coordinator: MessageCoordinator
  private var registered = false
  private var taskObservation: AnyCancellable?

  init(store: GalaxySSIStore, coordinator: MessageCoordinator) {
    self.store = store
    self.coordinator = coordinator
    taskObservation = store.$proactiveTasks.sink { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.scheduleNext()
      }
    }
  }

  func start() {
    registerIfNeeded()
    scheduleNext()
  }

  func scheduleNext() {
    guard registered else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    guard let next = store.automationTasks()
      .filter({ $0.enabled && $0.nextRunAtMillis > 0 })
      .map(\.nextRunAtMillis)
      .min() else {
      return
    }

    let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
    request.earliestBeginDate = Date(
      timeIntervalSince1970: Double(max(next, now + 1_000)) / 1_000
    )
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // iOS can reject a request while Low Power Mode or system policy is active.
      return
    }
  }

  private func registerIfNeeded() {
    guard !registered else { return }
    registered = true
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
      Task { @MainActor [weak self] in
        self?.handle(task)
      }
    }
  }

  private func handle(_ task: BGTask) {
    task.expirationHandler = { }
    Task { @MainActor [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      let executions = self.store.claimDueAutomationExecutions()
      var success = true
      for execution in executions {
        let completed = await self.coordinator.executeProactiveTask(execution.task)
        self.store.finishAutomationRun(
          id: execution.runId,
          status: completed ? .completed : .failed,
          resultSummary: completed ? "Background Agent request submitted." : "Background Agent request failed.",
          errorCode: completed ? "" : "background_execution_failed"
        )
        success = success && completed
      }
      task.setTaskCompleted(success: success)
      self.scheduleNext()
    }
  }
}
