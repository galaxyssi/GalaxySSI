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
