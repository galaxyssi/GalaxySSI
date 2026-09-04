import Foundation

final class URLSessionVoiceMicrosoftEdgeTTSSynthesizer: VoiceMicrosoftEdgeTTSSynthesizing {
  private let session: URLSession
  private let timeoutNanoseconds: UInt64
  private let clockLock = NSLock()
  private var clockSkewSeconds: TimeInterval = 0

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
    var lastError: Error?
    for attempt in 0..<2 {
      let effectiveRequest = try request.rebased(to: correctedDate())
      do {
        return try await synthesizeOnce(effectiveRequest, trace: trace)
      } catch let error as VoiceMicrosoftEdgeTTSHandshakeError {
        lastError = error
        guard attempt == 0, error.statusCode == 403, adjustClockSkew(error.serverDate) else {
          throw error
        }
      }
    }
    throw lastError ?? VoiceMicrosoftEdgeTTSError.runtimeUnavailable
  }

  private func synthesizeOnce(
    _ request: VoiceMicrosoftEdgeTTSRequest,
    trace: @escaping VoiceMicrosoftEdgeTTSTraceRecorder
  ) async throws -> Data {
    var urlRequest = URLRequest(url: request.endpointURL)
    VoiceMicrosoftEdgeTTSWire.requestHeaders(muid: request.muid).forEach {
      urlRequest.setValue($0.value, forHTTPHeaderField: $0.key)
    }

    let task = session.webSocketTask(with: urlRequest)
    task.resume()
    defer { task.cancel(with: .goingAway, reason: nil) }

    do {
      try await task.send(.string(VoiceMicrosoftEdgeTTSWire.speechConfigMessage(request: request)))
      try await task.send(.string(VoiceMicrosoftEdgeTTSWire.ssmlMessage(request: request, language: request.languageTag)))
    } catch {
      throw handshakeError(task: task, underlying: error)
    }
    trace(
      VoiceTraceEvents.ttsConnected,
      [
        "tts_provider": VoiceTTSProvider.microsoftEdge.rawValue,
        "http_status": String((task.response as? HTTPURLResponse)?.statusCode ?? 101),
      ],
      true
    )

    var audio = Data()
    var recordedFirstAudio = false
    while true {
      let message: URLSessionWebSocketTask.Message
      do {
        message = try await receive(task)
      } catch {
        throw handshakeError(task: task, underlying: error)
      }
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

  private func correctedDate() -> Date {
    clockLock.lock()
    defer { clockLock.unlock() }
    return Date().addingTimeInterval(clockSkewSeconds)
  }

  private func adjustClockSkew(_ serverDate: String?) -> Bool {
    guard let serverDate,
          let date = Self.httpDateFormatter.date(from: serverDate) else {
      return false
    }
    clockLock.lock()
    clockSkewSeconds = date.timeIntervalSinceNow
    clockLock.unlock()
    return true
  }

  private func handshakeError(task: URLSessionWebSocketTask, underlying: Error) -> Error {
    guard let response = task.response as? HTTPURLResponse,
          response.statusCode >= 400 else {
      return underlying
    }
    return VoiceMicrosoftEdgeTTSHandshakeError(
      statusCode: response.statusCode,
      serverDate: response.value(forHTTPHeaderField: "Date"),
      underlying: underlying
    )
  }

  private static let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    return formatter
  }()

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

private struct VoiceMicrosoftEdgeTTSHandshakeError: Error, LocalizedError {
  var statusCode: Int
  var serverDate: String?
  var underlying: Error

  var errorDescription: String? {
    "Microsoft Edge TTS handshake failed: HTTP \(statusCode)"
  }
}

private extension VoiceMicrosoftEdgeTTSRequest {
  var languageTag: String {
    let components = voiceName.split(separator: "-")
    guard components.count >= 2 else { return LanguagePolicySettings.resolve(LanguagePolicySettings.auto) }
    return components.prefix(2).joined(separator: "-")
  }
}
