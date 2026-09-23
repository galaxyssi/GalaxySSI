import CryptoKit
import Foundation

enum AgentLatencyStage: String, Codable, CaseIterable {
  case phoneSendStarted = "phone_send_started"
  case phonePublishStarted = "phone_publish_started"
  case phoneRequestQueued = "phone_request_queued"
  case phoneResponseReceived = "phone_response_received"
  case phoneFirstOutputVisible = "phone_first_output_visible"
  case phoneFinalReceived = "phone_final_received"
  case phoneFinalOutputVisible = "phone_final_output_visible"
  case phoneRuntimeActionDispatchStarted = "phone_runtime_action_dispatch_started"
  case phoneRuntimeActionDispatchFinished = "phone_runtime_action_dispatch_finished"
  case phoneRuntimeScreenObserveStarted = "phone_runtime_screen_observe_started"
  case phoneRuntimeScreenObserveFinished = "phone_runtime_screen_observe_finished"
  case phoneRuntimeReceiptObserveStarted = "phone_runtime_receipt_observe_started"
  case phoneRuntimeReceiptObserveFinished = "phone_runtime_receipt_observe_finished"
  case phoneRuntimeResultVerifyStarted = "phone_runtime_result_verify_started"
  case phoneRuntimeResultVerifyFinished = "phone_runtime_result_verify_finished"
  case phoneRuntimeImagePrepareStarted = "phone_runtime_image_prepare_started"
  case phoneRuntimeImagePrepareFinished = "phone_runtime_image_prepare_finished"
  case phoneRuntimeImageOriginalProbeStarted = "phone_runtime_image_original_probe_started"
  case phoneRuntimeImageOriginalProbeFinished = "phone_runtime_image_original_probe_finished"
  case phoneRuntimeImageDecodeStarted = "phone_runtime_image_decode_started"
  case phoneRuntimeImageDecodeFinished = "phone_runtime_image_decode_finished"
  case phoneRuntimeImageEncodeStarted = "phone_runtime_image_encode_started"
  case phoneRuntimeImageEncodeFinished = "phone_runtime_image_encode_finished"
  case phoneModelRequestStarted = "phone_model_request_started"
  case phoneModelRequestFinished = "phone_model_request_finished"
  case phoneModelClientLockWaitStarted = "phone_model_client_lock_wait_started"
  case phoneModelClientLockWaitFinished = "phone_model_client_lock_wait_finished"
  case phoneModelWorkerLockWaitStarted = "phone_model_worker_lock_wait_started"
  case phoneModelWorkerLockWaitFinished = "phone_model_worker_lock_wait_finished"
  case phoneModelServiceBindStarted = "phone_model_service_bind_started"
  case phoneModelServiceBindFinished = "phone_model_service_bind_finished"
  case phoneModelProcessRoundtripStarted = "phone_model_process_roundtrip_started"
  case phoneModelProcessRoundtripFinished = "phone_model_process_roundtrip_finished"
  case phoneModelServiceQueueStarted = "phone_model_service_queue_started"
  case phoneModelServiceQueueFinished = "phone_model_service_queue_finished"
  case phoneModelPreflightStarted = "phone_model_preflight_started"
  case phoneModelPreflightFinished = "phone_model_preflight_finished"
  case phoneModelSdkInitStarted = "phone_model_sdk_init_started"
  case phoneModelSdkInitFinished = "phone_model_sdk_init_finished"
  case phoneModelLoadStarted = "phone_model_load_started"
  case phoneModelLoadFinished = "phone_model_load_finished"
  case phoneModelReuseStarted = "phone_model_reuse_started"
  case phoneModelReuseFinished = "phone_model_reuse_finished"
  case phoneModelGenerateStarted = "phone_model_generate_started"
  case phoneModelGenerateFinished = "phone_model_generate_finished"
  case phoneModelFirstTokenStarted = "phone_model_first_token_started"
  case phoneModelFirstTokenFinished = "phone_model_first_token_finished"
  case phoneModelReleaseStarted = "phone_model_release_started"
  case phoneModelReleaseFinished = "phone_model_release_finished"
}

