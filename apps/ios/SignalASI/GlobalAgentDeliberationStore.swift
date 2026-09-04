import Foundation

struct GlobalAutonomousWorkClaim: Codable, Equatable {
  var run: GlobalAutonomousRun
  var actionId: String
  var planReview: Bool

  init(
    run: GlobalAutonomousRun,
    actionId: String = "",
    planReview: Bool = false
  ) {
    self.run = run
    self.actionId = actionId
    self.planReview = planReview
  }

  enum CodingKeys: String, CodingKey {
    case run
    case actionId = "action_id"
    case planReview = "plan_review"
  }
}

enum GlobalCognitionTaskPolicy {
  static func selectionScore(_ task: GlobalCognitionTask, nowMillis: Int64) -> Int64 {
    let understanding = task.baselineUnderstanding
    let ageMillis = max(nowMillis - task.createdAtMillis, 0)
    let freshBonus = min(max(sixHoursMillis - ageMillis, 0) / 60_000, 360)
    let agingBonus = min(ageMillis / dayMillis, 30) * 12
    return Int64(understanding.urgency * 320) +
      Int64(understanding.complexity * 180) +
      (understanding.durableFollowUpUseful ? 220 : 0) +
      (understanding.externalResearchUseful ? 140 : 0) +
      (understanding.riskCandidates.isEmpty ? 0 : 180) +
      (understanding.opportunityCandidates.isEmpty ? 0 : 100) +
      (task.longHorizonGoalId.isBlank ? 0 : 240) +
      (task.sourceEvent.metadata["origin"] == GlobalProactiveDiscoveryPolicy.origin ? 260 : 0) +
      (task.sourceEvent.actor == .user && task.sourceEvent.type == .messageCreated ? 520 : 0) +
      (task.status == .queued ? 100 : 0) +
      freshBonus + agingBonus - Int64(min(task.attemptCount, 8) * 45)
  }

  static func recoverIfStale(
    _ task: GlobalCognitionTask,
    nowMillis: Int64
  ) -> GlobalCognitionTask {
    guard task.status == .running,
          task.leaseExpiresAtMillis > 0,
          task.leaseExpiresAtMillis <= nowMillis else {
      return task
    }
    var recovered = task
    recovered.status = .waitingForResource
    recovered.attemptedResourceIds = distinctStrings(task.attemptedResourceIds + [task.resourceId])
    recovered.sourceMessageId = 0
    recovered.nextAttemptAtMillis = max(nowMillis, 0)
    recovered.leaseExpiresAtMillis = 0
    recovered.lastError = "The previous cognition lease expired before a result arrived"
    recovered.updatedAtMillis = max(nowMillis, 0)
    return recovered
  }

  static func retryDelayMillis(attemptCount: Int) -> Int64 {
    switch max(attemptCount, 1) {
    case 1: return 15_000
    case 2: return 60_000
    default: return 5 * 60 * 1_000
    }
  }

  private static func distinctStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
      result.append(clean)
    }
    return result
  }

  static let leaseMillis: Int64 = 4 * 60 * 1_000
  static let maxAttempts = 3
  private static let sixHoursMillis: Int64 = 6 * 60 * 60 * 1_000
  private static let dayMillis: Int64 = 24 * 60 * 60 * 1_000
}

final class GlobalAgentDeliberationStore {
  private struct Snapshot: Codable {
    var formatVersion: Int
    var cognitionTasks: [GlobalCognitionTask]
    var autonomousRuns: [GlobalAutonomousRun]
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private(set) var lastErrorDescription: String = ""

  init(
    fileURL: URL = GlobalAgentDeliberationStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("global-deliberation", isDirectory: true)
      .appendingPathComponent("state.json", isDirectory: false)
  }

  static func destroyPersistentStore(
    fileURL: URL = GlobalAgentDeliberationStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(at: fileURL)
  }

  func cognitionTasks() -> [GlobalCognitionTask] {
    locked { load().cognitionTasks }
  }

  func saveCognitionTasks(_ tasks: [GlobalCognitionTask]) {
    locked {
      var snapshot = load()
      snapshot.cognitionTasks = boundedCognition(tasks)
      persist(snapshot)
    }
  }

  func upsertCognitionTask(_ task: GlobalCognitionTask) {
    locked {
      var snapshot = load()
      snapshot.cognitionTasks.removeAll { $0.id == task.id }
      snapshot.cognitionTasks.append(task)
      snapshot.cognitionTasks = boundedCognition(snapshot.cognitionTasks)
      persist(snapshot)
    }
  }

