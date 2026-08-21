import CryptoKit
import Foundation

/// Wire-compatible representation of the trusted-desktop Whisper protocol used by Android.
/// Audio is only prepared after the paired desktop advertises explicit consent support.
struct VoiceRemoteWhisperProfile: Equatable {
  let id: String
  let modelName: String
  let sha256: String
  let shaKind: String

  init?(id: String, modelName: String, sha256: String, shaKind: String) {
    let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSHA = sha256.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedID.isEmpty, VoiceRemoteWhisperProtocol.isSHA256(normalizedSHA) else { return nil }
    self.id = normalizedID
    self.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(normalizedID)
    self.sha256 = normalizedSHA
    self.shaKind = shaKind.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("profile_manifest_sha256")
  }
}

struct VoiceRemoteWhisperNodeCapability: Equatable {
  let desktopID: String
  let desktopName: String
  let clientRouteID: String
  let activeProfile: VoiceRemoteWhisperProfile
  let maxPCMBytes: Int
  let generatedAtMillis: Int64

  init?(
    desktopID: String,
    desktopName: String,
    clientRouteID: String,
    activeProfile: VoiceRemoteWhisperProfile,
    maxPCMBytes: Int,
    generatedAtMillis: Int64
  ) {
    let normalizedDesktopID = desktopID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedRouteID = clientRouteID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedDesktopID.isEmpty, !normalizedRouteID.isEmpty, maxPCMBytes >= 32_000 else { return nil }
    self.desktopID = normalizedDesktopID
    self.desktopName = desktopName.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("SignalASI Desktop")
    self.clientRouteID = normalizedRouteID
    self.activeProfile = activeProfile
    self.maxPCMBytes = maxPCMBytes
    self.generatedAtMillis = generatedAtMillis
  }
}

struct VoicePreparedRemoteWhisperRequest {
  let requestID: String
  let desktopID: String
  let voiceSessionID: String
  let transcriptID: String
  let audioSHA256: String
  let profile: VoiceRemoteWhisperProfile
  let manifest: [String: Any]
  let chunks: [[String: Any]]
}

struct VoiceRemoteWhisperTranscript: Equatable {
  let requestID: String
  let voiceSessionID: String
  let transcriptID: String
  let desktopID: String
  let text: String
  let language: String
  let confidence: Float?
  let profile: VoiceRemoteWhisperProfile
  let audioSHA256: String
  let processingMillis: Int64
  let cleanupVerified: Bool
}

enum VoiceRemoteWhisperOutcome: Equatable {
  case completed(VoiceRemoteWhisperTranscript)
  case failed(requestID: String, code: String, message: String, cancelled: Bool = false)
}

enum VoiceRemoteWhisperProtocol {
  static let version = "signalasi.remote-whisper/1.0"
  static let requestType = "remote_whisper_request"
  static let chunkType = "remote_whisper_chunk"
  static let cancelType = "remote_whisper_cancel"
  static let resultType = "remote_whisper_result"
  static let errorType = "remote_whisper_error"
  static let cancelledType = "remote_whisper_cancelled"
  static let audioFormat = "pcm_s16le_16000_mono"
  static let consentScope = "voice.remote_whisper.correction"
  static let maximumChunkBytes = 128 * 1024

  static func parseCapability(
    _ payload: [String: Any],
    sourceDesktopID: String,
    generatedAtMillis: Int64? = nil
  ) -> VoiceRemoteWhisperNodeCapability? {
    guard string(payload, "type") == "capability_manifest",
          let capabilities = dictionary(payload, "protocol_capabilities"),
          bool(capabilities, "remote_whisper"),
          let node = dictionary(capabilities, "remote_whisper_node"),
          bool(node, "available"),
          string(node, "protocol") == version,
          let executionDevice = dictionary(node, "execution_device"),
          let authorization = dictionary(node, "authorization"),
          bool(authorization, "explicit_user_consent_required"),
          bool(authorization, "paired_device_identity_required"),
          bool(authorization, "only_my_devices"),
          string(authorization, "scope") == consentScope,
          let profile = parseProfile(dictionary(node, "active_profile")),
          supportedAudio(node).contains(audioFormat) else {
      return nil
    }

    let advertisedDesktopID = string(executionDevice, "device_id")
    let desktopID = sourceDesktopID.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(advertisedDesktopID)
    guard !desktopID.isEmpty, desktopID == advertisedDesktopID else { return nil }

    return VoiceRemoteWhisperNodeCapability(
      desktopID: desktopID,
      desktopName: string(executionDevice, "device_name").ifBlank("SignalASI Desktop"),
      clientRouteID: string(authorization, "client_route_id"),
      activeProfile: profile,
      maxPCMBytes: integer(node, "max_pcm_bytes"),
      generatedAtMillis: generatedAtMillis ?? integer64(payload, "generated_at", fallback: nowMillis())
    )
  }

