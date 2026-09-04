import Foundation

enum AgentMemoryAttributionMode: String, Codable {
  case processTotal = "process_total"
  case sharedWeighted = "shared_weighted"
}

struct AgentMemoryPssSample: Codable, Equatable, Identifiable {
  var id: String
  var sampledAtMillis: Int64
  var processTotalBytes: Int64
  var attributedBytes: Int64
  var nativeBytes: Int64
  var dalvikBytes: Int64
  var otherBytes: Int64
  var measurementKind: String
  var attributionMode: String
  var agentId: String
  var sessionId: String
  var conversationId: String
  var providerId: String
  var taskId: String

  enum CodingKeys: String, CodingKey {
    case id
    case sampledAtMillis = "sampled_at_millis"
    case processTotalBytes = "process_total_bytes"
    case attributedBytes = "attributed_bytes"
    case nativeBytes = "native_bytes"
    case dalvikBytes = "dalvik_bytes"
    case otherBytes = "other_bytes"
    case measurementKind = "measurement_kind"
    case attributionMode = "attribution_mode"
    case agentId = "agent_id"
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case providerId = "provider_id"
    case taskId = "task_id"
  }

  init(
    id: String,
    sampledAtMillis: Int64,
    processTotalBytes: Int64,
    attributedBytes: Int64,
    nativeBytes: Int64,
    dalvikBytes: Int64,
    otherBytes: Int64,
    measurementKind: String = AgentMemoryMeasurementKind.iosResidentMemory.rawValue,
    attributionMode: String = AgentMemoryAttributionMode.processTotal.rawValue,
    agentId: String = "",
    sessionId: String = "",
    conversationId: String = "",
    providerId: String = "",
    taskId: String = ""
  ) {
    self.id = id
    self.sampledAtMillis = max(0, sampledAtMillis)
    self.processTotalBytes = max(0, processTotalBytes)
    self.attributedBytes = max(0, attributedBytes)
    self.nativeBytes = max(0, nativeBytes)
    self.dalvikBytes = max(0, dalvikBytes)
    self.otherBytes = max(0, otherBytes)
    self.measurementKind = measurementKind.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(
      AgentMemoryMeasurementKind.iosResidentMemory.rawValue
    )
    self.attributionMode = attributionMode.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(
      AgentMemoryAttributionMode.processTotal.rawValue
    )
    self.agentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.sessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.conversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.providerId = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.taskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct AgentMemoryDimensionStats: Codable, Equatable, Identifiable {
  var id: String
  var currentBytes: Int64
  var peakBytes: Int64
  var averageBytes: Int64
  var sampleCount: Int
  var lastSampledAtMillis: Int64
  var estimated: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case currentBytes = "current_bytes"
    case peakBytes = "peak_bytes"
    case averageBytes = "average_bytes"
    case sampleCount = "sample_count"
    case lastSampledAtMillis = "last_sampled_at_millis"
    case estimated
  }

  init(
    id: String,
    currentBytes: Int64,
    peakBytes: Int64,
    averageBytes: Int64,
    sampleCount: Int,
    lastSampledAtMillis: Int64,
    estimated: Bool
  ) {
    self.id = id
    self.currentBytes = max(0, currentBytes)
    self.peakBytes = max(0, peakBytes)
    self.averageBytes = max(0, averageBytes)
    self.sampleCount = max(0, sampleCount)
    self.lastSampledAtMillis = max(0, lastSampledAtMillis)
    self.estimated = estimated
  }
}

struct AgentMemoryPssSnapshot: Codable, Equatable {
  var measurementKind: String
  var sampledAtMillis: Int64
  var processCurrentBytes: Int64
  var processPeakBytes: Int64
  var nativeBytes: Int64
  var dalvikBytes: Int64
  var otherBytes: Int64
  var sampleCount: Int
  var byAgent: [AgentMemoryDimensionStats]
  var bySession: [AgentMemoryDimensionStats]
  var byProvider: [AgentMemoryDimensionStats]
  var sessionBudget: AgentSessionMemoryBudgetSnapshot

