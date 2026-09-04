import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum AgentMemoryMeasurementKind: String, Codable {
  case androidPss = "android_pss"
  case iosResidentMemory = "ios_resident_memory"
}

struct AgentMemoryPssReading: Codable, Equatable {
  var totalBytes: Int64
  var nativeBytes: Int64
  var dalvikBytes: Int64
  var otherBytes: Int64
  var measurementKind: AgentMemoryMeasurementKind

  init(
    totalBytes: Int64,
    nativeBytes: Int64 = 0,
    dalvikBytes: Int64 = 0,
    otherBytes: Int64 = 0,
    measurementKind: AgentMemoryMeasurementKind = .iosResidentMemory
  ) {
    self.totalBytes = max(0, totalBytes)
    self.nativeBytes = max(0, nativeBytes)
    self.dalvikBytes = max(0, dalvikBytes)
    self.otherBytes = max(0, otherBytes)
    self.measurementKind = measurementKind
  }
}

protocol AgentMemoryPssSampler {
  func sample() -> AgentMemoryPssReading
}

final class IOSAgentMemoryPssSampler: AgentMemoryPssSampler {
  func sample() -> AgentMemoryPssReading {
    #if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return AgentMemoryPssReading(totalBytes: 0)
    }
    return AgentMemoryPssReading(totalBytes: Self.int64(info.resident_size))
    #else
    return AgentMemoryPssReading(totalBytes: 0)
    #endif
  }

  #if canImport(Darwin)
  private static func int64(_ value: mach_vm_size_t) -> Int64 {
    value > UInt64(Int64.max) ? Int64.max : Int64(value)
  }
  #endif
}

struct AgentSessionMemoryBaseline: Codable, Equatable {
  var processBytes: Int64
  var capturedAtMillis: Int64
}

struct AgentSessionMemoryBudgetSample: Codable, Equatable, Identifiable {
  var id: String
  var conversationId: String
  var sampledAtMillis: Int64
  var beforeBytes: Int64
  var afterBytes: Int64
  var incrementalBytes: Int64
  var targetBytes: Int64

  var withinBudget: Bool {
    incrementalBytes <= targetBytes
  }

  enum CodingKeys: String, CodingKey {
    case id
    case conversationId = "conversation_id"
    case sampledAtMillis = "sampled_at_millis"
    case beforeBytes = "before_bytes"
    case afterBytes = "after_bytes"
    case incrementalBytes = "incremental_bytes"
    case targetBytes = "target_bytes"
  }

  init(
    id: String,
    conversationId: String,
    sampledAtMillis: Int64,
    beforeBytes: Int64,
    afterBytes: Int64,
    incrementalBytes: Int64,
    targetBytes: Int64
  ) {
    self.id = id
    self.conversationId = conversationId
    self.sampledAtMillis = sampledAtMillis
    self.beforeBytes = max(0, beforeBytes)
    self.afterBytes = max(0, afterBytes)
    self.incrementalBytes = max(0, incrementalBytes)
    self.targetBytes = max(1, targetBytes)
  }
}

struct AgentSessionMemoryBudgetSnapshot: Codable, Equatable {
  var targetBytes: Int64
  var latestIncrementalBytes: Int64
  var peakIncrementalBytes: Int64
  var averageIncrementalBytes: Int64
  var sampleCount: Int
  var exceededCount: Int
  var latestConversationId: String
  var latestSampledAtMillis: Int64

  var withinBudget: Bool {
    latestIncrementalBytes <= targetBytes
  }

  enum CodingKeys: String, CodingKey {
    case targetBytes = "target_bytes"
    case latestIncrementalBytes = "latest_incremental_bytes"
    case peakIncrementalBytes = "peak_incremental_bytes"
    case averageIncrementalBytes = "average_incremental_bytes"
    case sampleCount = "sample_count"
    case exceededCount = "exceeded_count"
    case latestConversationId = "latest_conversation_id"
    case latestSampledAtMillis = "latest_sampled_at_millis"
  }

  init(
    targetBytes: Int64 = AgentSessionMemoryBudgetMonitor.defaultTargetBytes,
    latestIncrementalBytes: Int64 = 0,
    peakIncrementalBytes: Int64 = 0,
    averageIncrementalBytes: Int64 = 0,
    sampleCount: Int = 0,
    exceededCount: Int = 0,
    latestConversationId: String = "",
    latestSampledAtMillis: Int64 = 0
  ) {
    self.targetBytes = max(1, targetBytes)
    self.latestIncrementalBytes = max(0, latestIncrementalBytes)
    self.peakIncrementalBytes = max(0, peakIncrementalBytes)
    self.averageIncrementalBytes = max(0, averageIncrementalBytes)
    self.sampleCount = max(0, sampleCount)
    self.exceededCount = max(0, exceededCount)
    self.latestConversationId = latestConversationId
    self.latestSampledAtMillis = max(0, latestSampledAtMillis)
  }
}

