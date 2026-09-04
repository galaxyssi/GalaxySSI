import Foundation

final class GlobalRealtimeContextProvider {
  private struct Snapshot {
    var cognitionTasks: [GlobalCognitionTask]
    var researchTasks: [GlobalResearchTask]
    var autonomousRuns: [GlobalAutonomousRun]
    var longHorizonGoals: [GlobalLongHorizonGoal]
    var continuitySnapshot: GlobalAgentContinuitySnapshot?
    var capturedAtMillis: Int64
  }

  private let cognitionTasksSource: () -> [GlobalCognitionTask]
  private let researchTasksSource: () -> [GlobalResearchTask]
  private let autonomousRunsSource: () -> [GlobalAutonomousRun]
  private let longHorizonGoalsSource: () -> [GlobalLongHorizonGoal]
  private let continuitySource: () -> GlobalAgentContinuitySnapshot?
  private let refreshQueue: DispatchQueue
  private let lock = NSLock()
  private var cachedSnapshot: Snapshot?
  private var refreshInProgress = false

  init(
    cognitionTasksSource: @escaping () -> [GlobalCognitionTask] = { GlobalAgentDeliberationStore().cognitionTasks() },
    researchTasksSource: @escaping () -> [GlobalResearchTask] = { [] },
    autonomousRunsSource: @escaping () -> [GlobalAutonomousRun] = { GlobalAgentDeliberationStore().autonomousRuns() },
    longHorizonGoalsSource: @escaping () -> [GlobalLongHorizonGoal] = { GlobalLongHorizonGoalStore().goals() },
    continuitySource: @escaping () -> GlobalAgentContinuitySnapshot? = { nil },
    refreshQueue: DispatchQueue = DispatchQueue(
      label: "galaxyssi.global-realtime-context",
      qos: .utility
    )
  ) {
    self.cognitionTasksSource = cognitionTasksSource
    self.researchTasksSource = researchTasksSource
    self.autonomousRunsSource = autonomousRunsSource
    self.longHorizonGoalsSource = longHorizonGoalsSource
    self.continuitySource = continuitySource
    self.refreshQueue = refreshQueue
  }

  func build(
    query: String,
    currentConversationId: String,
    excludedConversationIds: Set<String> = [],
    excludedKeys: Set<String> = [],
    maximumItems: Int = GlobalRealtimeContextPolicy.defaultMaximumItems,
    maximumCharacters: Int = GlobalRealtimeContextPolicy.defaultMaximumCharacters,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> String {
    render(
      snapshot: loadSnapshot(nowMillis: nowMillis),
      query: query,
      currentConversationId: currentConversationId,
      excludedConversationIds: excludedConversationIds,
      excludedKeys: excludedKeys,
      maximumItems: maximumItems,
      maximumCharacters: maximumCharacters,
      nowMillis: nowMillis
    )
  }

  /// Returns the last complete snapshot immediately and refreshes stale state off the caller path.
  func buildNonBlocking(
    query: String,
    currentConversationId: String,
    excludedConversationIds: Set<String> = [],
    excludedKeys: Set<String> = [],
    maximumItems: Int = GlobalRealtimeContextPolicy.defaultMaximumItems,
    maximumCharacters: Int = GlobalRealtimeContextPolicy.defaultMaximumCharacters,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> String {
    let snapshot = cachedSnapshotSnapshot()
    if snapshot == nil || nowMillis - snapshot!.capturedAtMillis >= Self.snapshotTTLMillis {
      refreshAsync()
    }
    guard let snapshot else { return "" }
    return render(
      snapshot: snapshot,
      query: query,
      currentConversationId: currentConversationId,
      excludedConversationIds: excludedConversationIds,
      excludedKeys: excludedKeys,
      maximumItems: maximumItems,
      maximumCharacters: maximumCharacters,
      nowMillis: nowMillis
    )
  }

  func prewarm(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    refreshNow(nowMillis: nowMillis)
  }

  private func render(
    snapshot: Snapshot,
    query: String,
    currentConversationId: String,
    excludedConversationIds: Set<String>,
    excludedKeys: Set<String>,
    maximumItems: Int,
    maximumCharacters: Int,
    nowMillis: Int64
  ) -> String {
    let items = GlobalRealtimeContextPolicy.project(
      cognitionTasks: snapshot.cognitionTasks,
      researchTasks: snapshot.researchTasks,
      autonomousRuns: snapshot.autonomousRuns,
      longHorizonGoals: snapshot.longHorizonGoals,
      excludedConversationIds: excludedConversationIds,
      nowMillis: nowMillis,
      continuitySnapshot: snapshot.continuitySnapshot
    )
    let selected = GlobalRealtimeContextPolicy.select(
      items: items,
      query: query,
      currentConversationId: currentConversationId,
      excludedKeys: excludedKeys,
      nowMillis: nowMillis,
      maximumItems: maximumItems
    )
    return GlobalRealtimeContextPolicy.render(selected, maximumCharacters: maximumCharacters)
  }

  private func cachedSnapshotSnapshot() -> Snapshot? {
    lock.lock()
    defer { lock.unlock() }
    return cachedSnapshot
  }

  private func refreshAsync() {
    lock.lock()
    guard !refreshInProgress else {
      lock.unlock()
      return
    }
    refreshInProgress = true
    lock.unlock()
    refreshQueue.async { [weak self] in
      guard let self else { return }
      self.finishRefresh(self.loadSnapshot(nowMillis: GlobalRealtimeClock.nowMillis()))
    }
  }

  private func refreshNow(nowMillis: Int64) {
    lock.lock()
    guard !refreshInProgress else {
      lock.unlock()
      return
    }
    refreshInProgress = true
    lock.unlock()
    finishRefresh(loadSnapshot(nowMillis: nowMillis))
  }

  private func finishRefresh(_ snapshot: Snapshot) {
    lock.lock()
    cachedSnapshot = snapshot
    refreshInProgress = false
    lock.unlock()
  }

  private func loadSnapshot(nowMillis: Int64) -> Snapshot {
    Snapshot(
      cognitionTasks: cognitionTasksSource(),
      researchTasks: researchTasksSource(),
      autonomousRuns: autonomousRunsSource(),
      longHorizonGoals: longHorizonGoalsSource(),
      continuitySnapshot: continuitySource(),
      capturedAtMillis: nowMillis
    )
  }

  private static let snapshotTTLMillis: Int64 = 15_000
}