  enum CodingKeys: String, CodingKey {
    case measurementKind = "measurement_kind"
    case sampledAtMillis = "sampled_at_millis"
    case processCurrentBytes = "process_current_bytes"
    case processPeakBytes = "process_peak_bytes"
    case nativeBytes = "native_bytes"
    case dalvikBytes = "dalvik_bytes"
    case otherBytes = "other_bytes"
    case sampleCount = "sample_count"
    case byAgent = "by_agent"
    case bySession = "by_session"
    case byProvider = "by_provider"
    case sessionBudget = "session_budget"
  }

  init(
    measurementKind: String = AgentMemoryMeasurementKind.iosResidentMemory.rawValue,
    sampledAtMillis: Int64 = 0,
    processCurrentBytes: Int64 = 0,
    processPeakBytes: Int64 = 0,
    nativeBytes: Int64 = 0,
    dalvikBytes: Int64 = 0,
    otherBytes: Int64 = 0,
    sampleCount: Int = 0,
    byAgent: [AgentMemoryDimensionStats] = [],
    bySession: [AgentMemoryDimensionStats] = [],
    byProvider: [AgentMemoryDimensionStats] = [],
    sessionBudget: AgentSessionMemoryBudgetSnapshot = AgentSessionMemoryBudgetSnapshot()
  ) {
    self.measurementKind = measurementKind
    self.sampledAtMillis = max(0, sampledAtMillis)
    self.processCurrentBytes = max(0, processCurrentBytes)
    self.processPeakBytes = max(0, processPeakBytes)
    self.nativeBytes = max(0, nativeBytes)
    self.dalvikBytes = max(0, dalvikBytes)
    self.otherBytes = max(0, otherBytes)
    self.sampleCount = max(0, sampleCount)
    self.byAgent = byAgent
    self.bySession = bySession
    self.byProvider = byProvider
    self.sessionBudget = sessionBudget
  }
}

protocol AgentMemoryPssSampleStore {
  func append(_ sample: AgentMemoryPssSample)
  func recent(limit: Int, sinceMillis: Int64) -> [AgentMemoryPssSample]
  func prune(beforeMillis: Int64, maxSamples: Int)
}

final class InMemoryAgentMemoryPssSampleStore: AgentMemoryPssSampleStore {
  private let lock = NSLock()
  private var samples: [AgentMemoryPssSample]

  init(samples: [AgentMemoryPssSample] = []) {
    self.samples = Self.ordered(samples)
  }

  func append(_ sample: AgentMemoryPssSample) {
    locked {
      samples.append(sample)
      samples = Self.ordered(samples)
    }
  }

  func recent(limit: Int, sinceMillis: Int64) -> [AgentMemoryPssSample] {
    locked {
      Array(Self.ordered(samples.filter { $0.sampledAtMillis >= sinceMillis }).suffix(max(1, limit)))
    }
  }

  func prune(beforeMillis: Int64, maxSamples: Int) {
    locked {
      samples = Array(Self.ordered(samples.filter { $0.sampledAtMillis >= beforeMillis }).suffix(max(1, maxSamples)))
    }
  }

