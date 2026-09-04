import BackgroundTasks
import Foundation

enum AgentIOSCognitionWorkMode: Equatable {
  case event
  case scheduled
  case explicit
  case projection
}

struct AgentIOSCognitionWorkPlan: Equatable {
  var eventLimit: Int
  var runBatchCognition: Bool
  var cycleCount: Int
  var projectKnowledge: Bool
}

enum AgentIOSCognitionSchedulePolicy {
  static func workPlan(_ mode: AgentIOSCognitionWorkMode) -> AgentIOSCognitionWorkPlan {
    switch mode {
    case .event: return .init(eventLimit: 12, runBatchCognition: false, cycleCount: 0, projectKnowledge: false)
    case .scheduled: return .init(eventLimit: 48, runBatchCognition: true, cycleCount: 1, projectKnowledge: true)
    case .explicit: return .init(eventLimit: 200, runBatchCognition: true, cycleCount: 2, projectKnowledge: true)
    case .projection: return .init(eventLimit: 0, runBatchCognition: false, cycleCount: 0, projectKnowledge: true)
    }
  }

  static func nextExplorationDelayMillis(
    pendingEvents: Int,
    activeCognition: Int,
    activeResearch: Int,
    pendingInsights: Int
  ) -> Int64 {
    if pendingEvents > 0 || activeCognition > 0 || activeResearch > 0 { return minimumDelayMillis }
    if pendingInsights > 0 { return 30 * 60 * 1_000 }
    return maximumDelayMillis
  }

  static let minimumDelayMillis: Int64 = 10 * 60 * 1_000
  static let maximumDelayMillis: Int64 = 4 * 60 * 60 * 1_000
}

@MainActor
final class AgentIOSBackgroundCognitionScheduler {
  static let taskIdentifier = "com.signalasi.ios.cognition.refresh"

  private unowned let store: SignalASIStore
  private weak var coordinator: MessageCoordinator?
  private var registered = false

  init(store: SignalASIStore, coordinator: MessageCoordinator) {
    self.store = store
    self.coordinator = coordinator
  }

  func start() {
    registerIfNeeded()
    scheduleDynamic()
  }

  func scheduleDynamic() {
    guard registered, store.globalAgentSettings.enabled else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
      return
    }
    let cognition = GlobalAgentDeliberationStore().cognitionTasks().filter {
      [.queued, .running, .waitingForResource].contains($0.status)
    }.count
    let research = SignalASIGlobalAgentRuntimeBridge.researchState().tasks.filter {
      [.queued, .running, .scheduled, .waitingForResource].contains($0.status)
    }.count
    let delay = AgentIOSCognitionSchedulePolicy.nextExplorationDelayMillis(
      pendingEvents: 0,
      activeCognition: cognition,
      activeResearch: research,
      pendingInsights: store.globalProactiveInboxItems(limit: 100).filter { $0.isNew }.count
    )
    let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: Double(delay) / 1_000)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    try? BGTaskScheduler.shared.submit(request)
  }

  func run(_ mode: AgentIOSCognitionWorkMode) async -> Bool {
    guard mode == .projection || store.globalAgentSettings.enabled,
          let coordinator else { return false }
    let plan = AgentIOSCognitionSchedulePolicy.workPlan(mode)
    if plan.runBatchCognition {
      _ = SignalASIGlobalAgentRuntimeBridge.processLongHorizonCycle(store: store)
      _ = SignalASIGlobalAgentRuntimeBridge.processProactiveDiscoveryCycle(
        store: store,
        force: mode == .explicit
      )
      for _ in 0..<plan.cycleCount {
        guard !Task.isCancelled else { return false }
        _ = await coordinator.runGlobalCognitionCycle()
        _ = coordinator.runGlobalAutonomousCycle()
        _ = await coordinator.runGlobalResearchCycle()
      }
      _ = store.deliverPendingGlobalProactiveMessages()
    }
    if plan.projectKnowledge {
      _ = AgentIOSObsidianBridge.projectIncrementally(
        appStore: store,
        maximumWrites: mode == .projection ? 32 : 12
      )
    }
    scheduleDynamic()
    return !Task.isCancelled
  }

  private func registerIfNeeded() {
    guard !registered else { return }
    registered = true
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      let work = Task { @MainActor [weak self] in
        guard let self else {
          refresh.setTaskCompleted(success: false)
          return
        }
        let success = await self.run(.scheduled)
        refresh.setTaskCompleted(success: success)
      }
      refresh.expirationHandler = { work.cancel() }
    }
  }
}