  @discardableResult
  func updateCognitionTask(
    taskId: String,
    transform: (GlobalCognitionTask) -> GlobalCognitionTask
  ) -> GlobalCognitionTask? {
    locked {
      var snapshot = load()
      guard let index = snapshot.cognitionTasks.firstIndex(where: { $0.id == taskId }) else {
        return nil
      }
      let updated = transform(snapshot.cognitionTasks[index])
      snapshot.cognitionTasks[index] = updated
      snapshot.cognitionTasks = boundedCognition(snapshot.cognitionTasks)
      persist(snapshot)
      return updated
    }
  }

  func claimCognitionTask(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> GlobalCognitionTask? {
    locked {
      var snapshot = load()
      var tasks = snapshot.cognitionTasks.map {
        GlobalCognitionTaskPolicy.recoverIfStale($0, nowMillis: nowMillis)
      }
      let index = tasks.indices
        .filter {
          [.queued, .waitingForResource].contains(tasks[$0].status) &&
            tasks[$0].nextAttemptAtMillis <= nowMillis
        }
        .max { left, right in
          GlobalCognitionTaskPolicy.selectionScore(tasks[left], nowMillis: nowMillis) <
            GlobalCognitionTaskPolicy.selectionScore(tasks[right], nowMillis: nowMillis)
        }
      guard let index else {
        snapshot.cognitionTasks = boundedCognition(tasks)
        persist(snapshot)
        return nil
      }
      var claimed = tasks[index]
      claimed.status = .running
      claimed.attemptCount += 1
      claimed.sourceMessageId = 0
      claimed.leaseExpiresAtMillis = max(nowMillis, 0) + GlobalCognitionTaskPolicy.leaseMillis
      claimed.updatedAtMillis = max(nowMillis, 0)
      tasks[index] = claimed
      snapshot.cognitionTasks = boundedCognition(tasks)
      persist(snapshot)
      return claimed
    }
  }

  func autonomousRuns() -> [GlobalAutonomousRun] {
    locked { load().autonomousRuns }
  }

  func saveAutonomousRuns(_ runs: [GlobalAutonomousRun]) {
    locked {
      var snapshot = load()
      snapshot.autonomousRuns = boundedRuns(runs)
      persist(snapshot)
    }
  }

  func upsertAutonomousRun(_ run: GlobalAutonomousRun) {
    locked {
      var snapshot = load()
      snapshot.autonomousRuns.removeAll { $0.id == run.id }
      snapshot.autonomousRuns.append(run)
      snapshot.autonomousRuns = boundedRuns(snapshot.autonomousRuns)
      persist(snapshot)
    }
  }

  @discardableResult
  func updateAutonomousRun(
    runId: String,
    transform: (GlobalAutonomousRun) -> GlobalAutonomousRun
  ) -> GlobalAutonomousRun? {
    locked {
      var snapshot = load()
      guard let index = snapshot.autonomousRuns.firstIndex(where: { $0.id == runId }) else {
        return nil
      }
      let updated = transform(snapshot.autonomousRuns[index])
      snapshot.autonomousRuns[index] = updated
      snapshot.autonomousRuns = boundedRuns(snapshot.autonomousRuns)
      persist(snapshot)
      return updated
    }
  }

  func claimAutonomousWork(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> GlobalAutonomousWorkClaim? {
    locked {
      var snapshot = load()
      var runs = snapshot.autonomousRuns.map {
        GlobalAutonomousRunPolicy.recoverIfStale(run: $0, nowMillis: nowMillis)
      }
      guard let index = runs.firstIndex(where: { run in
        reviewReady(run, nowMillis: nowMillis) || actionReady(run, nowMillis: nowMillis)
      }) else {
        snapshot.autonomousRuns = boundedRuns(runs)
        persist(snapshot)
        return nil
      }
      let source = runs[index]
      let lease = max(nowMillis, 0) + GlobalAutonomousRunPolicy.leaseMillis
      let isReviewReady = reviewReady(source, nowMillis: nowMillis)
      let reservation = isReviewReady ? nil : GlobalAutonomousActionGraphPolicy.reserveNext(
        actions: source.actions,
        nowMillis: nowMillis,
        leaseExpiresAtMillis: lease
      )
      let claimed: GlobalAutonomousRun
      if isReviewReady {
        claimed = claimReview(source, nowMillis: nowMillis, leaseExpiresAtMillis: lease)
      } else {
        claimed = claimAction(source, reservation: reservation, nowMillis: nowMillis, leaseExpiresAtMillis: lease)
      }
      runs[index] = claimed
      snapshot.autonomousRuns = boundedRuns(runs)
      persist(snapshot)
      return GlobalAutonomousWorkClaim(
        run: claimed,
        actionId: reservation?.actionId ?? "",
        planReview: isReviewReady
      )
    }
  }

  func exportCognitionTasks() -> [GlobalCognitionTask] {
    cognitionTasks()
  }

  func exportAutonomousRuns() -> [GlobalAutonomousRun] {
    autonomousRuns()
  }

  func restoreCognitionTasks(_ tasks: [GlobalCognitionTask]) {
    saveCognitionTasks(tasks)
  }

  func restoreAutonomousRuns(_ runs: [GlobalAutonomousRun]) {
    saveAutonomousRuns(runs)
  }

  private func reviewReady(_ run: GlobalAutonomousRun, nowMillis: Int64) -> Bool {
    run.status == .replanning &&
      [.pending, .waitingForResource].contains(run.review.status) &&
      run.review.nextAttemptAtMillis <= nowMillis
  }

  private func actionReady(_ run: GlobalAutonomousRun, nowMillis: Int64) -> Bool {
    [.queued, .waitingForResource, .running].contains(run.status) &&
      run.nextAttemptAtMillis <= nowMillis &&
      !GlobalAutonomousActionGraphPolicy.readyActions(run.actions).isEmpty
  }

  private func claimReview(
    _ run: GlobalAutonomousRun,
    nowMillis: Int64,
    leaseExpiresAtMillis: Int64
  ) -> GlobalAutonomousRun {
    var claimed = run
    var review = run.review
    review.status = .running
    review.attemptCount += 1
    review.leaseExpiresAtMillis = max(leaseExpiresAtMillis, 0)
    review.lastError = ""
    review.updatedAtMillis = max(nowMillis, 0)
    claimed.status = .replanning
    claimed.review = review
    claimed.attemptCount += 1
    claimed.leaseExpiresAtMillis = max(leaseExpiresAtMillis, 0)
    claimed.updatedAtMillis = max(nowMillis, 0)
    return claimed
  }

  private func claimAction(
    _ run: GlobalAutonomousRun,
    reservation: GlobalActionReservation?,
    nowMillis: Int64,
    leaseExpiresAtMillis: Int64
  ) -> GlobalAutonomousRun {
    var claimed = run
    claimed.status = .running
    claimed.actions = reservation?.actions ?? run.actions
    claimed.attemptCount += 1
    claimed.leaseExpiresAtMillis = max(run.leaseExpiresAtMillis, leaseExpiresAtMillis)
    claimed.updatedAtMillis = max(nowMillis, 0)
    return claimed
  }

  private func load() -> Snapshot {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return emptySnapshot()
    }
    do {
      let data = try Data(contentsOf: fileURL)
      guard !data.isEmpty else { return emptySnapshot() }
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
      guard snapshot.formatVersion == formatVersion else {
        lastErrorDescription = "Unsupported global deliberation store format"
        return emptySnapshot()
      }
      lastErrorDescription = ""
      return Snapshot(
        formatVersion: formatVersion,
        cognitionTasks: boundedCognition(snapshot.cognitionTasks),
        autonomousRuns: boundedRuns(snapshot.autonomousRuns)
      )
    } catch {
      lastErrorDescription = error.localizedDescription
      return emptySnapshot()
    }
  }

  private func persist(_ snapshot: Snapshot) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let bounded = Snapshot(
        formatVersion: formatVersion,
        cognitionTasks: boundedCognition(snapshot.cognitionTasks),
        autonomousRuns: boundedRuns(snapshot.autonomousRuns)
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(bounded).write(to: fileURL, options: [.atomic])
      lastErrorDescription = ""
    } catch {
      lastErrorDescription = error.localizedDescription
    }
  }

  private func emptySnapshot() -> Snapshot {
    Snapshot(formatVersion: formatVersion, cognitionTasks: [], autonomousRuns: [])
  }

  private func boundedCognition(_ tasks: [GlobalCognitionTask]) -> [GlobalCognitionTask] {
    Array(tasks
      .sorted { left, right in
        if left.createdAtMillis != right.createdAtMillis {
          return left.createdAtMillis < right.createdAtMillis
        }
        return left.id < right.id
      }
      .suffix(maxCognitionTasks))
  }

  private func boundedRuns(_ runs: [GlobalAutonomousRun]) -> [GlobalAutonomousRun] {
    Array(runs
      .sorted { left, right in
        if left.createdAtMillis != right.createdAtMillis {
          return left.createdAtMillis < right.createdAtMillis
        }
        return left.id < right.id
      }
      .suffix(maxAutonomousRuns))
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private let formatVersion = 1
  private let maxCognitionTasks = 300
  private let maxAutonomousRuns = 200
}