struct AgentLatencyPoint: Codable, Equatable {
  var traceId: String
  var clockId: String
  var stage: AgentLatencyStage
  var monotonicNs: Int64
  var wallClockMs: Int64
  var operationId: String = ""
  var outcome: String

  enum CodingKeys: String, CodingKey {
    case traceId = "trace_id"
    case clockId = "clock_id"
    case stage
    case monotonicNs = "monotonic_ns"
    case wallClockMs = "wall_clock_ms"
    case operationId = "operation_id"
    case outcome
  }
}

extension AgentLatencyPoint {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    traceId = try container.decode(String.self, forKey: .traceId)
    clockId = try container.decode(String.self, forKey: .clockId)
    stage = try container.decode(AgentLatencyStage.self, forKey: .stage)
    monotonicNs = try container.decode(Int64.self, forKey: .monotonicNs)
    wallClockMs = try container.decode(Int64.self, forKey: .wallClockMs)
    operationId = try container.decodeIfPresent(String.self, forKey: .operationId) ?? ""
    outcome = try container.decode(String.self, forKey: .outcome)
  }
}

struct AgentLatencyMetric: Equatable {
  var count: Int
  var incomplete: Int
  var unsuccessful: Int
  var p50Ms: Double?
  var p95Ms: Double?
  var p99Ms: Double?
}

enum AgentLatencyContract {
  static let schema = "galaxyssi.agent-latency.v1"
  static let eventLimit = 8_000
  static let metricPairs: [(name: String, start: AgentLatencyStage, end: AgentLatencyStage)] = [
    ("phone_context_route_ms", .phoneSendStarted, .phonePublishStarted),
    ("phone_send_prepare_ms", .phoneSendStarted, .phoneRequestQueued),
    ("phone_send_first_visible_ms", .phoneSendStarted, .phoneFirstOutputVisible),
    ("phone_publish_prepare_ms", .phonePublishStarted, .phoneRequestQueued),
    ("phone_response_roundtrip_ms", .phoneRequestQueued, .phoneResponseReceived),
    ("phone_connector_first_visible_ms", .phonePublishStarted, .phoneFirstOutputVisible),
    ("phone_connector_complete_visible_ms", .phonePublishStarted, .phoneFinalOutputVisible),
    ("phone_render_ms", .phoneResponseReceived, .phoneFirstOutputVisible),
    ("phone_runtime_action_dispatch_ms", .phoneRuntimeActionDispatchStarted, .phoneRuntimeActionDispatchFinished),
    ("phone_runtime_screen_observe_ms", .phoneRuntimeScreenObserveStarted, .phoneRuntimeScreenObserveFinished),
    ("phone_runtime_receipt_observe_ms", .phoneRuntimeReceiptObserveStarted, .phoneRuntimeReceiptObserveFinished),
    ("phone_runtime_result_verify_ms", .phoneRuntimeResultVerifyStarted, .phoneRuntimeResultVerifyFinished),
    ("phone_runtime_image_prepare_ms", .phoneRuntimeImagePrepareStarted, .phoneRuntimeImagePrepareFinished),
    ("phone_runtime_image_original_probe_ms", .phoneRuntimeImageOriginalProbeStarted, .phoneRuntimeImageOriginalProbeFinished),
    ("phone_runtime_image_decode_ms", .phoneRuntimeImageDecodeStarted, .phoneRuntimeImageDecodeFinished),
    ("phone_runtime_image_encode_ms", .phoneRuntimeImageEncodeStarted, .phoneRuntimeImageEncodeFinished),
    ("phone_model_request_ms", .phoneModelRequestStarted, .phoneModelRequestFinished),
    ("phone_model_client_lock_wait_ms", .phoneModelClientLockWaitStarted, .phoneModelClientLockWaitFinished),
    ("phone_model_worker_lock_wait_ms", .phoneModelWorkerLockWaitStarted, .phoneModelWorkerLockWaitFinished),
    ("phone_model_service_bind_ms", .phoneModelServiceBindStarted, .phoneModelServiceBindFinished),
    ("phone_model_process_roundtrip_ms", .phoneModelProcessRoundtripStarted, .phoneModelProcessRoundtripFinished),
    ("phone_model_service_queue_ms", .phoneModelServiceQueueStarted, .phoneModelServiceQueueFinished),
    ("phone_model_preflight_ms", .phoneModelPreflightStarted, .phoneModelPreflightFinished),
    ("phone_model_sdk_init_ms", .phoneModelSdkInitStarted, .phoneModelSdkInitFinished),
    ("phone_model_load_ms", .phoneModelLoadStarted, .phoneModelLoadFinished),
    ("phone_model_reuse_ms", .phoneModelReuseStarted, .phoneModelReuseFinished),
    ("phone_model_generate_ms", .phoneModelGenerateStarted, .phoneModelGenerateFinished),
    ("phone_model_first_token_ms", .phoneModelFirstTokenStarted, .phoneModelFirstTokenFinished),
    ("phone_model_release_ms", .phoneModelReleaseStarted, .phoneModelReleaseFinished)
  ]

