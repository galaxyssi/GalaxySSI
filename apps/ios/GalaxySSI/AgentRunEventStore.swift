import Foundation

protocol AgentRunEventPersistence: AgentRunControlStore {
  func appendNextAll(_ events: [AgentRunControlEvent]) -> [AgentRunControlEvent]
  func events(runId: String) -> [AgentRunControlEvent]
  func latestEvent(runId: String) -> AgentRunControlEvent?
  func snapshot(runId: String) -> AgentRunControlSnapshot?
  func containsIdempotencyKey(runId: String, key: String) -> Bool
}

final class UserDefaultsAgentRunEventStore: AgentRunEventPersistence {
  private let defaults: UserDefaults
  private let storageKey: String
  private static let persistenceLock = NSRecursiveLock()
  private let lock = UserDefaultsAgentRunEventStore.persistenceLock
  private let readCacheLock = NSLock()
  private let encoder = JSONEncoder()
  private var readCache: [String: CachedRun] = [:]

  private struct CachedRun {
    let data: Data
    let run: IndexedRun
  }

  private struct IndexedRun {
    var events: [AgentRunControlEvent] = []
    var byId: [String: Int] = [:]
    var byKey: [String: Int] = [:]
    var state: AgentRunControlState = .created

    init(_ events: [AgentRunControlEvent] = []) {
      for event in events { append(event) }
    }

    mutating func append(_ event: AgentRunControlEvent) {
      if byId[event.eventId] == nil { byId[event.eventId] = events.count }
      if byKey[event.idempotencyKey] == nil { byKey[event.idempotencyKey] = events.count }
      events.append(event)
      state = AgentRunEventStore.reduce(current: state, event: event.type)
    }

