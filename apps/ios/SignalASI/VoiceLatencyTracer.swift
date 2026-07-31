import Foundation

let voiceLatencyTraceFlag = "voice.latency_tracing_v1"

enum VoiceTraceEvents {
  static let sessionCreated = "voice_session_created"
  static let microphoneOpenStarted = "microphone_open_started"
  static let microphoneOpened = "microphone_opened"
  static let speechStarted = "speech_started"
  static let speechEnded = "speech_ended"
  static let asrFirstPartial = "asr_first_partial"
  static let asrFirstStable = "asr_first_stable"
  static let asrFinalStarted = "asr_final_started"
  static let asrDecodeStarted = "asr_decode_started"
  static let asrDecodeCompleted = "asr_decode_completed"
  static let asrModelLoadStarted = "asr_model_load_started"
  static let asrModelLoadCompleted = "asr_model_load_completed"
  static let whisperFullStarted = "whisper_full_started"
  static let whisperFullCompleted = "whisper_full_completed"
  static let asrFinalReceived = "asr_final_received"
  static let asrFinalFailed = "asr_final_failed"
  static let secondPassStarted = "second_pass_started"
  static let secondPassCompleted = "second_pass_completed"
  static let routeStarted = "route_started"
  static let routeSelected = "route_selected"
  static let localActionStarted = "local_action_started"
  static let localActionCompleted = "local_action_completed"
  static let modelRequestStarted = "model_request_started"
  static let modelConnected = "model_connected"
  static let modelFirstDelta = "model_first_delta"
  static let modelFirstSentenceCommitted = "model_first_sentence_committed"
  static let modelRequestCompleted = "model_request_completed"
  static let ttsRequestStarted = "tts_request_started"
  static let ttsConnected = "tts_connected"
  static let ttsFirstAudio = "tts_first_audio"
  static let ttsPlaybackStarted = "tts_playback_started"
  static let ttsCompleted = "tts_completed"
  static let agentRunCreateStarted = "agent_run_create_started"
  static let agentRunAccepted = "agent_run_accepted"
  static let agentFirstProgress = "agent_first_progress"
  static let agentFirstPartialResult = "agent_first_partial_result"
  static let agentCompleted = "agent_completed"
  static let sessionCompleted = "voice_session_completed"
  static let sessionCancelled = "voice_session_cancelled"
  static let sessionFailed = "voice_session_failed"
}

struct VoiceTraceEvent: Codable, Equatable {
  var traceId: String
  var sessionId: String
  var event: String
  var elapsedRealtimeNs: Int64
  var wallClockMs: Int64
  var attributes: [String: String]

  enum CodingKeys: String, CodingKey {
    case traceId = "trace_id"
    case sessionId = "session_id"
    case event
    case elapsedRealtimeNs = "elapsed_realtime_ns"
    case wallClockMs = "wall_clock_ms"
    case attributes
  }
}

struct VoiceLatencyPercentiles: Codable, Equatable {
  var count: Int
  var p50Ms: Int64
  var p90Ms: Int64
  var p95Ms: Int64
  var p99Ms: Int64

  enum CodingKeys: String, CodingKey {
    case count
    case p50Ms = "p50_ms"
    case p90Ms = "p90_ms"
    case p95Ms = "p95_ms"
    case p99Ms = "p99_ms"
  }
}

struct VoiceDiagnosticSummary: Codable, Equatable {
  var traceCount: Int
  var eventCount: Int
  var completedCount: Int
  var cancelledCount: Int
  var failedCount: Int
  var successRate: Double
  var cancellationRate: Double
  var failureRate: Double
  var fallbackRate: Double
  var oomCount: Int
  var nativeCrashCount: Int
  var thermalDegradeCount: Int
  var modelVerificationFailureCount: Int
  var metrics: [String: VoiceLatencyPercentiles]

  enum CodingKeys: String, CodingKey {
    case traceCount = "trace_count"
    case eventCount = "event_count"
    case completedCount = "completed_count"
    case cancelledCount = "cancelled_count"
    case failedCount = "failed_count"
    case successRate = "success_rate"
    case cancellationRate = "cancellation_rate"
    case failureRate = "failure_rate"
    case fallbackRate = "fallback_rate"
    case oomCount = "oom_count"
    case nativeCrashCount = "native_crash_count"
    case thermalDegradeCount = "thermal_degrade_count"
    case modelVerificationFailureCount = "model_verification_failure_count"
    case metrics
  }
}

typealias VoiceElapsedRealtimeSource = () -> Int64
typealias VoiceWallClockSource = () -> Int64