  static func opaqueId(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func valid(_ point: AgentLatencyPoint) -> Bool {
    point.traceId.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
      && point.clockId.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil
      && (point.operationId.isEmpty
        || point.operationId.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil)
      && point.monotonicNs >= 0
      && point.wallClockMs >= 0
      && allowedOutcomes.contains(point.outcome)
  }

  static func summarize(_ points: [AgentLatencyPoint]) -> [String: AgentLatencyMetric] {
    let groups = Dictionary(
      grouping: points.filter(valid),
      by: { "\($0.traceId):\($0.clockId):\($0.operationId)" }
    )
    return Dictionary(uniqueKeysWithValues: metricPairs.map { pair in
      var incomplete = 0
      var unsuccessful = 0
      var samples: [Double] = []
      for group in groups.values {
        guard let start = group.filter({ $0.stage == pair.start }).map(\.monotonicNs).min() else {
          continue
        }
        guard let end = group
          .filter({ $0.stage == pair.end && $0.monotonicNs >= start })
          .min(by: { $0.monotonicNs < $1.monotonicNs }) else {
          incomplete += 1
          continue
        }
        if unsuccessfulOutcomes.contains(end.outcome) {
          unsuccessful += 1
        } else {
          samples.append(Double(end.monotonicNs - start) / 1_000_000)
        }
      }
      samples.sort()
      return (pair.name, AgentLatencyMetric(
        count: samples.count,
        incomplete: incomplete,
        unsuccessful: unsuccessful,
        p50Ms: percentile(samples, 0.50),
        p95Ms: percentile(samples, 0.95),
        p99Ms: percentile(samples, 0.99)
      ))
    })
  }

  private static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let index = min(max(Int(ceil(fraction * Double(values.count))) - 1, 0), values.count - 1)
    return values[index]
  }

  private static let allowedOutcomes: Set<String> = ["", "completed", "failed", "cancelled", "timed_out"]
  private static let unsuccessfulOutcomes: Set<String> = ["failed", "cancelled", "timed_out"]
}

enum AgentRuntimeTimingPhase: String, CaseIterable {
  case actionDispatch = "action_dispatch"
  case screenObserve = "screen_observe"
  case receiptObserve = "receipt_observe"
  case resultVerify = "result_verify"
  case imagePrepare = "image_prepare"
  case imageOriginalProbe = "image_original_probe"
  case imageDecode = "image_decode"
  case imageEncode = "image_encode"

