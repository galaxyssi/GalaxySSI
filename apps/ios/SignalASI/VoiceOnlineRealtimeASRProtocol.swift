import Foundation

struct VoiceOnlineRealtimeASRConfig {
  let voiceSessionID: String
  let transcriptID: String
  let language: String
  let requestServerDataDeletion: Bool
}

enum VoiceOnlineRealtimeASREvent {
  case ready(provider: String, modelProfileID: String)
  case partial(TranscriptHypothesis, stable: Bool)
  case final(TranscriptHypothesis)
  case failed(code: String, message: String)
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
    switch type {
    case "ready", "session.ready":
      return .ready(provider: provider, modelProfileID: string(json, "model_profile_id"))
    case "partial", "transcript.partial":
      return .partial(hypothesis(json, config: config, provider: provider), stable: false)
    case "stable", "transcript.stable":
      return .partial(hypothesis(json, config: config, provider: provider), stable: true)
    case "final", "transcript.final":
      guard string(json, "transcript_id").ifBlank(config.transcriptID) == config.transcriptID else {
        return nil
      }
      return .final(hypothesis(json, config: config, provider: provider))
    case "recoverable_error", "error.recoverable", "fatal_error", "error.fatal":
      return .failed(
        code: string(json, "code").ifBlank("provider_error"),
        message: String(string(json, "message").prefix(240))
      )
    default:
      return nil
    }
  }

  private static func hypothesis(
    _ json: [String: Any],
    config: VoiceOnlineRealtimeASRConfig,
    provider: String
  ) -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: string(json, "text"),
      revision: max(0, number(json, "revision")?.intValue ?? number(json, "sequence")?.intValue ?? 0),
      provider: provider,
      modelProfileId: string(json, "model_profile_id"),
      confidence: number(json, "confidence")?.floatValue
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
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }
}