  private static func ordered(_ samples: [AgentMemoryPssSample]) -> [AgentMemoryPssSample] {
    samples.sorted {
      if $0.sampledAtMillis == $1.sampledAtMillis {
        return $0.id < $1.id
      }
      return $0.sampledAtMillis < $1.sampledAtMillis
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

final class UserDefaultsAgentMemoryPssSampleStore: AgentMemoryPssSampleStore {
  static let defaultKey = "galaxyssi_agent_memory_pss"

  private struct Document: Codable {
    var version: Int
    var samples: [AgentMemoryPssSample]
  }

  private let defaults: UserDefaults
  private let key: String
  private let lock = NSLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryPssSampleStore.defaultKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentMemoryPssSampleStore.defaultKey
  ) {
    defaults.removeObject(forKey: key)
  }

  func append(_ sample: AgentMemoryPssSample) {
    locked {
      persist(Self.ordered(load() + [sample]))
    }
  }

  func recent(limit: Int, sinceMillis: Int64) -> [AgentMemoryPssSample] {
    locked {
      Array(Self.ordered(load().filter { $0.sampledAtMillis >= sinceMillis }).suffix(max(1, limit)))
    }
  }

  func prune(beforeMillis: Int64, maxSamples: Int) {
    locked {
      persist(Array(Self.ordered(load().filter { $0.sampledAtMillis >= beforeMillis }).suffix(max(1, maxSamples))))
    }
  }

  private static func ordered(_ samples: [AgentMemoryPssSample]) -> [AgentMemoryPssSample] {
    samples.sorted {
      if $0.sampledAtMillis == $1.sampledAtMillis {
        return $0.id < $1.id
      }
      return $0.sampledAtMillis < $1.sampledAtMillis
    }
  }

  private func load() -> [AgentMemoryPssSample] {
    guard let data = defaults.data(forKey: key),
          let decoded = try? JSONDecoder().decode(Document.self, from: data) else {
      return []
    }
    return Self.ordered(decoded.samples)
  }

  private func persist(_ samples: [AgentMemoryPssSample]) {
    let document = Document(version: 1, samples: samples)
    if let data = try? JSONEncoder().encode(document) {
      defaults.set(data, forKey: key)
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

enum AgentMemoryPssAggregation {
  static func snapshot(
    _ samples: [AgentMemoryPssSample],
    sessionBudget: AgentSessionMemoryBudgetSnapshot = AgentSessionMemoryBudgetSnapshot()
  ) -> AgentMemoryPssSnapshot {
    let ordered = ordered(samples)
    guard let latest = ordered.last else {
      return AgentMemoryPssSnapshot(sessionBudget: sessionBudget)
    }
    let latestAt = latest.sampledAtMillis
    let latestSet = ordered.filter { $0.sampledAtMillis == latestAt }
    return AgentMemoryPssSnapshot(
      measurementKind: latest.measurementKind,
      sampledAtMillis: latestAt,
      processCurrentBytes: latestSet.map(\.processTotalBytes).max() ?? latest.processTotalBytes,
      processPeakBytes: ordered.map(\.processTotalBytes).max() ?? latest.processTotalBytes,
      nativeBytes: latest.nativeBytes,
      dalvikBytes: latest.dalvikBytes,
      otherBytes: latest.otherBytes,
      sampleCount: ordered.count,
      byAgent: aggregate(ordered, key: \.agentId),
      bySession: aggregate(ordered, key: \.sessionId),
      byProvider: aggregate(ordered, key: \.providerId),
      sessionBudget: sessionBudget
    )
  }

  private static func aggregate(
    _ samples: [AgentMemoryPssSample],
    key: KeyPath<AgentMemoryPssSample, String>
  ) -> [AgentMemoryDimensionStats] {
    let globalLatestAt = samples.last?.sampledAtMillis ?? 0
    let grouped = Dictionary(grouping: samples.filter { !$0[keyPath: key].isEmpty }) {
      $0[keyPath: key]
    }
    return grouped.map { id, values in
      let ordered = ordered(values)
      let latest = ordered.last
      let total = ordered.reduce(Int64(0)) { $0 + $1.attributedBytes }
      return AgentMemoryDimensionStats(
        id: id,
        currentBytes: latest?.sampledAtMillis == globalLatestAt ? latest?.attributedBytes ?? 0 : 0,
        peakBytes: ordered.map(\.attributedBytes).max() ?? 0,
        averageBytes: total / Int64(max(1, ordered.count)),
        sampleCount: ordered.count,
        lastSampledAtMillis: latest?.sampledAtMillis ?? 0,
        estimated: ordered.contains { $0.attributionMode != AgentMemoryAttributionMode.processTotal.rawValue }
      )
    }
    .sorted {
      if $0.currentBytes != $1.currentBytes {
        return $0.currentBytes > $1.currentBytes
      }
      if $0.peakBytes != $1.peakBytes {
        return $0.peakBytes > $1.peakBytes
      }
      return $0.id.lowercased() < $1.id.lowercased()
    }
  }

  private static func ordered(_ samples: [AgentMemoryPssSample]) -> [AgentMemoryPssSample] {
    samples.sorted {
      if $0.sampledAtMillis == $1.sampledAtMillis {
        return $0.id < $1.id
      }
      return $0.sampledAtMillis < $1.sampledAtMillis
    }
  }
}

final class AgentMemoryPssMonitor {
  static let defaultRetentionMillis: Int64 = 24 * 60 * 60 * 1_000
  static let defaultMaxSamples = 4_096

  private let sampler: AgentMemoryPssSampler
  private let store: AgentMemoryPssSampleStore
  private let clock: () -> Int64
  private let retentionMillis: Int64
  private let maxSamples: Int
  private let idGenerator: () -> String
  private let lock = NSLock()
  private var history: [AgentMemoryPssSample]
  private var capturesSincePrune = 0
  private var cachedSnapshot: AgentMemoryPssSnapshot

  init(
    sampler: AgentMemoryPssSampler,
    store: AgentMemoryPssSampleStore,
    clock: @escaping () -> Int64 = AgentMemoryClock.nowMillis,
    retentionMillis: Int64 = AgentMemoryPssMonitor.defaultRetentionMillis,
    maxSamples: Int = AgentMemoryPssMonitor.defaultMaxSamples,
    idGenerator: @escaping () -> String = { UUID().uuidString }
  ) {
    self.sampler = sampler
    self.store = store
    self.clock = clock
    self.retentionMillis = max(0, retentionMillis)
    self.maxSamples = max(1, maxSamples)
    self.idGenerator = idGenerator
    let restored = store.recent(limit: self.maxSamples, sinceMillis: clock() - self.retentionMillis)
    self.history = Self.ordered(restored)
    self.cachedSnapshot = AgentMemoryPssAggregation.snapshot(restored)
  }

  @discardableResult
  func capture(activeWorkspaces: [AgentWorkspace]) -> AgentMemoryPssSnapshot {
    locked {
      let reading = sampler.sample()
      let sampledAt = clock()
      let active = distinctByTask(activeWorkspaces.filter { !$0.cancellationRequested })
      let samples: [AgentMemoryPssSample]
      if active.isEmpty {
        samples = [sample(for: reading, sampledAt: sampledAt, workspace: nil, attributedBytes: 0)]
      } else {
        let attributed = reading.totalBytes / Int64(max(1, active.count))
        samples = active.map {
          sample(for: reading, sampledAt: sampledAt, workspace: $0, attributedBytes: attributed)
        }
      }
      samples.forEach(store.append)
      history += samples
      let cutoff = sampledAt - retentionMillis
      history = Array(Self.ordered(history.filter { $0.sampledAtMillis >= cutoff }).suffix(maxSamples))
      capturesSincePrune += 1
      if capturesSincePrune >= Self.pruneEveryCaptures {
        store.prune(beforeMillis: cutoff, maxSamples: maxSamples)
        capturesSincePrune = 0
      }
      cachedSnapshot = AgentMemoryPssAggregation.snapshot(history)
      return cachedSnapshot
    }
  }

  func snapshot() -> AgentMemoryPssSnapshot {
    locked {
      cachedSnapshot
    }
  }

  static func providerIdForAgent(_ agentId: String) -> String {
    let clean = agentId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !clean.isEmpty else {
      return ""
    }
    for prefix in ["provider:", "model:", "cloud:", "local-model:"] where clean.hasPrefix(prefix) {
      return String(clean.dropFirst(prefix.count)).split(separator: ":").first.map(String.init) ?? ""
    }
    switch clean {
    case "galaxyssi-mobile", "mobile", "on-device":
      return "on-device"
    default:
      return clean.split(separator: ":").first.map(String.init) ?? clean
    }
  }

  private func sample(
    for reading: AgentMemoryPssReading,
    sampledAt: Int64,
    workspace: AgentWorkspace?,
    attributedBytes: Int64
  ) -> AgentMemoryPssSample {
    let cleanAgentId = workspace?.agentId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let agentId = cleanAgentId.ifBlank(workspace == nil ? "" : "galaxyssi-mobile")
    return AgentMemoryPssSample(
      id: idGenerator(),
      sampledAtMillis: sampledAt,
      processTotalBytes: reading.totalBytes,
      attributedBytes: attributedBytes,
      nativeBytes: reading.nativeBytes,
      dalvikBytes: reading.dalvikBytes,
      otherBytes: reading.otherBytes,
      measurementKind: reading.measurementKind.rawValue,
      attributionMode: workspace == nil
        ? AgentMemoryAttributionMode.processTotal.rawValue
        : AgentMemoryAttributionMode.sharedWeighted.rawValue,
      agentId: agentId,
      sessionId: workspace?.sessionId ?? "",
      conversationId: workspace?.conversationId ?? "",
      providerId: Self.providerIdForAgent(agentId),
      taskId: workspace?.taskId ?? ""
    )
  }

  private func distinctByTask(_ workspaces: [AgentWorkspace]) -> [AgentWorkspace] {
    var seen = Set<String>()
    return workspaces.filter { seen.insert($0.taskId).inserted }
  }

  private static func ordered(_ samples: [AgentMemoryPssSample]) -> [AgentMemoryPssSample] {
    samples.sorted {
      if $0.sampledAtMillis == $1.sampledAtMillis {
        return $0.id < $1.id
      }
      return $0.sampledAtMillis < $1.sampledAtMillis
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static let pruneEveryCaptures = 24
}

enum AgentMemoryPssRuntime {
  private static let lock = NSLock()
  private static let queue = DispatchQueue(label: "GalaxySSI.AgentMemoryPss")
  private static var monitor: AgentMemoryPssMonitor?
  private static var activeWorkspaces: (() -> [AgentWorkspace])?
  private static var pendingWorkspaces: [AgentWorkspace] = []
  private static var timer: DispatchSourceTimer?

  static func start(
    defaults: UserDefaults = .standard,
    activeWorkspaces: @escaping () -> [AgentWorkspace]
  ) {
    locked {
      self.activeWorkspaces = activeWorkspaces
      AgentSessionMemoryBudgetRuntime.start(defaults: defaults)
      if monitor == nil {
        monitor = AgentMemoryPssMonitor(
          sampler: IOSAgentMemoryPssSampler(),
          store: UserDefaultsAgentMemoryPssSampleStore(defaults: defaults)
        )
      }
      if timer == nil {
        let created = DispatchSource.makeTimerSource(queue: queue)
        created.schedule(deadline: .now(), repeating: .seconds(sampleIntervalSeconds))
        created.setEventHandler {
          captureSafely()
        }
        created.resume()
        timer = created
      }
    }
  }

  static func configureForTesting(
    monitor replacement: AgentMemoryPssMonitor?,
    activeWorkspaces replacementWorkspaces: (() -> [AgentWorkspace])? = nil
  ) {
    locked {
      timer?.cancel()
      timer = nil
      monitor = replacement
      activeWorkspaces = replacementWorkspaces
      pendingWorkspaces = []
    }
  }

  static func requestCapture(workspace: AgentWorkspace? = nil) {
    locked {
      if let workspace {
        pendingWorkspaces.append(workspace)
      }
    }
    queue.async {
      captureSafely()
    }
  }

  static func snapshot() -> AgentMemoryPssSnapshot {
    requestCapture()
    let base = locked {
      monitor?.snapshot() ?? AgentMemoryPssSnapshot()
    }
    return AgentMemoryPssSnapshot(
      measurementKind: base.measurementKind,
      sampledAtMillis: base.sampledAtMillis,
      processCurrentBytes: base.processCurrentBytes,
      processPeakBytes: base.processPeakBytes,
      nativeBytes: base.nativeBytes,
      dalvikBytes: base.dalvikBytes,
      otherBytes: base.otherBytes,
      sampleCount: base.sampleCount,
      byAgent: base.byAgent,
      bySession: base.bySession,
      byProvider: base.byProvider,
      sessionBudget: AgentSessionMemoryBudgetRuntime.snapshot()
    )
  }

  private static func captureSafely() {
    let context = locked { () -> (AgentMemoryPssMonitor?, [AgentWorkspace], (() -> [AgentWorkspace])?) in
      let pending = pendingWorkspaces
      pendingWorkspaces = []
      return (monitor, pending, activeWorkspaces)
    }
    guard let monitor = context.0 else {
      return
    }
    let active = (context.2?() ?? []) + context.1
    let latestByTask = Dictionary(grouping: active, by: \.taskId)
      .compactMap { _, candidates in
        candidates.max {
          if $0.revision == $1.revision {
            return $0.updatedAtMillis < $1.updatedAtMillis
          }
          return $0.revision < $1.revision
        }
      }
    _ = monitor.capture(activeWorkspaces: latestByTask)
  }

  private static func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static let sampleIntervalSeconds = 5
}
