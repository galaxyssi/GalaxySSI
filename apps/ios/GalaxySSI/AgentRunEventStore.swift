import Foundation

protocol AgentRunEventPersistence: AgentRunControlStore {
  func appendNextAll(_ events: [AgentRunControlEvent]) -> [AgentRunControlEvent]
  func events(runId: String) -> [AgentRunControlEvent]
  func latestEvent(runId: String) -> AgentRunControlEvent?
  func snapshot(runId: String) -> AgentRunControlSnapshot?
}

final class UserDefaultsAgentRunEventStore: AgentRunEventPersistence {
  private let defaults: UserDefaults
  private let storageKey: String
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var cachedEventsByRunId: [String: [AgentRunControlEvent]] = [:]
  private var cachedRunIds: [String]?
  private var cachedRecoverableRunIds: [String]?

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = "galaxyssi.agent.run.events.v1"
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
  }

  func appendNext(_ event: AgentRunControlEvent) -> AgentRunControlEvent {
    lock.lock()
    defer { lock.unlock() }
    let runId = clean(event.runId)
    guard !runId.isEmpty, !clean(event.taskId).isEmpty else { return event }
    var current = eventsLocked(runId)
    if let existing = current.first(where: { $0.eventId == event.eventId }) {
      return existing
    }
    let state = current.reduce(AgentRunControlState.created) {
      AgentRunEventStore.reduce(current: $0, event: $1.type)
    }
    if state.isTerminal, event.type != .runRecovered {
      return current.last ?? event
    }
    let sequenced = event.withSequence((current.last?.sequence ?? 0) + 1)
    current.append(sequenced)
    persistLocked(runId: runId, events: Array(current.suffix(Self.maxEventsPerRun)))
    return sequenced
  }

  func appendNextAll(_ events: [AgentRunControlEvent]) -> [AgentRunControlEvent] {
    guard let runId = events.first.map({ clean($0.runId) }),
          !runId.isEmpty,
          events.allSatisfy({ clean($0.runId) == runId && !clean($0.taskId).isEmpty }) else {
      return []
    }
    lock.lock()
    defer { lock.unlock() }
    var current = eventsLocked(runId)
    var knownEventIds = Set(current.map(\.eventId))
    var state = current.reduce(AgentRunControlState.created) {
      AgentRunEventStore.reduce(current: $0, event: $1.type)
    }
    var sequence = current.last?.sequence ?? 0
    var appended: [AgentRunControlEvent] = []
    for event in events {
      guard knownEventIds.insert(event.eventId).inserted else { continue }
      guard !state.isTerminal || event.type == .runRecovered else { continue }
      sequence += 1
      let sequenced = event.withSequence(sequence)
      current.append(sequenced)
      appended.append(sequenced)
      state = AgentRunEventStore.reduce(current: state, event: sequenced.type)
    }
    guard !appended.isEmpty else { return [] }
    persistLocked(runId: runId, events: Array(current.suffix(Self.maxEventsPerRun)))
    return appended
  }

  func events(runId: String) -> [AgentRunControlEvent] {
    lock.lock()
    defer { lock.unlock() }
    return eventsLocked(runId).sorted { $0.sequence < $1.sequence }
  }

  func latestEvent(runId: String) -> AgentRunControlEvent? {
    lock.lock()
    defer { lock.unlock() }
    return eventsLocked(runId).max { $0.sequence < $1.sequence }
  }

  func snapshot(runId: String) -> AgentRunControlSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return snapshotLocked(runId)
  }

  func recoverableRuns() -> [AgentRunControlSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return recoverableRunIdsLocked().compactMap(snapshotLocked).filter { !$0.state.isTerminal }
  }

  func storedRunIds(limit: Int = 500) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(runIdsLocked().suffix(max(1, min(limit, Self.maxRuns))))
  }

  func removeRuns(_ runIds: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    let normalized = Set(runIds.map(clean).filter { !$0.isEmpty })
    guard !normalized.isEmpty else { return }
    let retained = runIdsLocked().filter { !normalized.contains($0) }
    let recoverable = recoverableRunIdsLocked().filter { !normalized.contains($0) }
    normalized.forEach { cachedEventsByRunId.removeValue(forKey: $0) }
    cachedRunIds = retained
    cachedRecoverableRunIds = recoverable
    persistIndexesLocked()
    normalized.forEach { defaults.removeObject(forKey: eventKey($0)) }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    runIdsLocked().forEach { defaults.removeObject(forKey: eventKey($0)) }
    defaults.removeObject(forKey: runIdsKey)
    defaults.removeObject(forKey: recoverableRunIdsKey)
    cachedEventsByRunId.removeAll()
    cachedRunIds = []
    cachedRecoverableRunIds = []
  }

  private func eventsLocked(_ runId: String) -> [AgentRunControlEvent] {
    let cleanRunId = clean(runId)
    if let cached = cachedEventsByRunId[cleanRunId] { return cached }
    let decoded: [AgentRunControlEvent]
    if let data = defaults.data(forKey: eventKey(cleanRunId)) {
      decoded = (try? decoder.decode([AgentRunControlEvent].self, from: data)) ?? []
    } else {
      decoded = []
    }
    let sorted = decoded.sorted { $0.sequence < $1.sequence }
    cachedEventsByRunId[cleanRunId] = sorted
    return sorted
  }

  private func snapshotLocked(_ runId: String) -> AgentRunControlSnapshot? {
    let events = eventsLocked(runId)
    guard let last = events.last else { return nil }
    let state = events.reduce(AgentRunControlState.created) {
      AgentRunEventStore.reduce(current: $0, event: $1.type)
    }
    return AgentRunControlSnapshot(
      runId: last.runId,
      taskId: last.taskId,
      state: state,
      agentId: last.agentId,
      deviceId: last.deviceId,
      lastSequence: last.sequence,
      lastEvent: last
    )
  }

  private func persistLocked(runId: String, events: [AgentRunControlEvent]) {
    let normalized = Array(events.suffix(Self.maxEventsPerRun))
    cachedEventsByRunId[runId] = normalized
    var runIds = runIdsLocked().filter { $0 != runId }
    runIds.append(runId)
    let retainedRunIds = Array(runIds.suffix(Self.maxRuns))
    let staleRunIds = Set(runIds).subtracting(retainedRunIds)
    let state = normalized.reduce(AgentRunControlState.created) {
      AgentRunEventStore.reduce(current: $0, event: $1.type)
    }
    var recoverable = recoverableRunIdsLocked().filter {
      $0 != runId && !staleRunIds.contains($0)
    }
    if !state.isTerminal { recoverable.append(runId) }
    let retainedRecoverable = Array(recoverable.suffix(Self.maxRecoverableRuns))
    cachedRunIds = retainedRunIds
    cachedRecoverableRunIds = retainedRecoverable
    if let data = try? encoder.encode(normalized) {
      defaults.set(data, forKey: eventKey(runId))
    }
    staleRunIds.forEach {
      cachedEventsByRunId.removeValue(forKey: $0)
      defaults.removeObject(forKey: eventKey($0))
    }
    persistIndexesLocked()
  }

  private func persistIndexesLocked() {
    if let data = try? encoder.encode(runIdsLocked()) {
      defaults.set(data, forKey: runIdsKey)
    }
    if let data = try? encoder.encode(recoverableRunIdsLocked()) {
      defaults.set(data, forKey: recoverableRunIdsKey)
    }
  }

  private func runIdsLocked() -> [String] {
    if let cachedRunIds { return cachedRunIds }
    let decoded = decodeStrings(defaults.data(forKey: runIdsKey))
    cachedRunIds = decoded
    return decoded
  }

  private func recoverableRunIdsLocked() -> [String] {
    if let cachedRecoverableRunIds { return cachedRecoverableRunIds }
    let decoded = decodeStrings(defaults.data(forKey: recoverableRunIdsKey))
    cachedRecoverableRunIds = decoded
    return decoded
  }

  private func decodeStrings(_ data: Data?) -> [String] {
    guard let data else { return [] }
    return (try? decoder.decode([String].self, from: data)) ?? []
  }

  private func eventKey(_ runId: String) -> String {
    "\(storageKey).run.\(runId)"
  }

  private var runIdsKey: String { "\(storageKey).ids" }
  private var recoverableRunIdsKey: String { "\(storageKey).recoverable" }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let maxRuns = 500
  private static let maxRecoverableRuns = 64
  private static let maxEventsPerRun = 2_000
}

private extension AgentRunControlEvent {
  func withSequence(_ sequence: Int64) -> AgentRunControlEvent {
    var copy = self
    copy.sequence = max(sequence, 1)
    if copy.timestampMillis <= 0 {
      copy.timestampMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
    return copy
  }
}
