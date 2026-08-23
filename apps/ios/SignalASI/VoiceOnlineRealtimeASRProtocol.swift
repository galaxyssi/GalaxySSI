import Foundation

struct VoiceOnlineRealtimeASRConfig {
  let voiceSessionID: String
  let transcriptID: String
  let language: String
  let requestServerDataDeletion: Bool
}

enum VoiceOnlineRealtimeASREvent {
  case ready(provider: String, providerSessionID: String, modelProfileID: String)
  case speechStarted(
    provider: String,
    providerSessionID: String,
    sequence: Int64?,
    serverTimestampMs: Int64?
  )
  case partial(TranscriptHypothesis, stable: Bool)
  case final(TranscriptHypothesis)
  case usage(VoiceOnlineRealtimeASRUsage)
  case metrics(VoiceOnlineRealtimeASRMetrics)
  case failed(VoiceOnlineRealtimeASRFailure)
  case closed(provider: String, providerSessionID: String, reasonCode: String)
}

struct VoiceOnlineRealtimeASRUsage: Equatable {
  let providerID: String
  let providerSessionID: String
  let audioDurationMs: Int64
  let billableDurationMs: Int64?
  let serverTimestampMs: Int64?
}

struct VoiceOnlineRealtimeASRMetrics: Equatable {
  let providerID: String
  let providerSessionID: String
  let audioSentMs: Int64
  let firstPartialLatencyMs: Int64?
  let finalLatencyMs: Int64?
  let reconnectCount: Int
  let droppedAudioBatches: Int
  let serverTimestampMs: Int64?
}

struct VoiceOnlineRealtimeASRFailure: Equatable {
  let code: String
  let message: String
  let retryable: Bool
  let fatal: Bool
  let providerID: String
  let providerSessionID: String
  let serverTimestampMs: Int64?
}

struct VoiceOnlineRealtimeASRAudioBatch {
  let firstSequence: Int64
  let lastSequence: Int64
  let firstCaptureTimeNanos: Int64
  let lastCaptureTimeNanos: Int64
  var samples: [Int16]
}

enum VoiceOnlineRealtimeASRProtocol {
  static let sampleRateHz = 16_000
  private static let magic: UInt32 = 0x53415352
  private static let version: UInt16 = 1

  static func startMessage(
    config: VoiceOnlineRealtimeASRConfig,
    credential: VoiceOnlineRealtimeASRCredential
  ) throws -> String {
    try jsonString([
      "schema_version": 1,
      "event_type": "session.start",
      "voice_session_id": config.voiceSessionID,
      "transcript_id": config.transcriptID,
      "provider_session_id": credential.providerSessionID,
      "language": config.language,
      "encoding": "pcm_s16le",
      "sample_rate_hz": sampleRateHz,
      "channel_count": 1,
      "server_vad": true,
      "request_server_data_deletion": config.requestServerDataDeletion &&
        credential.serverDataDeletionSupported
    ])
  }

  static func finishMessage(config: VoiceOnlineRealtimeASRConfig) throws -> String {
    try controlMessage(type: "input.finish", config: config)
  }

  static func abortMessage(config: VoiceOnlineRealtimeASRConfig, reason: String) throws -> String {
    try jsonString([
      "schema_version": 1,
      "event_type": "session.abort",
      "voice_session_id": config.voiceSessionID,
      "transcript_id": config.transcriptID,
      "reason_code": String(reason.prefix(120))
    ])
  }

  static func heartbeatMessage(config: VoiceOnlineRealtimeASRConfig) throws -> String {
    try jsonString([
      "schema_version": 1,
      "event_type": "session.heartbeat",
      "voice_session_id": config.voiceSessionID,
      "transcript_id": config.transcriptID,
      "sent_at_epoch_ms": Int64(Date().timeIntervalSince1970 * 1_000)
    ])
  }

