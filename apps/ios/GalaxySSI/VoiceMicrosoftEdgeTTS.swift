import Foundation

final class VoiceMicrosoftEdgeTTS {
  private let synthesizer: VoiceMicrosoftEdgeTTSSynthesizing

  init(synthesizer: VoiceMicrosoftEdgeTTSSynthesizing = URLSessionVoiceMicrosoftEdgeTTSSynthesizer()) {
    self.synthesizer = synthesizer
  }

  func synthesize(_ playbackRequest: VoiceReplyPlaybackRequest) async throws -> VoiceMicrosoftEdgeTTSResult {
    let request = try VoiceMicrosoftEdgeTTSWire.request(
      text: playbackRequest.text,
      voiceName: playbackRequest.voiceName,
      requestId: playbackRequest.utteranceId.replacingOccurrences(of: "-", with: "")
    )
    record(
      playbackRequest,
      event: VoiceTraceEvents.ttsRequestStarted,
      attributes: ["tts_provider": VoiceTTSProvider.microsoftEdge.rawValue],
      once: true
    )
    let audio = try await synthesizer.synthesize(request) { event, attributes, once in
      self.record(playbackRequest, event: event, attributes: attributes, once: once)
    }
    guard !audio.isEmpty else { throw VoiceMicrosoftEdgeTTSError.emptyAudio }
    return VoiceMicrosoftEdgeTTSResult(request: request, audioData: audio)
  }

  private func record(
    _ request: VoiceReplyPlaybackRequest,
    event: String,
    attributes: [String: String],
    once: Bool
  ) {
    VoiceLatencyTelemetry.record(
      traceId: request.sessionId,
      event: event,
      attributes: attributes,
      once: once
    )
  }
}