protocol AgentSessionMemoryBudgetStore {
  func append(_ sample: AgentSessionMemoryBudgetSample)
  func recent(limit: Int, sinceMillis: Int64) -> [AgentSessionMemoryBudgetSample]
  func prune(beforeMillis: Int64, maxSamples: Int)
}

final class InMemoryAgentSessionMemoryBudgetStore: AgentSessionMemoryBudgetStore {
  private let lock = NSLock()
  private var samples: [AgentSessionMemoryBudgetSample]

  init(samples: [AgentSessionMemoryBudgetSample] = []) {
    self.samples = Self.ordered(samples)
  }

  func append(_ sample: AgentSessionMemoryBudgetSample) {
    locked {
      samples.append(sample)
      samples = Self.ordered(samples)
    }
  }

  func recent(limit: Int, sinceMillis: Int64) -> [AgentSessionMemoryBudgetSample] {
    locked {
      Array(
        Self.ordered(samples.filter { $0.sampledAtMillis >= sinceMillis })
          .suffix(max(1, limit))
      )
    }
  }

  func prune(beforeMillis: Int64, maxSamples: Int) {
    locked {
      samples = Array(
        Self.ordered(samples.filter { $0.sampledAtMillis >= beforeMillis })
          .suffix(max(1, maxSamples))
      )
    }
  }

