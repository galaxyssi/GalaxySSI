import Foundation

final class URLSessionVoiceMicrosoftEdgeTTSSynthesizer: VoiceMicrosoftEdgeTTSSynthesizing {
  private let session: URLSession
  private let timeoutNanoseconds: UInt64

  init(
    session: URLSession = .shared,
    timeoutNanoseconds: UInt64 = 30_000_000_000
  ) {
    self.session = session
    self.timeoutNanoseconds = timeoutNanoseconds
  }

  func synthesize(
    _ request: VoiceMicrosoftEdgeTTSRequest,
    trace: @escaping VoiceMicrosoftEdgeTTSTraceRecorder
  ) async throws -> Data {
    var urlRequest = URLRequest(url: request.endpointURL)
    urlRequest.setValue(request.origin, forHTTPHeaderField: "Origin")
    urlRequest.setValue(request.userAgent, forHTTPHeaderField: "User-Agent")

    let task = session.webSocketTask(with: urlRequest)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    trace(VoiceTraceEvents.ttsConnected, ["tts_provider": VoiceTTSProvider.microsoftEdge.rawValue], true)
    try await task.send(.string(VoiceMicrosoftEdgeTTSWire.speechConfigMessage(request: request)))
    try await task.send(.string(VoiceMicrosoftEdgeTTSWire.ssmlMessage(request: request, language: request.languageTag)))

    var audio = Data()
    var recordedFirstAudio = false
    while true {
      let message = try await receive(task)
      switch message {
      case .data(let data):
        let payload = VoiceMicrosoftEdgeTTSWire.audioPayload(from: data)
        if !payload.isEmpty {
          audio.append(payload)
          if !recordedFirstAudio {
            trace(VoiceTraceEvents.ttsFirstAudio, ["tts_provider": VoiceTTSProvider.microsoftEdge.rawValue], true)
            recordedFirstAudio = true
          }
        }
      case .string(let text):
        if text.range(of: "Path:turn.end", options: .caseInsensitive) != nil {
          guard !audio.isEmpty else { throw VoiceMicrosoftEdgeTTSError.emptyAudio }
          return audio
        }
      @unknown default:
        continue
      }
    }
  }

  private func receive(_ task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
    try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
      group.addTask { try await task.receive() }
      group.addTask {
        try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
        throw VoiceMicrosoftEdgeTTSError.timedOut
      }
      guard let message = try await group.next() else {
        throw VoiceMicrosoftEdgeTTSError.timedOut
      }
      group.cancelAll()
      return message
    }
  }
}

private extension VoiceMicrosoftEdgeTTSRequest {
  var languageTag: String {
    let components = voiceName.split(separator: "-")
    guard components.count >= 2 else { return LanguagePolicySettings.resolve(LanguagePolicySettings.auto) }
    return components.prefix(2).joined(separator: "-")
  }
}
