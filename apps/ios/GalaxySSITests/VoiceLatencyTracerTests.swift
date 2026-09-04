import XCTest
@testable import GalaxySSI

final class VoiceLatencyTracerTests: XCTestCase {
  func testElapsedDurationsUseMonotonicClockInsteadOfWallClock() {
    var elapsedNs: Int64 = 2_000_000_000
    var wallClockMs: Int64 = 10_000
    let tracer = VoiceLatencyTracer(
      elapsedSource: { elapsedNs },
      wallClockSource: { wallClockMs }
    )
    let traceId = tracer.startSession()

    elapsedNs += 125_000_000
    wallClockMs += 60_000
    tracer.record(traceId: traceId, event: VoiceTraceEvents.asrFinalStarted)
    elapsedNs += 875_000_000
    wallClockMs -= 120_000
    tracer.record(traceId: traceId, event: VoiceTraceEvents.asrFinalReceived)

    XCTAssertEqual(
      tracer.elapsedMillis(
        traceId: traceId,
        startEvent: VoiceTraceEvents.asrFinalStarted,
        endEvent: VoiceTraceEvents.asrFinalReceived
      ),
      875
    )
    XCTAssertEqual(tracer.diagnosticSummary().metrics["asr_total_ms"]?.p95Ms, 875)
  }

  func testSensitiveFieldsAndValuesNeverEnterTrace() {
    let tracer = VoiceLatencyTracer(
      elapsedSource: { 5_000_000 },
      wallClockSource: { 10 }
    )
    let traceId = tracer.startSession()
    let event = tracer.record(
      traceId: traceId,
      event: VoiceTraceEvents.modelRequestCompleted,
      attributes: [
        "transcript": "private words",
        "prompt": "delete everything",
        "file_path": "C:\\Users\\agent\\secret.txt",
        "api_key": "secret-token",
        "agent_provider": "Codex",
        "duration_ms": "1250",
        "error_code": "HTTP_TIMEOUT",
        "transport": "https://private.example/path",
      ]
    )

    XCTAssertEqual(event?.attributes["agent_provider"], "Codex")
    XCTAssertEqual(event?.attributes["duration_ms"], "1250")
    XCTAssertEqual(event?.attributes["error_code"], "HTTP_TIMEOUT")
    XCTAssertFalse(event?.attributes.keys.contains("transcript") ?? true)
    XCTAssertFalse(event?.attributes.keys.contains("prompt") ?? true)
    XCTAssertFalse(event?.attributes.keys.contains("file_path") ?? true)
    XCTAssertFalse(event?.attributes.keys.contains("api_key") ?? true)
    XCTAssertFalse(event?.attributes.keys.contains("transport") ?? true)
    XCTAssertFalse(String(describing: event).contains("private words"))
    XCTAssertFalse(String(describing: event).contains("secret.txt"))
  }

  func testDisabledFlagProducesNoEvents() {
    let sink = InMemoryVoiceTraceEventSink()
    let tracer = VoiceLatencyTracer(
      elapsedSource: { 1 },
      wallClockSource: { 1 },
      enabled: { false },
      sink: sink
    )

    let traceId = tracer.startSession()
    XCTAssertNil(tracer.record(traceId: traceId, event: VoiceTraceEvents.speechStarted))
    XCTAssertTrue(sink.snapshot().isEmpty)
  }

  func testOnceEventsAreDeduplicatedPerTrace() {
    var elapsedNs: Int64 = 0
    let tracer = VoiceLatencyTracer(
      elapsedSource: {
        elapsedNs += 1
        return elapsedNs
      },
      wallClockSource: { 1 }
    )
    let traceId = tracer.startSession()

    tracer.record(traceId: traceId, event: VoiceTraceEvents.agentRunAccepted, once: true)
    tracer.record(traceId: traceId, event: VoiceTraceEvents.agentRunAccepted, once: true)

    XCTAssertEqual(
      tracer.snapshot().filter { $0.event == VoiceTraceEvents.agentRunAccepted }.count,
      1
    )
  }

  func testSummaryCountsTerminalFallbackAndErrorClasses() {
    let events = [
      event("a", VoiceTraceEvents.sessionCreated, 0),
      event("a", VoiceTraceEvents.ttsRequestStarted, 10_000_000),
      event("a", VoiceTraceEvents.ttsPlaybackStarted, 30_000_000),
      event("a", VoiceTraceEvents.sessionCompleted, 40_000_000, ["fallback": "true"]),
      event("b", VoiceTraceEvents.sessionFailed, 50_000_000, ["error_code": "SIGSEGV"]),
      event("c", VoiceTraceEvents.sessionCancelled, 60_000_000, ["error_code": "oom"]),
      event("d", VoiceTraceEvents.sessionFailed, 70_000_000, ["error_code": "model_verification_failed"]),
      event("e", VoiceTraceEvents.sessionFailed, 80_000_000, ["error_code": "thermal_degraded"]),
    ]

    let summary = VoiceLatencyTracer.summarize(events)

    XCTAssertEqual(summary.traceCount, 5)
    XCTAssertEqual(summary.completedCount, 1)
    XCTAssertEqual(summary.cancelledCount, 1)
    XCTAssertEqual(summary.failedCount, 3)
    XCTAssertEqual(summary.fallbackRate, 0.2)
    XCTAssertEqual(summary.nativeCrashCount, 1)
    XCTAssertEqual(summary.oomCount, 1)
    XCTAssertEqual(summary.modelVerificationFailureCount, 1)
    XCTAssertEqual(summary.thermalDegradeCount, 1)
    XCTAssertEqual(summary.metrics["tts_playback_ms"]?.p50Ms, 20)
  }

  func testTraceContextRestoresPreviousTrace() {
    let outer = VoiceLatencyTraceContext.withTrace("outer") {
      VoiceLatencyTraceContext.withTrace("inner") {
        VoiceLatencyTraceContext.currentTraceId()
      }
    }

    XCTAssertEqual(outer, "inner")
    XCTAssertEqual(VoiceLatencyTraceContext.currentTraceId(), "")
  }

  private func event(
    _ traceId: String,
    _ name: String,
    _ elapsedNs: Int64,
    _ attributes: [String: String] = [:]
  ) -> VoiceTraceEvent {
    VoiceTraceEvent(
      traceId: traceId,
      sessionId: traceId,
      event: name,
      elapsedRealtimeNs: elapsedNs,
      wallClockMs: elapsedNs / 1_000_000,
      attributes: VoiceTracePrivacy.sanitizeAttributes(attributes)
    )
  }
}