  static func prepare(
    node: VoiceRemoteWhisperNodeCapability,
    clientID: String,
    voiceSessionID: String,
    transcriptID: String,
    pcm16: [Int16],
    sampleRateHz: Int,
    language: String,
    authorizedAtMillis: Int64,
    requestID: String = UUID().uuidString.lowercased(),
    chunkBytes: Int = maximumChunkBytes
  ) -> VoicePreparedRemoteWhisperRequest? {
    let client = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    let session = voiceSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    let transcript = transcriptID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard UUID(uuidString: requestID)?.uuidString.lowercased() == requestID.lowercased(),
          !client.isEmpty,
          !session.isEmpty,
          !transcript.isEmpty,
          sampleRateHz == 16_000,
          !pcm16.isEmpty,
          chunkBytes >= 2,
          chunkBytes <= maximumChunkBytes,
          chunkBytes.isMultiple(of: 2) else {
      return nil
    }

    var bytes = [UInt8]()
    bytes.reserveCapacity(pcm16.count * 2)
    for sample in pcm16 {
      let littleEndian = UInt16(bitPattern: sample).littleEndian
      bytes.append(UInt8(truncatingIfNeeded: littleEndian))
      bytes.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
    }
    let pcm = Data(bytes)
    guard pcm.count <= node.maxPCMBytes else { return nil }

    let audioSHA = sha256(pcm)
    let chunks = stride(from: 0, to: pcm.count, by: chunkBytes).enumerated().map { offset, start in
      let slice = pcm.subdata(in: start ..< min(start + chunkBytes, pcm.count))
      return [
        "type": chunkType,
        "protocol": version,
        "request_id": requestID,
        "client_route_id": node.clientRouteID,
        "client_id": client,
        "chunk_index": offset,
        "chunk_count": (pcm.count + chunkBytes - 1) / chunkBytes,
        "chunk_sha256": sha256(slice),
        "data_base64": slice.base64EncodedString()
      ] as [String: Any]
    }
    let audio: [String: Any] = [
      "format": audioFormat,
      "sample_rate_hz": sampleRateHz,
      "channels": 1,
      "sample_count": pcm16.count,
      "byte_count": pcm.count,
      "duration_ms": Int64(pcm16.count) * 1_000 / Int64(sampleRateHz),
      "sha256": audioSHA,
      "chunk_count": chunks.count,
      "chunk_size_bytes": chunkBytes
    ]
    let manifest: [String: Any] = [
      "type": requestType,
      "protocol": version,
      "request_id": requestID,
      "voice_session_id": session,
      "transcript_id": transcript,
      "client_route_id": node.clientRouteID,
      "client_id": client,
      "language": language.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("auto"),
      "authorization": [
        "explicit": true,
        "only_my_devices": true,
        "scope": consentScope,
        "authorized_at_ms": authorizedAtMillis,
        "request_audio_deletion": true
      ],
      "model": [
        "profile_id": node.activeProfile.id,
        "profile_sha256": node.activeProfile.sha256
      ],
      "audio": audio
    ]
    return VoicePreparedRemoteWhisperRequest(
      requestID: requestID,
      desktopID: node.desktopID,
      voiceSessionID: session,
      transcriptID: transcript,
      audioSHA256: audioSHA,
      profile: node.activeProfile,
      manifest: manifest,
      chunks: chunks
    )
  }

