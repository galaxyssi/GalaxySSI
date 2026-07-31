import Foundation

typealias VoiceMicrosoftEdgeTTSTraceRecorder = (_ event: String, _ attributes: [String: String], _ once: Bool) -> Void

struct VoiceMicrosoftEdgeTTSRequest: Equatable {
  var requestId: String
  var text: String
  var voiceName: String
  var endpointURL: URL
  var origin: String
  var userAgent: String
  var outputFormat: String

  init(
    requestId: String,
    text: String,
    voiceName: String,
    endpointURL: URL,
    origin: String,
    userAgent: String,
    outputFormat: String = VoiceMicrosoftEdgeTTSWire.defaultOutputFormat
  ) {
    self.requestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    self.voiceName = voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.endpointURL = endpointURL
    self.origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
    self.userAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
    self.outputFormat = outputFormat.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct VoiceMicrosoftEdgeTTSResult: Equatable {
  var request: VoiceMicrosoftEdgeTTSRequest
  var audioData: Data
}

enum VoiceMicrosoftEdgeTTSError: Error, LocalizedError, Equatable {
  case blankText
  case invalidEndpoint
  case runtimeUnavailable
  case timedOut
  case emptyAudio

  var errorDescription: String? {
    switch self {
    case .blankText:
      return "Microsoft Edge TTS requires spoken text."
    case .invalidEndpoint:
      return "Microsoft Edge TTS endpoint could not be created."
    case .runtimeUnavailable:
      return "Microsoft Edge TTS is unavailable on this device."
    case .timedOut:
      return "Microsoft Edge TTS timed out."
    case .emptyAudio:
      return "Microsoft Edge TTS returned empty audio."
    }
  }
}

protocol VoiceMicrosoftEdgeTTSSynthesizing {
  func synthesize(
    _ request: VoiceMicrosoftEdgeTTSRequest,
    trace: @escaping VoiceMicrosoftEdgeTTSTraceRecorder
  ) async throws -> Data
}
