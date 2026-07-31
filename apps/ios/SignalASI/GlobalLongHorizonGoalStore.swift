import Foundation

protocol GlobalLongHorizonGoalStoring: AnyObject {
  func goals() -> [GlobalLongHorizonGoal]
  func save(_ goals: [GlobalLongHorizonGoal], nowMillis: Int64)
  func upsert(_ goal: GlobalLongHorizonGoal, nowMillis: Int64)
  @discardableResult
  func update(
    goalId: String,
    nowMillis: Int64,
    transform: (GlobalLongHorizonGoal) -> GlobalLongHorizonGoal
  ) -> GlobalLongHorizonGoal?
  func exportGoals() -> [GlobalLongHorizonGoal]
  func restore(_ goals: [GlobalLongHorizonGoal])
}

extension GlobalLongHorizonGoalStoring {
  func save(_ goals: [GlobalLongHorizonGoal]) {
    save(goals, nowMillis: GlobalRealtimeClock.nowMillis())
  }

  func upsert(_ goal: GlobalLongHorizonGoal) {
    upsert(goal, nowMillis: GlobalRealtimeClock.nowMillis())
  }

  @discardableResult
  func update(
    goalId: String,
    transform: (GlobalLongHorizonGoal) -> GlobalLongHorizonGoal
  ) -> GlobalLongHorizonGoal? {
    update(goalId: goalId, nowMillis: GlobalRealtimeClock.nowMillis(), transform: transform)
  }
}

final class GlobalLongHorizonGoalStore: GlobalLongHorizonGoalStoring {
  private struct Snapshot: Codable {
    var formatVersion: Int
    var goals: [GlobalLongHorizonGoal]
  }

  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSLock()
  private(set) var lastErrorDescription: String = ""

  init(
    fileURL: URL = GlobalLongHorizonGoalStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(
    storageRootURL: URL = AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
  ) -> URL {
    storageRootURL
      .appendingPathComponent("global-long-horizon", isDirectory: true)
      .appendingPathComponent("goals.json", isDirectory: false)
  }

  static func destroyPersistentStore(
    fileURL: URL = GlobalLongHorizonGoalStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    try? fileManager.removeItem(at: fileURL)
  }

  func goals() -> [GlobalLongHorizonGoal] {
    locked { load() }
  }

  func save(_ goals: [GlobalLongHorizonGoal], nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    locked {
      let previous = load()
      let stamped = stamp(previous: previous, next: bounded(goals), nowMillis: nowMillis)
      persist(stamped)
    }
  }

  func upsert(_ goal: GlobalLongHorizonGoal, nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    locked {
      let previous = load()
      let next = previous.filter { $0.id != goal.id } + [goal]
      let stamped = stamp(previous: previous, next: bounded(next), nowMillis: nowMillis)
      persist(stamped)
    }
  }

  @discardableResult
  func update(
    goalId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    transform: (GlobalLongHorizonGoal) -> GlobalLongHorizonGoal
  ) -> GlobalLongHorizonGoal? {
    locked {
      var current = load()
      guard let index = current.firstIndex(where: { $0.id == goalId }) else {
        return nil
      }
      let previous = current[index]
      let updated = GlobalLongHorizonLifecyclePolicy.stampTransition(
        previous: previous,
        next: transform(previous),
        nowMillis: nowMillis
      )
      current[index] = updated
      persist(bounded(current))
      return updated
    }
  }

  func exportGoals() -> [GlobalLongHorizonGoal] {
    goals()
  }

  func restore(_ goals: [GlobalLongHorizonGoal]) {
    locked {
      persist(bounded(goals))
    }
  }

  private func load() -> [GlobalLongHorizonGoal] {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return []
    }
    do {
      let data = try Data(contentsOf: fileURL)
      guard !data.isEmpty else { return [] }
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
      guard snapshot.formatVersion == formatVersion else {
        lastErrorDescription = "Unsupported long-horizon goal store format"
        return []
      }
      lastErrorDescription = ""
      return bounded(snapshot.goals)
    } catch {
      lastErrorDescription = error.localizedDescription
      return []
    }
  }

  private func persist(_ goals: [GlobalLongHorizonGoal]) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let snapshot = Snapshot(formatVersion: formatVersion, goals: bounded(goals))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
      lastErrorDescription = ""
    } catch {
      lastErrorDescription = error.localizedDescription
    }
  }

  private func stamp(
    previous: [GlobalLongHorizonGoal],
    next: [GlobalLongHorizonGoal],
    nowMillis: Int64
  ) -> [GlobalLongHorizonGoal] {
    var previousById: [String: GlobalLongHorizonGoal] = [:]
    for goal in previous {
      previousById[goal.id] = goal
    }
    return next.map {
      GlobalLongHorizonLifecyclePolicy.stampTransition(
        previous: previousById[$0.id],
        next: $0,
        nowMillis: nowMillis
      )
    }
  }

  private func bounded(_ goals: [GlobalLongHorizonGoal]) -> [GlobalLongHorizonGoal] {
    Array(goals
      .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { left, right in
        if left.createdAtMillis != right.createdAtMillis {
          return left.createdAtMillis < right.createdAtMillis
        }
        return left.id < right.id
      }
      .suffix(maxGoals))
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private let formatVersion = 1
  private let maxGoals = 200
}

final class InMemoryGlobalLongHorizonGoalStore: GlobalLongHorizonGoalStoring {
  private var storedGoals: [GlobalLongHorizonGoal]
  private let lock = NSLock()

  init(goals: [GlobalLongHorizonGoal] = []) {
    self.storedGoals = Array(goals.suffix(200))
  }

  func goals() -> [GlobalLongHorizonGoal] {
    locked { storedGoals }
  }

  func save(_ goals: [GlobalLongHorizonGoal], nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    locked {
      storedGoals = stamp(previous: storedGoals, next: Array(goals.suffix(200)), nowMillis: nowMillis)
    }
  }

  func upsert(_ goal: GlobalLongHorizonGoal, nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) {
    locked {
      let next = storedGoals.filter { $0.id != goal.id } + [goal]
      storedGoals = stamp(previous: storedGoals, next: Array(next.suffix(200)), nowMillis: nowMillis)
    }
  }

  @discardableResult
  func update(
    goalId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    transform: (GlobalLongHorizonGoal) -> GlobalLongHorizonGoal
  ) -> GlobalLongHorizonGoal? {
    locked {
      guard let index = storedGoals.firstIndex(where: { $0.id == goalId }) else {
        return nil
      }
      let previous = storedGoals[index]
      let updated = GlobalLongHorizonLifecyclePolicy.stampTransition(
        previous: previous,
        next: transform(previous),
        nowMillis: nowMillis
      )
      storedGoals[index] = updated
      return updated
    }
  }

  func exportGoals() -> [GlobalLongHorizonGoal] {
    goals()
  }

  func restore(_ goals: [GlobalLongHorizonGoal]) {
    locked {
      storedGoals = Array(goals.suffix(200))
    }
  }

  private func stamp(
    previous: [GlobalLongHorizonGoal],
    next: [GlobalLongHorizonGoal],
    nowMillis: Int64
  ) -> [GlobalLongHorizonGoal] {
    var previousById: [String: GlobalLongHorizonGoal] = [:]
    for goal in previous {
      previousById[goal.id] = goal
    }
    return next.map {
      GlobalLongHorizonLifecyclePolicy.stampTransition(
        previous: previousById[$0.id],
        next: $0,
        nowMillis: nowMillis
      )
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
