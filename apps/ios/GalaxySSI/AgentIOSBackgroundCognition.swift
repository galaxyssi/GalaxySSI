import BackgroundTasks
import Combine
import Foundation
import os

private let agentIOSCognitionLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "com.galaxyssi.chat.ios",
  category: "cognition"
)

enum AgentIOSCognitionWorkMode: Equatable {
  case event
  case foreground
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
  static func allows(_ mode: AgentIOSCognitionWorkMode, learningEnabled: Bool) -> Bool {
    learningEnabled || mode == .projection
  }

  static func allowsTransport(_ item: PendingLinkMessage, learningEnabled: Bool,
                              legacySources: Set<String> = []) -> Bool {
    learningEnabled || !isLearningTransport(item, legacySources: legacySources)
  }

  static func isLearningTransport(_ item: PendingLinkMessage, legacySources: Set<String>) -> Bool {
    item.backgroundLearning ?? legacySources.contains(item.clientSourceMessageId)
  }

  static func workPlan(_ mode: AgentIOSCognitionWorkMode) -> AgentIOSCognitionWorkPlan {
    switch mode {
    case .event: return .init(eventLimit: 12, runBatchCognition: false, cycleCount: 0, projectKnowledge: false)
    case .foreground: return .init(eventLimit: 12, runBatchCognition: true, cycleCount: 1, projectKnowledge: false)
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
  static let taskIdentifier = "com.galaxyssi.ios.cognition.refresh"

  private unowned let store: GalaxySSIStore
  private weak var coordinator: MessageCoordinator?
  private var registered = false
  private var settingsObservation: AnyCancellable?
  private var learningWork: (id: UUID, task: Task<Bool, Never>)?

  init(store: GalaxySSIStore, coordinator: MessageCoordinator) {
    self.store = store
    self.coordinator = coordinator
    settingsObservation = store.$globalAgentSettings.map(\.enabled).removeDuplicates().dropFirst().sink { [weak self] enabled in
      guard let self else { return }
      if enabled {
        // Published settings emit before the new value is committed to the store.
        Task { @MainActor [weak self] in
          guard let self, self.store.globalAgentSettings.enabled else { return }
          self.coordinator?.scheduleOutboxFlushFromStore()
          self.scheduleDynamic()
        }
      } else {
        self.cancelLearning()
        self.coordinator?.pausedLegacyLearningSourceIDs = nil
        Task { @MainActor [weak self] in self?.coordinator?.scheduleOutboxFlushFromStore() }
      }
    }
  }

  func start() {
    registerIfNeeded()
    scheduleDynamic()
  }

  func scheduleDynamic() {
    guard registered else { return }
    guard store.globalAgentSettings.enabled else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
      return
    }
    let cognition = GlobalAgentDeliberationStore().cognitionTasks().filter {
      [.queued, .running, .waitingForResource].contains($0.status)
    }.count
    let research = GalaxySSIGlobalAgentRuntimeBridge.researchState().tasks.filter {
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

  func requestForegroundCycle() {
    guard store.globalAgentSettings.enabled else { return }
    _ = startLearning(.foreground)
  }

  func run(_ mode: AgentIOSCognitionWorkMode) async -> Bool {
    guard !Task.isCancelled, AgentIOSCognitionSchedulePolicy.allows(mode, learningEnabled: store.globalAgentSettings.enabled)
    else { return false }
    if mode == .projection { return await perform(mode) }
    guard let task = startLearning(mode) else { return false }
    return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
  }

  private func startLearning(_ mode: AgentIOSCognitionWorkMode) -> Task<Bool, Never>? {
    guard learningWork == nil, store.globalAgentSettings.enabled else { return nil }
    let id = UUID()
    let task = Task { @MainActor [weak self] in
      guard let self else { return false }
      defer { if self.learningWork?.id == id { self.learningWork = nil } }
      return await self.perform(mode)
    }
    learningWork = (id, task)
    return task
  }

  private func cancelLearning() {
    learningWork?.task.cancel()
    if registered { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier) }
  }

  private func mayContinue(_ mode: AgentIOSCognitionWorkMode) -> Bool {
    !Task.isCancelled && AgentIOSCognitionSchedulePolicy.allows(mode, learningEnabled: store.globalAgentSettings.enabled)
  }

  private func perform(_ mode: AgentIOSCognitionWorkMode) async -> Bool {
    let startedAt = ProcessInfo.processInfo.systemUptime
    let modeName = String(describing: mode)
    guard mayContinue(mode), let coordinator else {
      agentIOSCognitionLogger.info(
        "run_skipped mode=\(modeName, privacy: .public) reason=disabled_or_unavailable elapsed_ms=\(self.elapsedMillis(since: startedAt))"
      )
      return false
    }
    let plan = AgentIOSCognitionSchedulePolicy.workPlan(mode)
    var projection = AgentIOSObsidianProjectionResult(configured: false)
    if plan.runBatchCognition {
      _ = GalaxySSIGlobalAgentRuntimeBridge.processLongHorizonCycle(store: store)
      _ = GalaxySSIGlobalAgentRuntimeBridge.processProactiveDiscoveryCycle(
        store: store,
        force: mode == .explicit
      )
      for _ in 0..<plan.cycleCount {
        guard mayContinue(mode) else {
          agentIOSCognitionLogger.info(
            "run_cancelled mode=\(modeName, privacy: .public) elapsed_ms=\(self.elapsedMillis(since: startedAt))"
          )
          return false
        }
        _ = await coordinator.runGlobalCognitionCycle()
        guard mayContinue(mode) else { return false }
        _ = await coordinator.runGlobalAutonomousCycle()
        guard mayContinue(mode) else { return false }
        _ = await coordinator.runGlobalResearchCycle()
      }
      guard mayContinue(mode) else { return false }
      _ = store.deliverPendingGlobalProactiveMessages()
    }
    guard mayContinue(mode) else { return false }
    if plan.projectKnowledge {
      projection = AgentIOSObsidianBridge.projectIncrementally(
        appStore: store,
        maximumWrites: mode == .projection ? 32 : 12
      )
    }
    if mode != .projection { scheduleDynamic() }
    let completed = !Task.isCancelled
    agentIOSCognitionLogger.info(
      "run_complete mode=\(modeName, privacy: .public) elapsed_ms=\(self.elapsedMillis(since: startedAt)) projection_configured=\(projection.configured) projection_written=\(projection.writtenCount) projection_unchanged=\(projection.unchangedCount) projection_candidates=\(projection.candidateCount) projection_remaining=\(projection.remainingCount) cancelled=\(!completed)"
    )
    return completed
  }

  private func elapsedMillis(since startedAt: TimeInterval) -> Int64 {
    max(0, Int64((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000))
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
        guard self.store.globalAgentSettings.enabled else {
          refresh.setTaskCompleted(success: true)
          return
        }
        let success = await self.run(.scheduled)
        refresh.setTaskCompleted(success: success)
      }
      refresh.expirationHandler = { work.cancel() }
    }
  }
}