  static func encodeAudio(_ batch: VoiceOnlineRealtimeASRAudioBatch) -> Data {
    var data = Data(capacity: 48 + batch.samples.count * 2)
    data.appendLittleEndian(magic)
    data.appendLittleEndian(version)
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt64(bitPattern: batch.firstSequence))
    data.appendLittleEndian(UInt64(bitPattern: batch.lastSequence))
    data.appendLittleEndian(UInt64(bitPattern: batch.firstCaptureTimeNanos))
    data.appendLittleEndian(UInt64(bitPattern: batch.lastCaptureTimeNanos))
    data.appendLittleEndian(UInt32(sampleRateHz))
    data.appendLittleEndian(UInt32(batch.samples.count))
    batch.samples.forEach { data.appendLittleEndian(UInt16(bitPattern: $0)) }
    return data
  }

  static func parseEvent(
    _ text: String,
    config: VoiceOnlineRealtimeASRConfig,
    credential: VoiceOnlineRealtimeASRCredential
  ) -> VoiceOnlineRealtimeASREvent? {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let type = string(json, "event_type").ifBlank(string(json, "type")).lowercased()
    let provider = string(json, "provider_id").ifBlank(credential.providerID)
    let providerSessionID = string(json, "provider_session_id").ifBlank(credential.providerSessionID)
    let serverTimestampMs = optionalInt64(json, "server_timestamp_ms")
    switch type {
    case "ready", "session.ready":
      return .ready(
        provider: provider,
        providerSessionID: providerSessionID,
        modelProfileID: string(json, "model_profile_id")
      )
    case "speech_started", "input.speech_started":
      return .speechStarted(
        provider: provider,
        providerSessionID: providerSessionID,
        sequence: optionalInt64(json, "sequence"),
        serverTimestampMs: serverTimestampMs
      )
    case "partial", "transcript.partial":
      return .partial(hypothesis(json, config: config, provider: provider, isFinal: false), stable: false)
    case "stable", "transcript.stable":
      return .partial(hypothesis(json, config: config, provider: provider, isFinal: false), stable: true)
    case "final", "transcript.final":
      guard string(json, "transcript_id").ifBlank(config.transcriptID) == config.transcriptID else {
        return nil
      }
      return .final(hypothesis(json, config: config, provider: provider, isFinal: true))
    case "usage", "session.usage":
      return .usage(VoiceOnlineRealtimeASRUsage(
        providerID: provider,
        providerSessionID: providerSessionID,
        audioDurationMs: max(0, int64(json, "audio_duration_ms")),
        billableDurationMs: optionalInt64(json, "billable_duration_ms"),
        serverTimestampMs: serverTimestampMs
      ))
    case "metrics", "session.metrics":
      return .metrics(VoiceOnlineRealtimeASRMetrics(
        providerID: provider,
        providerSessionID: providerSessionID,
        audioSentMs: max(0, int64(json, "audio_sent_ms")),
        firstPartialLatencyMs: optionalInt64(json, "first_partial_latency_ms"),
        finalLatencyMs: optionalInt64(json, "final_latency_ms"),
        reconnectCount: max(0, number(json, "reconnect_count")?.intValue ?? 0),
        droppedAudioBatches: max(0, number(json, "dropped_audio_batches")?.intValue ?? 0),
        serverTimestampMs: serverTimestampMs
      ))
    case "recoverable_error", "error.recoverable":
      return .failed(VoiceOnlineRealtimeASRFailure(
        code: string(json, "code").ifBlank("provider_error"),
        message: String(string(json, "message").prefix(240)),
        retryable: boolean(json, "retryable") ?? true,
        fatal: false,
        providerID: provider,
        providerSessionID: providerSessionID,
        serverTimestampMs: serverTimestampMs
      ))
    case "fatal_error", "error.fatal":
      return .failed(VoiceOnlineRealtimeASRFailure(
        code: string(json, "code").ifBlank("provider_error"),
        message: String(string(json, "message").prefix(240)),
        retryable: boolean(json, "retryable") ?? false,
        fatal: true,
        providerID: provider,
        providerSessionID: providerSessionID,
        serverTimestampMs: serverTimestampMs
      ))
    case "closed", "session.closed":
      return .closed(
        provider: provider,
        providerSessionID: providerSessionID,
        reasonCode: string(json, "reason_code")
      )
    default:
      return nil
    }
  }

  private static func hypothesis(
    _ json: [String: Any],
    config: VoiceOnlineRealtimeASRConfig,
    provider: String,
    isFinal: Bool
  ) -> TranscriptHypothesis {
    let language = string(json, "language")
    return TranscriptHypothesis(
      text: string(json, "text"),
      revision: max(0, number(json, "revision")?.intValue ?? number(json, "sequence")?.intValue ?? 0),
      provider: provider,
      modelProfileId: string(json, "model_profile_id"),
      confidence: number(json, "confidence")?.floatValue,
      transcriptId: string(json, "transcript_id").ifBlank(config.transcriptID),
      stablePrefixLength: max(0, number(json, "stable_prefix_length")?.intValue ?? 0),
      isFinal: isFinal,
      language: language.isEmpty ? nil : language,
      segmentStartMs: max(0, int64(json, "segment_start_ms")),
      segmentEndMs: max(0, int64(json, "segment_end_ms")),
      averageLogProb: number(json, "average_log_prob")?.floatValue,
      noSpeechProbability: number(json, "no_speech_probability")?.floatValue,
      createdElapsedNs: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    )
  }

  private static func controlMessage(type: String, config: VoiceOnlineRealtimeASRConfig) throws -> String {
    try jsonString([
      "schema_version": 1,
      "event_type": type,
      "voice_session_id": config.voiceSessionID,
      "transcript_id": config.transcriptID
    ])
  }

  private static func jsonString(_ value: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else {
      throw VoiceOnlineRealtimeASRError.invalidResponse
    }
    return text
  }

  private static func string(_ json: [String: Any], _ key: String) -> String {
    (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func number(_ json: [String: Any], _ key: String) -> NSNumber? {
    json[key] as? NSNumber
  }

  private static func int64(_ json: [String: Any], _ key: String) -> Int64 {
    number(json, key)?.int64Value ?? 0
  }

  private static func optionalInt64(_ json: [String: Any], _ key: String) -> Int64? {
    number(json, key)?.int64Value
  }

  private static func boolean(_ json: [String: Any], _ key: String) -> Bool? {
    number(json, key)?.boolValue
  }
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }
}
