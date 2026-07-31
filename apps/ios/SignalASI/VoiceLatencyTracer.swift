import Foundation

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