  private static func ordered(_ samples: [AgentSessionMemoryBudgetSample]) -> [AgentSessionMemoryBudgetSample] {
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

final class UserDefaultsAgentSessionMemoryBudgetStore: AgentSessionMemoryBudgetStore {
  static let defaultKey = "galaxyssi_agent_session_memory_budget"

  private struct Document: Codable {
    var version: Int
    var samples: [AgentSessionMemoryBudgetSample]
  }

  private let defaults: UserDefaults
  private let key: String
  private let lock = NSLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentSessionMemoryBudgetStore.defaultKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentSessionMemoryBudgetStore.defaultKey
  ) {
    defaults.removeObject(forKey: key)
  }

  func append(_ sample: AgentSessionMemoryBudgetSample) {
    locked {
      persist(Self.ordered(load() + [sample]))
    }
  }

  func recent(limit: Int, sinceMillis: Int64) -> [AgentSessionMemoryBudgetSample] {
    locked {
      Array(
        Self.ordered(load().filter { $0.sampledAtMillis >= sinceMillis })
          .suffix(max(1, limit))
      )
    }
  }

  func prune(beforeMillis: Int64, maxSamples: Int) {
    locked {
      persist(
        Array(
          Self.ordered(load().filter { $0.sampledAtMillis >= beforeMillis })
            .suffix(max(1, maxSamples))
        )
      )
    }
  }

  private static func ordered(_ samples: [AgentSessionMemoryBudgetSample]) -> [AgentSessionMemoryBudgetSample] {
    samples.sorted {
      if $0.sampledAtMillis == $1.sampledAtMillis {
        return $0.id < $1.id
      }
      return $0.sampledAtMillis < $1.sampledAtMillis
    }
  }

  private func load() -> [AgentSessionMemoryBudgetSample] {
    guard let data = defaults.data(forKey: key),
          let decoded = try? JSONDecoder().decode(Document.self, from: data) else {
      return []
    }
    return Self.ordered(decoded.samples)
  }

  private func persist(_ samples: [AgentSessionMemoryBudgetSample]) {
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

final class AgentSessionMemoryBudgetMonitor {
  static let defaultTargetBytes: Int64 = 20 * 1024 * 1024
  static let defaultRetentionMillis: Int64 = 30 * 24 * 60 * 60 * 1_000
  static let defaultMaxSamples = 512

  private let sampler: AgentMemoryPssSampler
  private let store: AgentSessionMemoryBudgetStore
  private let clock: () -> Int64
  private let targetBytes: Int64
  private let retentionMillis: Int64
  private let maxSamples: Int
  private let idGenerator: () -> String
  private let lock = NSLock()
  private var history: [AgentSessionMemoryBudgetSample]
  private var cachedSnapshot: AgentSessionMemoryBudgetSnapshot

  init(
    sampler: AgentMemoryPssSampler,
    store: AgentSessionMemoryBudgetStore,
    clock: @escaping () -> Int64 = AgentMemoryClock.nowMillis,
    targetBytes: Int64 = AgentSessionMemoryBudgetMonitor.defaultTargetBytes,
    retentionMillis: Int64 = AgentSessionMemoryBudgetMonitor.defaultRetentionMillis,
    maxSamples: Int = AgentSessionMemoryBudgetMonitor.defaultMaxSamples,
    idGenerator: @escaping () -> String = { UUID().uuidString }
  ) {
    self.sampler = sampler
    self.store = store
    self.clock = clock
    self.targetBytes = max(1, targetBytes)
    self.retentionMillis = max(0, retentionMillis)
    self.maxSamples = max(1, maxSamples)
    self.idGenerator = idGenerator
    let restored = store.recent(limit: self.maxSamples, sinceMillis: clock() - self.retentionMillis)
    self.history = Self.ordered(restored)
    self.cachedSnapshot = Self.aggregate(restored, targetBytes: self.targetBytes)
  }

  func begin() -> AgentSessionMemoryBaseline {
    let reading = sampler.sample()
    return AgentSessionMemoryBaseline(
      processBytes: max(0, reading.totalBytes),
      capturedAtMillis: clock()
    )
  }

  @discardableResult
  func complete(
    conversationId: String,
    baseline: AgentSessionMemoryBaseline
  ) -> AgentSessionMemoryBudgetSnapshot {
    locked {
      let after = max(0, sampler.sample().totalBytes)
      let sampledAt = clock()
      let sample = AgentSessionMemoryBudgetSample(
        id: idGenerator(),
        conversationId: conversationId.trimmingCharacters(in: .whitespacesAndNewlines),
        sampledAtMillis: sampledAt,
        beforeBytes: baseline.processBytes,
        afterBytes: after,
        incrementalBytes: after - max(0, baseline.processBytes),
        targetBytes: targetBytes
      )
      store.append(sample)
      history.append(sample)
      let cutoff = sampledAt - retentionMillis
      history = Array(
        Self.ordered(history.filter { $0.sampledAtMillis >= cutoff })
          .suffix(maxSamples)
      )
      store.prune(beforeMillis: cutoff, maxSamples: maxSamples)
      cachedSnapshot = Self.aggregate(history, targetBytes: targetBytes)
      return cachedSnapshot
    }
  }

  func snapshot() -> AgentSessionMemoryBudgetSnapshot {
    locked {
      cachedSnapshot
    }
  }

  static func aggregate(
    _ samples: [AgentSessionMemoryBudgetSample],
    targetBytes: Int64 = AgentSessionMemoryBudgetMonitor.defaultTargetBytes
  ) -> AgentSessionMemoryBudgetSnapshot {
    let ordered = ordered(samples)
    guard let latest = ordered.last else {
      return AgentSessionMemoryBudgetSnapshot(targetBytes: targetBytes)
    }
    let total = ordered.reduce(Int64(0)) { $0 + $1.incrementalBytes }
    return AgentSessionMemoryBudgetSnapshot(
      targetBytes: targetBytes,
      latestIncrementalBytes: latest.incrementalBytes,
      peakIncrementalBytes: ordered.map(\.incrementalBytes).max() ?? 0,
      averageIncrementalBytes: total / Int64(max(1, ordered.count)),
      sampleCount: ordered.count,
      exceededCount: ordered.filter { $0.incrementalBytes > targetBytes }.count,
      latestConversationId: latest.conversationId,
      latestSampledAtMillis: latest.sampledAtMillis
    )
  }

  private static func ordered(_ samples: [AgentSessionMemoryBudgetSample]) -> [AgentSessionMemoryBudgetSample] {
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

enum AgentSessionMemoryBudgetRuntime {
  private static let lock = NSLock()
  private static let queue = DispatchQueue(label: "GalaxySSI.AgentSessionMemoryBudget")
  private static var monitor: AgentSessionMemoryBudgetMonitor?

  static func start(defaults: UserDefaults = .standard) {
    locked {
      if monitor == nil {
        monitor = AgentSessionMemoryBudgetMonitor(
          sampler: IOSAgentMemoryPssSampler(),
          store: UserDefaultsAgentSessionMemoryBudgetStore(defaults: defaults)
        )
      }
    }
  }

  static func configureForTesting(_ replacement: AgentSessionMemoryBudgetMonitor?) {
    locked {
      monitor = replacement
    }
  }

  static func begin() -> AgentSessionMemoryBaseline? {
    locked {
      monitor?.begin()
    }
  }

  static func complete(conversationId: String, baseline: AgentSessionMemoryBaseline?) {
    guard let baseline else {
      return
    }
    let active = locked {
      monitor
    }
    queue.async {
      _ = active?.complete(conversationId: conversationId, baseline: baseline)
    }
  }

  static func snapshot() -> AgentSessionMemoryBudgetSnapshot {
    locked {
      monitor?.snapshot() ?? AgentSessionMemoryBudgetSnapshot()
    }
  }

  private static func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