  var boundaries: (start: AgentLatencyStage, finish: AgentLatencyStage) {
    switch self {
    case .actionDispatch:
      return (.phoneRuntimeActionDispatchStarted, .phoneRuntimeActionDispatchFinished)
    case .screenObserve:
      return (.phoneRuntimeScreenObserveStarted, .phoneRuntimeScreenObserveFinished)
    case .receiptObserve:
      return (.phoneRuntimeReceiptObserveStarted, .phoneRuntimeReceiptObserveFinished)
    case .resultVerify:
      return (.phoneRuntimeResultVerifyStarted, .phoneRuntimeResultVerifyFinished)
    case .imagePrepare:
      return (.phoneRuntimeImagePrepareStarted, .phoneRuntimeImagePrepareFinished)
    case .imageOriginalProbe:
      return (.phoneRuntimeImageOriginalProbeStarted, .phoneRuntimeImageOriginalProbeFinished)
    case .imageDecode:
      return (.phoneRuntimeImageDecodeStarted, .phoneRuntimeImageDecodeFinished)
    case .imageEncode:
      return (.phoneRuntimeImageEncodeStarted, .phoneRuntimeImageEncodeFinished)
    }
  }
}

/// Content-free synchronous spans. Instrumentation never replaces operation results or errors.
struct AgentRuntimeTiming {
  var tracer: AgentLatencyTracer?

  func measure<T>(
    taskId: String,
    phase: AgentRuntimeTimingPhase,
    outcome: (T) -> String = { _ in "completed" },
    operation: () throws -> T
  ) rethrows -> T {
    let normalizedTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let tracer, !normalizedTaskId.isEmpty else { return try operation() }
    let operationId = UUID().uuidString
    let boundaries = phase.boundaries
    tracer.recordOpaque(
      taskId: normalizedTaskId,
      stage: boundaries.start,
      operationId: operationId
    )
    var resultOutcome = "failed"
    defer {
      tracer.recordOpaque(
        taskId: normalizedTaskId,
        stage: boundaries.finish,
        operationId: operationId,
        outcome: resultOutcome
      )
    }
    do {
      let result = try operation()
      resultOutcome = Self.normalizedOutcome(outcome(result))
      return result
    } catch {
      if error is CancellationError { resultOutcome = "cancelled" }
      throw error
    }
  }

  private static func normalizedOutcome(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["completed", "failed", "cancelled", "timed_out"].contains(normalized)
      ? normalized
      : "failed"
  }
}

enum AgentModelTimingPhase: String, CaseIterable {
  case request
  case clientLockWait = "client_lock_wait"
  case workerLockWait = "worker_lock_wait"
  case serviceBind = "service_bind"
  case processRoundtrip = "process_roundtrip"
  case serviceQueue = "service_queue"
  case preflight
  case sdkInit = "sdk_init"
  case load
  case reuse
  case generate
  case firstToken = "first_token"
  case release

  var boundaries: (AgentLatencyStage, AgentLatencyStage) {
    switch self {
    case .request: return (.phoneModelRequestStarted, .phoneModelRequestFinished)
    case .clientLockWait: return (.phoneModelClientLockWaitStarted, .phoneModelClientLockWaitFinished)
    case .workerLockWait: return (.phoneModelWorkerLockWaitStarted, .phoneModelWorkerLockWaitFinished)
    case .serviceBind: return (.phoneModelServiceBindStarted, .phoneModelServiceBindFinished)
    case .processRoundtrip: return (.phoneModelProcessRoundtripStarted, .phoneModelProcessRoundtripFinished)
    case .serviceQueue: return (.phoneModelServiceQueueStarted, .phoneModelServiceQueueFinished)
    case .preflight: return (.phoneModelPreflightStarted, .phoneModelPreflightFinished)
    case .sdkInit: return (.phoneModelSdkInitStarted, .phoneModelSdkInitFinished)
    case .load: return (.phoneModelLoadStarted, .phoneModelLoadFinished)
    case .reuse: return (.phoneModelReuseStarted, .phoneModelReuseFinished)
    case .generate: return (.phoneModelGenerateStarted, .phoneModelGenerateFinished)
    case .firstToken: return (.phoneModelFirstTokenStarted, .phoneModelFirstTokenFinished)
    case .release: return (.phoneModelReleaseStarted, .phoneModelReleaseFinished)
    }
  }
}

final class AgentModelTiming {
  private let taskId: String
  private let tracer: AgentLatencyTracer?