protocol VoiceTraceEventSink {
  func append(_ event: VoiceTraceEvent)
  func snapshot() -> [VoiceTraceEvent]
}

final class InMemoryVoiceTraceEventSink: VoiceTraceEventSink {
  private let lock = NSLock()
  private var events: [VoiceTraceEvent] = []

  func append(_ event: VoiceTraceEvent) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }

  func snapshot() -> [VoiceTraceEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

final class VoiceLatencyTracer {
  private let elapsedSource: VoiceElapsedRealtimeSource
  private let wallClockSource: VoiceWallClockSource
  private let enabled: () -> Bool
  private let sink: VoiceTraceEventSink
  private let onceLock = NSLock()
  private var onceKeys: [String] = []
  private var onceSet: Set<String> = []

  init(
    elapsedSource: @escaping VoiceElapsedRealtimeSource,
    wallClockSource: @escaping VoiceWallClockSource,
    enabled: @escaping () -> Bool = { true },
    sink: VoiceTraceEventSink = InMemoryVoiceTraceEventSink()
  ) {
    self.elapsedSource = elapsedSource
    self.wallClockSource = wallClockSource
    self.enabled = enabled
    self.sink = sink
  }

  func startSession(attributes: [String: String] = [:]) -> String {
    let id = UUID().uuidString
    _ = record(
      traceId: id,
      sessionId: id,
      event: VoiceTraceEvents.sessionCreated,
      attributes: attributes,
      once: true
    )
    return id
  }

  @discardableResult
  func record(
    traceId: String,
    sessionId: String? = nil,
    event: String,
    attributes: [String: String] = [:],
    once: Bool = false
  ) -> VoiceTraceEvent? {
    guard enabled(),
          let safeTraceId = VoiceTracePrivacy.safeIdentifier(traceId),
          let safeEvent = VoiceTracePrivacy.safeEvent(event) else {
      return nil
    }
    let safeSessionId = VoiceTracePrivacy.safeIdentifier(sessionId ?? "") ?? safeTraceId
    if once, !claimOnce(traceId: safeTraceId, event: safeEvent) {
      return nil
    }
    let traceEvent = VoiceTraceEvent(
      traceId: safeTraceId,
      sessionId: safeSessionId,
      event: safeEvent,
      elapsedRealtimeNs: max(0, elapsedSource()),
      wallClockMs: max(0, wallClockSource()),
      attributes: VoiceTracePrivacy.sanitizeAttributes(attributes)
    )
    sink.append(traceEvent)
    return traceEvent
  }

  func snapshot() -> [VoiceTraceEvent] {
    sink.snapshot()
  }

  func elapsedMillis(
    traceId: String,
    startEvent: String,
    endEvent: String
  ) -> Int64? {
    let events = snapshot()
      .filter { $0.traceId == traceId }
      .sorted { $0.elapsedRealtimeNs < $1.elapsedRealtimeNs }
    guard let start = events.first(where: { $0.event == startEvent })?.elapsedRealtimeNs,
          let end = events.first(where: { $0.event == endEvent && $0.elapsedRealtimeNs >= start })?.elapsedRealtimeNs else {
      return nil
    }
    return max(0, (end - start) / 1_000_000)
  }

  func diagnosticSummary() -> VoiceDiagnosticSummary {
    Self.summarize(snapshot())
  }

  static func summarize(_ events: [VoiceTraceEvent]) -> VoiceDiagnosticSummary {
    let byTrace = Dictionary(grouping: events, by: \.traceId)
    let completedCount = byTrace.values.filter { trace in
      trace.contains { $0.event == VoiceTraceEvents.sessionCompleted }
    }.count
    let cancelledCount = byTrace.values.filter { trace in
      trace.contains { $0.event == VoiceTraceEvents.sessionCancelled }
    }.count
    let failedCount = byTrace.values.filter { trace in
      trace.contains { $0.event == VoiceTraceEvents.sessionFailed }
    }.count
    let terminalCount = completedCount + cancelledCount + failedCount
    let fallbackCount = byTrace.values.filter { trace in
      trace.contains { $0.attributes["fallback"] == "true" }
    }.count
    var samplesByMetric: [String: [Int64]] = [:]
    metricPairs.forEach { samplesByMetric[$0.name] = [] }
    for trace in byTrace.values {
      let ordered = trace.sorted { $0.elapsedRealtimeNs < $1.elapsedRealtimeNs }
      for pair in metricPairs {
        guard let start = ordered.first(where: { $0.event == pair.start })?.elapsedRealtimeNs,
              let end = ordered.first(where: { $0.event == pair.end && $0.elapsedRealtimeNs >= start })?.elapsedRealtimeNs else {
          continue
        }
        samplesByMetric[pair.name, default: []].append(max(0, (end - start) / 1_000_000))
      }
    }
    return VoiceDiagnosticSummary(
      traceCount: byTrace.count,
      eventCount: events.count,
      completedCount: completedCount,
      cancelledCount: cancelledCount,
      failedCount: failedCount,
      successRate: rate(completedCount, terminalCount),
      cancellationRate: rate(cancelledCount, terminalCount),
      failureRate: rate(failedCount, terminalCount),
      fallbackRate: rate(fallbackCount, byTrace.count),
      oomCount: events.filter { event in
        let code = event.attributes["error_code"] ?? ""
        return code.range(of: "outofmemory", options: [.caseInsensitive]) != nil ||
          code.caseInsensitiveCompare("oom") == .orderedSame
      }.count,
      nativeCrashCount: events.filter { event in
        ["native_crash", "sigill", "sigsegv", "sigabrt"].contains(
          (event.attributes["error_code"] ?? "").lowercased()
        )
      }.count,
      thermalDegradeCount: events.filter {
        ($0.attributes["error_code"] ?? "").caseInsensitiveCompare("thermal_degraded") == .orderedSame
      }.count,
      modelVerificationFailureCount: events.filter {
        ($0.attributes["error_code"] ?? "").caseInsensitiveCompare("model_verification_failed") == .orderedSame
      }.count,
      metrics: samplesByMetric.compactMapValues { values in
        values.isEmpty ? nil : percentiles(values)
      }
    )
  }

  private func claimOnce(traceId: String, event: String) -> Bool {
    let key = "\(traceId):\(event)"
    onceLock.lock()
    defer { onceLock.unlock() }
    guard onceSet.insert(key).inserted else { return false }
    onceKeys.append(key)
    if onceKeys.count > 32_000 {
      let expired = onceKeys.prefix(8_000)
      expired.forEach { onceSet.remove($0) }
      onceKeys.removeFirst(min(8_000, onceKeys.count))
    }
    return true
  }

  private static func rate(_ count: Int, _ total: Int) -> Double {
    total > 0 ? Double(count) / Double(total) : 0
  }

  private static func percentiles(_ samples: [Int64]) -> VoiceLatencyPercentiles {
    let sorted = samples.sorted()
    func percentile(_ value: Double) -> Int64 {
      let index = min(max(Int(ceil(value * Double(sorted.count))) - 1, 0), sorted.count - 1)
      return sorted[index]
    }
    return VoiceLatencyPercentiles(
      count: sorted.count,
      p50Ms: percentile(0.50),
      p90Ms: percentile(0.90),
      p95Ms: percentile(0.95),
      p99Ms: percentile(0.99)
    )
  }

  private static let metricPairs: [(name: String, start: String, end: String)] = [
    ("microphone_open_ms", VoiceTraceEvents.microphoneOpenStarted, VoiceTraceEvents.microphoneOpened),
    ("endpoint_wait_ms", VoiceTraceEvents.speechStarted, VoiceTraceEvents.speechEnded),
    ("asr_decode_ms", VoiceTraceEvents.asrDecodeStarted, VoiceTraceEvents.asrDecodeCompleted),
    ("whisper_full_ms", VoiceTraceEvents.whisperFullStarted, VoiceTraceEvents.whisperFullCompleted),
    ("asr_total_ms", VoiceTraceEvents.asrFinalStarted, VoiceTraceEvents.asrFinalReceived),
    ("model_connect_ms", VoiceTraceEvents.modelRequestStarted, VoiceTraceEvents.modelConnected),
    ("model_first_delta_ms", VoiceTraceEvents.modelRequestStarted, VoiceTraceEvents.modelFirstDelta),
    ("model_total_ms", VoiceTraceEvents.modelRequestStarted, VoiceTraceEvents.modelRequestCompleted),
    ("tts_first_audio_ms", VoiceTraceEvents.ttsRequestStarted, VoiceTraceEvents.ttsFirstAudio),
    ("tts_playback_ms", VoiceTraceEvents.ttsRequestStarted, VoiceTraceEvents.ttsPlaybackStarted),
    ("agent_accept_ms", VoiceTraceEvents.agentRunCreateStarted, VoiceTraceEvents.agentRunAccepted),
    ("agent_first_progress_ms", VoiceTraceEvents.agentRunCreateStarted, VoiceTraceEvents.agentFirstProgress),
    ("agent_first_output_ms", VoiceTraceEvents.agentRunCreateStarted, VoiceTraceEvents.agentFirstPartialResult),
    ("agent_total_ms", VoiceTraceEvents.agentRunCreateStarted, VoiceTraceEvents.agentCompleted),
    ("voice_total_ms", VoiceTraceEvents.sessionCreated, VoiceTraceEvents.sessionCompleted),
  ]
}

enum VoiceTracePrivacy {
  static func safeIdentifier(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return matches(trimmed, pattern: "[A-Za-z0-9][A-Za-z0-9._:-]{0,127}") ? trimmed : nil
  }

  static func safeEvent(_ value: String) -> String? {
    let event = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return matches(event, pattern: "[a-z][a-z0-9_]{0,95}") ? event : nil
  }

  static func sanitizeAttributes(_ attributes: [String: String]) -> [String: String] {
    var sanitized: [String: String] = [:]
    for (rawKey, rawValue) in attributes {
      let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard allowedKeys.contains(key) else { continue }
      let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let safe: String?
      if key == "model_sha256" {
        safe = matches(value.lowercased(), pattern: "[a-f0-9]{64}") ? value.lowercased() : nil
      } else if numericKeys.contains(key) {
        if let number = Double(value), number.isFinite {
          safe = value
        } else {
          safe = nil
        }
      } else if booleanKeys.contains(key) {
        let lowered = value.lowercased()
        safe = lowered == "true" || lowered == "false" ? lowered : nil
      } else if value.contains("/") || value.contains("\\") || value.contains("@") {
        safe = nil
      } else {
        safe = matches(value, pattern: "[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,119}") ? value : nil
      }
      if let safe = safe {
        sanitized[key] = safe
      }
    }
    return sanitized
  }

  private static func matches(_ value: String, pattern: String) -> Bool {
    value.range(of: "^\(pattern)$", options: .regularExpression) != nil
  }

  private static let allowedKeys: Set<String> = [
    "device_model", "soc", "android_api", "ios_version", "app_version", "native_version",
    "network_type", "asr_provider", "model_provider", "model_profile_id", "model_sha256",
    "quantization", "execution_mode", "thread_count", "thermal_status",
    "battery_percent", "is_charging", "audio_duration_ms", "rtf",
    "agent_provider", "tts_provider", "error_code", "recording_source", "endpoint_reason",
    "http_status", "success", "cold_start", "queue_depth", "transport",
    "task_status", "retry_count", "fallback", "duration_ms",
  ]
  private static let numericKeys: Set<String> = [
    "android_api", "ios_version", "thread_count", "thermal_status", "battery_percent",
    "audio_duration_ms", "rtf", "http_status", "queue_depth", "retry_count",
    "duration_ms",
  ]
  private static let booleanKeys: Set<String> = ["is_charging", "success", "cold_start", "fallback"]
}

enum VoiceLatencyFeatureFlags {
  static func isEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = true
  ) -> Bool {
    guard userDefaults.object(forKey: voiceLatencyTraceFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceLatencyTraceFlag)
  }

  static func setEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
    userDefaults.set(enabled, forKey: voiceLatencyTraceFlag)
  }
}