  static func parseOutcome(
    _ payload: [String: Any],
    expected: VoicePreparedRemoteWhisperRequest
  ) -> VoiceRemoteWhisperOutcome? {
    let type = string(payload, "type")
    guard [resultType, errorType, cancelledType].contains(type) else { return nil }
    guard string(payload, "protocol") == version,
          string(payload, "request_id") == expected.requestID,
          string(payload, "desktop_id") == expected.desktopID else {
      return .failed(
        requestID: expected.requestID,
        code: "response_identity_mismatch",
        message: "Remote node identity could not be verified"
      )
    }
    guard type == resultType else {
      let cancelled = type == cancelledType || string(payload, "status") == "cancelled"
      return .failed(
        requestID: expected.requestID,
        code: string(payload, "error_code").ifBlank(cancelled ? "cancelled" : "remote_failed"),
        message: string(payload, "error_message").ifBlank("Remote transcription failed"),
        cancelled: cancelled
      )
    }
    guard let profile = VoiceRemoteWhisperProfile(
      id: string(payload, "model_profile_id"),
      modelName: string(payload, "model_profile_id"),
      sha256: string(payload, "model_profile_sha256"),
      shaKind: expected.profile.shaKind
    ), profile.id == expected.profile.id,
       profile.sha256 == expected.profile.sha256,
       string(payload, "voice_session_id") == expected.voiceSessionID,
       string(payload, "transcript_id") == expected.transcriptID,
       string(payload, "audio_sha256").lowercased() == expected.audioSHA256 else {
      return .failed(
        requestID: expected.requestID,
        code: "response_integrity_failed",
        message: "Remote transcript binding could not be verified"
      )
    }
    guard bool(dictionary(payload, "cleanup") ?? [:], "verified") else {
      return .failed(
        requestID: expected.requestID,
        code: "cleanup_not_verified",
        message: "Remote audio cleanup could not be verified"
      )
    }
    let content = string(payload, "content")
    guard !content.isEmpty else {
      return .failed(
        requestID: expected.requestID,
        code: "empty_transcript",
        message: "Remote transcription returned no speech"
      )
    }
    return .completed(VoiceRemoteWhisperTranscript(
      requestID: expected.requestID,
      voiceSessionID: expected.voiceSessionID,
      transcriptID: expected.transcriptID,
      desktopID: expected.desktopID,
      text: content,
      language: string(payload, "language").ifBlank("auto"),
      confidence: number(payload, "confidence").map(Float.init),
      profile: profile,
      audioSHA256: expected.audioSHA256,
      processingMillis: max(0, integer64(payload, "processing_ms", fallback: 0)),
      cleanupVerified: true
    ))
  }

  static func cancelPayload(for request: VoicePreparedRemoteWhisperRequest) -> [String: Any] {
    [
      "type": cancelType,
      "protocol": version,
      "request_id": request.requestID,
      "client_route_id": request.manifest["client_route_id"] as? String ?? "",
      "time": nowMillis()
    ]
  }

  fileprivate static func isSHA256(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }

  private static func parseProfile(_ value: [String: Any]?) -> VoiceRemoteWhisperProfile? {
    guard let value else { return nil }
    return VoiceRemoteWhisperProfile(
      id: string(value, "profile_id"),
      modelName: string(value, "model_name"),
      sha256: string(value, "profile_sha256"),
      shaKind: string(value, "sha_kind").ifBlank("profile_manifest_sha256")
    )
  }

  private static func supportedAudio(_ value: [String: Any]) -> [String] {
    (value["supported_audio"] as? [Any] ?? []).compactMap { $0 as? String }
  }

  private static func dictionary(_ value: [String: Any], _ key: String) -> [String: Any]? {
    value[key] as? [String: Any]
  }

  private static func string(_ value: [String: Any], _ key: String) -> String {
    (value[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func bool(_ value: [String: Any], _ key: String) -> Bool {
    if let bool = value[key] as? Bool { return bool }
    if let number = value[key] as? NSNumber { return number.boolValue }
    return false
  }

  private static func integer(_ value: [String: Any], _ key: String) -> Int {
    if let integer = value[key] as? Int { return integer }
    if let number = value[key] as? NSNumber { return number.intValue }
    return 0
  }

  private static func integer64(_ value: [String: Any], _ key: String, fallback: Int64) -> Int64 {
    if let integer = value[key] as? Int64 { return integer }
    if let integer = value[key] as? Int { return Int64(integer) }
    if let number = value[key] as? NSNumber { return number.int64Value }
    return fallback
  }

  private static func number(_ value: [String: Any], _ key: String) -> Double? {
    if let number = value[key] as? NSNumber { return number.doubleValue }
    if let number = value[key] as? Double { return number }
    return nil
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}