  var taskIdentity: String { taskId }

  init(taskId: String, tracer: AgentLatencyTracer? = AgentLatencyTelemetry.shared) {
    self.taskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.tracer = self.taskId.isEmpty ? nil : tracer
  }

  func begin(_ phase: AgentModelTimingPhase) -> Span {
    guard let tracer else { return Span(finish: nil) }
    let operationId = UUID().uuidString
    let boundaries = phase.boundaries
    tracer.recordOpaque(taskId: taskId, stage: boundaries.0, operationId: operationId)
    return Span { outcome in
      tracer.recordOpaque(
        taskId: self.taskId,
        stage: boundaries.1,
        operationId: operationId,
        outcome: outcome
      )
    }
  }

  func measure<T>(_ phase: AgentModelTimingPhase, operation: () throws -> T) rethrows -> T {
    let span = begin(phase)
    defer { span.close() }
    do {
      let result = try operation()
      span.completed()
      return result
    } catch {
      span.failed(error)
      throw error
    }
  }

  func measureAsync<T>(
    _ phase: AgentModelTimingPhase,
    operation: () async throws -> T
  ) async rethrows -> T {
    let span = begin(phase)
    defer { span.close() }
    do {
      let result = try await operation()
      span.completed()
      return result
    } catch {
      span.failed(error)
      throw error
    }
  }

  final class Span {
    private let lock = NSLock()
    private var finish: ((String) -> Void)?

    fileprivate init(finish: ((String) -> Void)?) {
      self.finish = finish
    }

    func completed() { end("completed") }

    func failed(_ error: Error) {
      end(error is CancellationError ? "cancelled" : "failed")
    }

    func close() { end("failed") }

    private func end(_ outcome: String) {
      lock.lock()
      let completion = finish
      finish = nil
      lock.unlock()
      completion?(outcome)
    }
  }
}

final class AgentLatencyJournal {
  private let lock = NSLock()
  private let fileURL: URL
  private let previousURL: URL
  private let maxEvents: Int
  private let byteLimit: Int64
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var memory: [AgentLatencyPoint] = []

  init(
    fileURL: URL = AgentLatencyJournal.defaultFileURL(),
    maxEvents: Int = AgentLatencyContract.eventLimit,
    byteLimit: Int64 = 2 * 1024 * 1024
  ) {
    self.fileURL = fileURL
    self.previousURL = fileURL.deletingLastPathComponent()
      .appendingPathComponent("agent_latency_v1.previous.jsonl")
    self.maxEvents = max(1, maxEvents)
    self.byteLimit = max(1, byteLimit)
  }

  static func defaultFileURL() -> URL {
    AgentNativeToolDefaultStorePaths.applicationSupportRootURL()
      .appendingPathComponent("diagnostics", isDirectory: true)
      .appendingPathComponent("agent_latency_v1.jsonl")
  }

  func append(_ point: AgentLatencyPoint) {
    guard AgentLatencyContract.valid(point) else { return }
    lock.lock()
    defer { lock.unlock() }
    memory.append(point)
    memory = Array(memory.suffix(maxEvents))
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try rotateIfNeeded()
      var data = try encoder.encode(point)
      data.append(Data("\n".utf8))
      if FileManager.default.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
      } else {
        try data.write(to: fileURL, options: .atomic)
      }
    } catch {
      return
    }
  }

  func snapshot() -> [AgentLatencyPoint] {
    lock.lock()
    defer { lock.unlock() }
    var seen: Set<String> = []
    let loaded = [previousURL, fileURL].flatMap(load) + memory
    return Array(loaded.filter { point in
      let key = "\(point.traceId):\(point.clockId):\(point.stage.rawValue):\(point.monotonicNs)"
      return AgentLatencyContract.valid(point) && seen.insert(key).inserted
    }.suffix(maxEvents))
  }

  private func load(_ url: URL) -> [AgentLatencyPoint] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap {
      try? decoder.decode(AgentLatencyPoint.self, from: Data($0.utf8))
    }
  }

  private func rotateIfNeeded() throws {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          let size = attributes[.size] as? NSNumber,
          size.int64Value >= byteLimit else { return }
    try? FileManager.default.removeItem(at: previousURL)
    try FileManager.default.moveItem(at: fileURL, to: previousURL)
  }
}

