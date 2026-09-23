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
  case phonePlanningTotalStarted = "phone_planning_total_started"
  case phonePlanningTotalFinished = "phone_planning_total_finished"
  case phonePlanningProgressStarted = "phone_planning_progress_started"
  case phonePlanningProgressFinished = "phone_planning_progress_finished"
  case phonePlanningInventoryStarted = "phone_planning_inventory_started"
  case phonePlanningInventoryFinished = "phone_planning_inventory_finished"
  case phonePlanningGoalStarted = "phone_planning_goal_started"
  case phonePlanningGoalFinished = "phone_planning_goal_finished"
  case phonePlanningContextStarted = "phone_planning_context_started"
  case phonePlanningContextFinished = "phone_planning_context_finished"
  case phonePlanningConversationStarted = "phone_planning_conversation_started"
  case phonePlanningConversationFinished = "phone_planning_conversation_finished"
  case phonePlanningPromptStarted = "phone_planning_prompt_started"
  case phonePlanningPromptFinished = "phone_planning_prompt_finished"
  case phonePlanningPlanStarted = "phone_planning_plan_started"
  case phonePlanningPlanFinished = "phone_planning_plan_finished"
}

struct AgentLatencyPoint: Codable, Equatable {
  var traceId: String
  var clockId: String
  var stage: AgentLatencyStage
  var monotonicNs: Int64
  var wallClockMs: Int64
  var outcome: String
  var operationId: String? = nil

  enum CodingKeys: String, CodingKey {
    case traceId = "trace_id"
    case clockId = "clock_id"
    case stage
    case monotonicNs = "monotonic_ns"
    case wallClockMs = "wall_clock_ms"
    case outcome
    case operationId = "operation_id"
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
    ("phone_planning_total_ms", .phonePlanningTotalStarted, .phonePlanningTotalFinished),
    ("phone_planning_progress_ms", .phonePlanningProgressStarted, .phonePlanningProgressFinished),
    ("phone_planning_inventory_ms", .phonePlanningInventoryStarted, .phonePlanningInventoryFinished),
    ("phone_planning_goal_ms", .phonePlanningGoalStarted, .phonePlanningGoalFinished),
    ("phone_planning_context_ms", .phonePlanningContextStarted, .phonePlanningContextFinished),
    ("phone_planning_conversation_ms", .phonePlanningConversationStarted, .phonePlanningConversationFinished),
    ("phone_planning_prompt_ms", .phonePlanningPromptStarted, .phonePlanningPromptFinished),
    ("phone_planning_plan_ms", .phonePlanningPlanStarted, .phonePlanningPlanFinished)
  ]

  static func opaqueId(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func valid(_ point: AgentLatencyPoint) -> Bool {
    point.traceId.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
      && point.clockId.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil
      && point.monotonicNs >= 0
      && point.wallClockMs >= 0
      && (point.operationId == nil || point.operationId?.range(
        of: #"^[a-f0-9]{64}$"#,
        options: .regularExpression
      ) != nil)
      && allowedOutcomes.contains(point.outcome)
  }

  static func summarize(_ points: [AgentLatencyPoint]) -> [String: AgentLatencyMetric] {
    let groups = Dictionary(grouping: points.filter(valid), by: {
      "\($0.traceId):\($0.clockId):\($0.operationId ?? "")"
    })
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
      let key = "\(point.traceId):\(point.clockId):\(point.operationId ?? ""):\(point.stage.rawValue):\(point.monotonicNs)"
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
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty else { return }
    let traceId = AgentLatencyContract.opaqueId(cleanTaskId)
    let key = "\(traceId):\(stage.rawValue)"
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
      outcome: stage == .phoneFinalReceived ? normalizedOutcome(outcome) : normalizedOutcome(outcome, emptyAllowed: true)
    ))
  }

  func recordOpaque(
    taskId: String,
    stage: AgentLatencyStage,
    operationId: String,
    outcome: String = "",
    monotonicNs: Int64? = nil
  ) {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty else { return }
    journal.append(AgentLatencyPoint(
      traceId: AgentLatencyContract.opaqueId(cleanTaskId),
      clockId: clockId,
      stage: stage,
      monotonicNs: max(0, monotonicNs ?? self.monotonicNs()),
      wallClockMs: max(0, wallClockMs()),
      outcome: normalizedOutcome(outcome, emptyAllowed: true),
      operationId: AgentLatencyContract.opaqueId(operationId)
    ))
  }

  func visible(taskId: String, final: Bool) {
    let traceId = AgentLatencyContract.opaqueId(taskId)
    lock.lock()
    let hasResponse = seen.contains("\(traceId):\(AgentLatencyStage.phoneResponseReceived.rawValue)")
    let hasFinal = seen.contains("\(traceId):\(AgentLatencyStage.phoneFinalReceived.rawValue)")
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

enum AgentPlanningTiming {
  private struct Scope {
    var taskId: String
    var tracer: AgentLatencyTracer
  }

  @TaskLocal private static var scope: Scope?

  static func capture<T>(
    taskId: String,
    tracer: AgentLatencyTracer = AgentLatencyTelemetry.shared,
    operation: () async throws -> T
  ) async rethrows -> T {
    let cleanTaskId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTaskId.isEmpty else { return try await operation() }
    return try await $scope.withValue(Scope(taskId: cleanTaskId, tracer: tracer)) {
      try await measureAsync("total", operation: operation)
    }
  }

  static func measure<T>(_ phase: String, operation: () throws -> T) rethrows -> T {
    guard let boundary = boundaries[phase], let scope else { return try operation() }
    let operationId = UUID().uuidString
    scope.tracer.recordOpaque(taskId: scope.taskId, stage: boundary.start, operationId: operationId)
    var outcome = "failed"
    defer {
      scope.tracer.recordOpaque(
        taskId: scope.taskId,
        stage: boundary.finish,
        operationId: operationId,
        outcome: outcome
      )
    }
    do {
      let result = try operation()
      outcome = "completed"
      return result
    } catch {
      if error is CancellationError { outcome = "cancelled" }
      throw error
    }
  }

  private static func measureAsync<T>(
    _ phase: String,
    operation: () async throws -> T
  ) async rethrows -> T {
    guard let boundary = boundaries[phase], let scope else { return try await operation() }
    let operationId = UUID().uuidString
    scope.tracer.recordOpaque(taskId: scope.taskId, stage: boundary.start, operationId: operationId)
    var outcome = "failed"
    defer {
      scope.tracer.recordOpaque(
        taskId: scope.taskId,
        stage: boundary.finish,
        operationId: operationId,
        outcome: outcome
      )
    }
    do {
      let result = try await operation()
      outcome = "completed"
      return result
    } catch {
      if error is CancellationError { outcome = "cancelled" }
      throw error
    }
  }

  private static let boundaries: [String: (start: AgentLatencyStage, finish: AgentLatencyStage)] = [
    "total": (.phonePlanningTotalStarted, .phonePlanningTotalFinished),
    "progress": (.phonePlanningProgressStarted, .phonePlanningProgressFinished),
    "inventory": (.phonePlanningInventoryStarted, .phonePlanningInventoryFinished),
    "goal": (.phonePlanningGoalStarted, .phonePlanningGoalFinished),
    "context": (.phonePlanningContextStarted, .phonePlanningContextFinished),
    "conversation": (.phonePlanningConversationStarted, .phonePlanningConversationFinished),
    "prompt": (.phonePlanningPromptStarted, .phonePlanningPromptFinished),
    "plan": (.phonePlanningPlanStarted, .phonePlanningPlanFinished)
  ]
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