    func firstMatch(_ event: AgentRunControlEvent) -> AgentRunControlEvent? {
      [byId[event.eventId], byKey[event.idempotencyKey]].compactMap { $0 }.min().map { events[$0] }
    }
  }

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = "galaxyssi.agent.run.events.v1"
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
  }

  private func appendPreparedNext(_ event: AgentRunControlEvent) -> AgentRunControlEvent {
    lock.lock()
    defer { lock.unlock() }
    guard let canonical = AgentRunKernelContract.canonical(event) else { return event }
    let runId = canonical.runId
    var current = readRun(runId)
    if let root = current.events.first, !AgentRunKernelContract.hasSameRoot(root, canonical) {
      return current.events.last ?? event
    }
    if let existing = current.firstMatch(canonical) {
      guard AgentRunKernelContract.isIdempotentReplay(existing, canonical) else {
        return current.events.last ?? existing
      }
      return existing
    }
    if current.state.isTerminal, canonical.type != .runRecovered {
      return current.events.last ?? event
    }
    let sequence = current.events.last?.sequence ?? 0
    guard sequence < Int64.max else { return current.events.last ?? event }
    let sequenced = canonical.withSequence(sequence + 1)
    current.append(sequenced)
    persistLocked(runId: runId, run: current)
    return sequenced
  }

  private func appendPreparedBatch(_ events: [AgentRunControlEvent]) -> [AgentRunControlEvent] {
    let canonicalEvents = events.compactMap(AgentRunKernelContract.canonical)
    guard canonicalEvents.count == events.count,
          let first = canonicalEvents.first,
          canonicalEvents.allSatisfy({ AgentRunKernelContract.hasSameRoot(first, $0) }) else {
      return []
    }
    let runId = first.runId
    lock.lock()
    defer { lock.unlock() }
    var current = readRun(runId)
    if let root = current.events.first, !AgentRunKernelContract.hasSameRoot(root, first) { return [] }
    var sequence = current.events.last?.sequence ?? 0
    var appended: [AgentRunControlEvent] = []
    for event in canonicalEvents {
      guard current.firstMatch(event) == nil, sequence < Int64.max,
            !current.state.isTerminal || event.type == .runRecovered else { continue }
      sequence += 1
      let sequenced = event.withSequence(sequence)
      current.append(sequenced)
      appended.append(sequenced)
    }
    guard !appended.isEmpty else { return [] }
    persistLocked(runId: runId, run: current)
    return appended
  }

  func appendRecoveryIfCurrent(_ event: AgentRunControlEvent, expectedSequence: Int64) -> AgentRunControlEvent? {
    lock.lock()
    defer { lock.unlock() }
    guard let current = snapshot(runId: event.runId), !current.state.isTerminal,
          current.lastSequence == expectedSequence else { return nil }
    let committed = appendNext(event)
    return committed.eventId == event.eventId ? committed : nil
  }

  func events(runId: String) -> [AgentRunControlEvent] {
    readRun(runId).events
  }

  func latestEvent(runId: String) -> AgentRunControlEvent? {
    readRun(runId).events.last
  }

  func snapshot(runId: String) -> AgentRunControlSnapshot? {
    let run = readRun(runId)
    guard let last = run.events.last else { return nil }
    return AgentRunControlSnapshot(runId: last.runId, taskId: last.taskId, state: run.state,
      agentId: last.agentId, deviceId: last.deviceId, lastSequence: last.sequence, lastEvent: last)
  }

  func containsIdempotencyKey(runId: String, key: String) -> Bool {
    let normalizedKey = clean(key)
    guard !normalizedKey.isEmpty else { return false }
    return readRun(runId).byKey[normalizedKey] != nil
  }

  func recoverableRuns() -> [AgentRunControlSnapshot] {
    recoverableRunIds().compactMap { snapshot(runId: $0) }.filter { !$0.state.isTerminal }
  }

  func storedRunIds(limit: Int = 500) -> [String] {
    Array(runIds().suffix(max(1, min(limit, Self.maxRuns))))
  }

  func removeRuns(_ runIds: Set<String>) {
    lock.lock()
    defer { lock.unlock() }
    let normalized = Set(runIds.map(clean).filter { !$0.isEmpty })
    guard !normalized.isEmpty else { return }
    persistIndexes(runIds: self.runIds().filter { !normalized.contains($0) },
      recoverable: recoverableRunIds().filter { !normalized.contains($0) })
    normalized.forEach { defaults.removeObject(forKey: eventKey($0)) }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    runIds().forEach { defaults.removeObject(forKey: eventKey($0)) }
    defaults.removeObject(forKey: runIdsKey)
    defaults.removeObject(forKey: recoverableRunIdsKey)
    readCacheLock.lock()
    readCache.removeAll()
    readCacheLock.unlock()
  }

  private func readRun(_ id: String) -> IndexedRun {
    let runId = clean(id)
    // UserDefaults returns a complete immutable value. Readers never wait for ledger encoding or index writes.
    guard let data = defaults.data(forKey: eventKey(runId)) else { return IndexedRun() }
    readCacheLock.lock()
    let cached = readCache[runId]
    readCacheLock.unlock()
    if let cached, cached.data == data { return cached.run }
    let decoded = (try? JSONDecoder().decode([AgentRunControlEvent].self, from: data)) ?? []
    let run = IndexedRun(decoded.compactMap(AgentRunKernelContract.canonical).sorted { $0.sequence < $1.sequence })
    cache(run, data: data, id: runId)
    return run
  }

  private func cache(_ run: IndexedRun, data: Data, id: String) {
    guard data.count <= 2 * 1_024 * 1_024 else { return }
    readCacheLock.lock()
    defer { readCacheLock.unlock() }
    if readCache.count >= 8, readCache[id] == nil, let oldest = readCache.keys.first {
      readCache.removeValue(forKey: oldest)
    }
    readCache[id] = CachedRun(data: data, run: run)
  }

  private func persistLocked(runId: String, run: IndexedRun) {
    let normalized = run.events.count > Self.maxEventsPerRun
      ? IndexedRun(Array(run.events.suffix(Self.maxEventsPerRun))) : run
    guard let data = try? encoder.encode(normalized.events) else { return }
    var ids = runIds().filter { $0 != runId }
    ids.append(runId)
    let retainedRunIds = Array(ids.suffix(Self.maxRuns))
    let staleRunIds = Set(ids).subtracting(retainedRunIds)
    var recoverable = recoverableRunIds().filter {
      $0 != runId && !staleRunIds.contains($0)
    }
    if !normalized.state.isTerminal { recoverable.append(runId) }
    defaults.set(data, forKey: eventKey(runId))
    cache(normalized, data: data, id: runId)
    staleRunIds.forEach { defaults.removeObject(forKey: eventKey($0)) }
    persistIndexes(runIds: retainedRunIds, recoverable: Array(recoverable.suffix(Self.maxRecoverableRuns)))
  }

  private func persistIndexes(runIds: [String], recoverable: [String]) {
    if let data = try? encoder.encode(runIds) {
      defaults.set(data, forKey: runIdsKey)
    }
    if let data = try? encoder.encode(recoverable) {
      defaults.set(data, forKey: recoverableRunIdsKey)
    }
  }

  private func runIds() -> [String] {
    decodeStrings(defaults.data(forKey: runIdsKey))
  }

  private func recoverableRunIds() -> [String] {
    decodeStrings(defaults.data(forKey: recoverableRunIdsKey))
  }

  private func decodeStrings(_ data: Data?) -> [String] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  private func eventKey(_ runId: String) -> String {
    "\(storageKey).run.\(runId)"
  }

  private var runIdsKey: String { "\(storageKey).ids" }
  private var recoverableRunIdsKey: String { "\(storageKey).recoverable" }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func appendNext(_ event: AgentRunControlEvent) -> AgentRunControlEvent {
    guard let candidate = AgentRunKernelContract.canonical(event),
          candidate.runId.hasPrefix(AgentDeviceOperationCheckpoint.runPrefix) else { return appendPreparedNext(event) }
    lock.lock()
    defer { lock.unlock() }
    let history = deviceOperationHistory(runId: candidate.runId)
    guard AgentDeviceOperationCheckpoint.ownsRun(candidate) else { return history.last ?? event }
    if let existing = history.first(where: {
      $0.eventId == candidate.eventId || $0.idempotencyKey == candidate.idempotencyKey
    }), AgentDeviceOperationCheckpoint.replayMatches(existing, candidate) { return existing }
    guard let prepared = AgentDeviceOperationCheckpoint.preparingForAppend(candidate, after: history.last)
    else { return history.last ?? event }
    return appendPreparedNext(prepared)
  }

  func appendNextAll(_ events: [AgentRunControlEvent]) -> [AgentRunControlEvent] {
    guard let first = events.first.flatMap(AgentRunKernelContract.canonical),
          first.runId.hasPrefix(AgentDeviceOperationCheckpoint.runPrefix) else { return appendPreparedBatch(events) }
    let canonical = events.compactMap(AgentRunKernelContract.canonical)
    guard canonical.count == events.count,
          canonical.allSatisfy({ AgentDeviceOperationCheckpoint.ownsRun($0) &&
            AgentRunKernelContract.hasSameRoot(first, $0) }) else { return [] }
    lock.lock()
    defer { lock.unlock() }
    let history = deviceOperationHistory(runId: first.runId)
    var last = history.last
    var ids = Set(history.map(\.eventId))
    var keys = Set(history.map(\.idempotencyKey))
    var state = history.reduce(AgentRunControlState.created) { AgentRunEventStore.reduce(current: $0, event: $1.type) }
    var batch: [AgentRunControlEvent] = []
    for candidate in canonical {
      guard !ids.contains(candidate.eventId), !keys.contains(candidate.idempotencyKey),
            let event = AgentDeviceOperationCheckpoint.preparingForAppend(candidate, after: last),
            !state.isTerminal || event.type == .runRecovered else { continue }
      ids.insert(event.eventId)
      keys.insert(event.idempotencyKey)
      state = AgentRunEventStore.reduce(current: state, event: event.type)
      last = event
      batch.append(event)
    }
    return appendPreparedBatch(batch)
  }

  private func deviceOperationHistory(runId: String) -> [AgentRunControlEvent] {
    // Read the committed value under the writer lock, not an instance's potentially older cache.
    guard let data = defaults.data(forKey: eventKey(runId)),
          let events = try? JSONDecoder().decode([AgentRunControlEvent].self, from: data) else { return [] }
    return events.compactMap(AgentRunKernelContract.canonical).sorted { $0.sequence < $1.sequence }
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