final class AgentLatencyTracer {
  private let journal: AgentLatencyJournal
  private let monotonicNs: () -> Int64
  private let wallClockMs: () -> Int64
  private let clockId: String
  private let lock = NSLock()
  private var seen: Set<String> = []
  private var outcomes: [String: String] = [:]

  init(
    journal: AgentLatencyJournal,
    monotonicNs: @escaping () -> Int64 = AgentLatencyTelemetry.currentMonotonicNs,
    wallClockMs: @escaping () -> Int64 = AgentLatencyTelemetry.currentWallClockMs,
    clockId: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  ) {
    self.journal = journal
    self.monotonicNs = monotonicNs
    self.wallClockMs = wallClockMs
    self.clockId = clockId
  }

  func record(taskId: String, stage: AgentLatencyStage, outcome: String = "") {
    recordOpaque(taskId: taskId, stage: stage, operationId: "", outcome: outcome)
  }

  func recordOpaque(
    taskId: String,
    stage: AgentLatencyStage,
    operationId: String,
    outcome: String = ""
  ) {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty else { return }
    let traceId = AgentLatencyContract.opaqueId(cleanTaskId)
    let cleanOperationId = operationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let opaqueOperationId = cleanOperationId.isEmpty ? "" : AgentLatencyContract.opaqueId(cleanOperationId)
    let key = "\(traceId):\(stage.rawValue):\(opaqueOperationId)"
    lock.lock()
    guard seen.insert(key).inserted else {
      lock.unlock()
      return
    }
    if stage == .phoneFinalReceived {
      outcomes[traceId] = normalizedOutcome(outcome)
    }
    if seen.count > AgentLatencyContract.eventLimit {
      seen.removeAll(keepingCapacity: true)
      seen.insert(key)
      outcomes = outcomes.filter { $0.key == traceId }
    }
    lock.unlock()
    journal.append(AgentLatencyPoint(
      traceId: traceId,
      clockId: clockId,
      stage: stage,
      monotonicNs: max(0, monotonicNs()),
      wallClockMs: max(0, wallClockMs()),
      operationId: opaqueOperationId,
      outcome: stage == .phoneFinalReceived ? normalizedOutcome(outcome) : normalizedOutcome(outcome, emptyAllowed: true)
    ))
  }

  func visible(taskId: String, final: Bool) {
    let traceId = AgentLatencyContract.opaqueId(taskId)
    lock.lock()
    let hasResponse = seen.contains("\(traceId):\(AgentLatencyStage.phoneResponseReceived.rawValue):")
    let hasFinal = seen.contains("\(traceId):\(AgentLatencyStage.phoneFinalReceived.rawValue):")
    let outcome = outcomes[traceId] ?? "completed"
    lock.unlock()
    guard hasResponse else { return }
    record(taskId: taskId, stage: .phoneFirstOutputVisible)
    if final && hasFinal {
      record(taskId: taskId, stage: .phoneFinalOutputVisible, outcome: outcome)
    }
  }

  func summary() -> [String: AgentLatencyMetric] {
    AgentLatencyContract.summarize(journal.snapshot())
  }

  private func normalizedOutcome(_ value: String, emptyAllowed: Bool = false) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["failed", "cancelled", "timed_out"].contains(normalized) { return normalized }
    return emptyAllowed && normalized.isEmpty ? "" : "completed"
  }
}

enum AgentLatencyTelemetry {
  static let shared = AgentLatencyTracer(journal: AgentLatencyJournal())
  static let runtime = AgentRuntimeTiming(tracer: shared)

  static func currentMonotonicNs() -> Int64 {
    Int64(clamping: DispatchTime.now().uptimeNanoseconds)
  }

  static func currentWallClockMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}