enum VoiceLatencyTraceContext {
  private static let key = "signalasi.voice_latency_trace_id"

  static func currentTraceId() -> String {
    Thread.current.threadDictionary[key] as? String ?? ""
  }

  static func withTrace<T>(_ traceId: String, operation: () -> T) -> T {
    let previous = currentTraceId()
    if traceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Thread.current.threadDictionary.removeObject(forKey: key)
    } else {
      Thread.current.threadDictionary[key] = traceId
    }
    defer {
      if previous.isEmpty {
        Thread.current.threadDictionary.removeObject(forKey: key)
      } else {
        Thread.current.threadDictionary[key] = previous
      }
    }
    return operation()
  }
}

enum VoiceLatencyTelemetry {
  private static let lock = NSLock()
  private static var runtimeTracer: VoiceLatencyTracer?

  static func tracer() -> VoiceLatencyTracer {
    lock.lock()
    defer { lock.unlock() }
    if let runtimeTracer = runtimeTracer {
      return runtimeTracer
    }
    let tracer = VoiceLatencyTracer(
      elapsedSource: {
        Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
      },
      wallClockSource: {
        Int64(Date().timeIntervalSince1970 * 1_000)
      },
      enabled: {
        VoiceLatencyFeatureFlags.isEnabled()
      }
    )
    runtimeTracer = tracer
    return tracer
  }

  static func resetForTests(_ tracer: VoiceLatencyTracer? = nil) {
    lock.lock()
    runtimeTracer = tracer
    lock.unlock()
  }
}
