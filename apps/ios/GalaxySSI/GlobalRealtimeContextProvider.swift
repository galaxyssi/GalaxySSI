import Foundation

struct GlobalRealtimeContextProjection {
  var text: String
  var conversationIds: Set<String>
}

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
  private var refreshToken: UUID?

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
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    allowedConversationIds: Set<String>? = nil
  ) -> String {
    render(
      snapshot: loadSnapshot(nowMillis: nowMillis),
      query: query,
      currentConversationId: currentConversationId,
      excludedConversationIds: excludedConversationIds,
      excludedKeys: excludedKeys,
      maximumItems: maximumItems,
      maximumCharacters: maximumCharacters,
      nowMillis: nowMillis,
      allowedConversationIds: allowedConversationIds
    ).text
  }

  func buildProjection(query: String, currentConversationId: String,
    excludedConversationIds: Set<String>, allowedConversationIds: Set<String>,
    maximumItems: Int = GlobalRealtimeContextPolicy.defaultMaximumItems,
    maximumCharacters: Int = GlobalRealtimeContextPolicy.defaultMaximumCharacters,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> GlobalRealtimeContextProjection {
    render(snapshot: loadSnapshot(nowMillis: nowMillis), query: query,
      currentConversationId: currentConversationId, excludedConversationIds: excludedConversationIds,
      excludedKeys: [], maximumItems: maximumItems, maximumCharacters: maximumCharacters,
      nowMillis: nowMillis, allowedConversationIds: allowedConversationIds, captureConversationIds: true)
  }

  /// Returns the last complete snapshot immediately and refreshes stale state off the caller path.
  func buildNonBlocking(
    query: String,
    currentConversationId: String,
    excludedConversationIds: Set<String> = [],
    excludedKeys: Set<String> = [],
    maximumItems: Int = GlobalRealtimeContextPolicy.defaultMaximumItems,
    maximumCharacters: Int = GlobalRealtimeContextPolicy.defaultMaximumCharacters,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    allowedConversationIds: Set<String>? = nil
  ) -> String {
    let snapshot = cachedSnapshotSnapshot()
    let needsRefresh: Bool
    if let snapshot {
      let age = nowMillis.subtractingReportingOverflow(snapshot.capturedAtMillis)
      needsRefresh = age.overflow || age.partialValue < 0 || age.partialValue >= Self.snapshotTTLMillis
    } else { needsRefresh = true }
    if needsRefresh {
      refreshAsync(nowMillis: nowMillis)
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
      nowMillis: nowMillis,
      allowedConversationIds: allowedConversationIds
    ).text
  }

  func prewarm(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    refreshAsync(nowMillis: nowMillis)
  }

  func invalidate() {
    lock.lock()
    cachedSnapshot = nil
    refreshToken = nil
    lock.unlock()
  }

  private func render(
    snapshot: Snapshot,
    query: String,
    currentConversationId: String,
    excludedConversationIds: Set<String>,
    excludedKeys: Set<String>,
    maximumItems: Int,
    maximumCharacters: Int,
    nowMillis: Int64,
    allowedConversationIds: Set<String>? = nil,
    captureConversationIds: Bool = false
  ) -> GlobalRealtimeContextProjection {
    let researchTasks = allowedConversationIds == nil ? snapshot.researchTasks :
      snapshot.researchTasks.filter { $0.sourceConversationIds != nil }
    let autonomousRuns = allowedConversationIds == nil ? snapshot.autonomousRuns :
      snapshot.autonomousRuns.filter { $0.sourceConversationIds != nil }
    let allowedGoals = allowedConversationIds.map { allowed in
      snapshot.longHorizonGoals.filter { $0.sourceConversationIds.isSubset(of: allowed) }
    } ?? snapshot.longHorizonGoals
    let items = GlobalRealtimeContextPolicy.project(
      cognitionTasks: snapshot.cognitionTasks,
      researchTasks: researchTasks,
      autonomousRuns: autonomousRuns,
      longHorizonGoals: allowedGoals,
      excludedConversationIds: excludedConversationIds,
      nowMillis: nowMillis,
      continuitySnapshot: snapshot.continuitySnapshot
    )
    let selected = GlobalRealtimeContextPolicy.select(
      items: items.filter { item in
        allowedConversationIds.map { item.conversationIds.isSubset(of: $0) } ?? true
      },
      query: query,
      currentConversationId: currentConversationId,
      excludedKeys: excludedKeys,
      nowMillis: nowMillis,
      maximumItems: maximumItems
    )
    return GlobalRealtimeContextProjection(text: GlobalRealtimeContextPolicy.render(selected, maximumCharacters: maximumCharacters),
      conversationIds: captureConversationIds ? Set(selected.flatMap(\.conversationIds)) : [])
  }

  private func cachedSnapshotSnapshot() -> Snapshot? {
    lock.lock()
    defer { lock.unlock() }
    return cachedSnapshot
  }

  private func refreshAsync(nowMillis: Int64) {
    lock.lock()
    guard refreshToken == nil else {
      lock.unlock()
      return
    }
    let token = UUID()
    refreshToken = token
    lock.unlock()
    refreshQueue.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let current = self.refreshToken == token
      self.lock.unlock()
      guard current else { return }
      self.finishRefresh(self.loadSnapshot(nowMillis: nowMillis), token: token)
    }
  }

  private func finishRefresh(_ snapshot: Snapshot, token: UUID) {
    lock.lock()
    defer { lock.unlock() }
    guard refreshToken == token else { return }
    cachedSnapshot = snapshot
    refreshToken = nil
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
