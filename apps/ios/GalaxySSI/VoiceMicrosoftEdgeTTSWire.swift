import Foundation

enum VoiceMicrosoftEdgeTTSWire {
  static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
  static let host = "speech.platform.bing.com"
  static let path = "/consumer/speech/synthesize/readaloud/edge/v1"
  static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
  static let userAgent = "Mozilla/5.0 GalaxySSI iOS"
  static let defaultOutputFormat = "audio-24khz-48kbitrate-mono-mp3"

  static func request(
    text: String,
    voiceName: String,
    requestId: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
  ) throws -> VoiceMicrosoftEdgeTTSRequest {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { throw VoiceMicrosoftEdgeTTSError.blankText }
    guard let endpointURL = endpointURL(requestId: requestId) else {
      throw VoiceMicrosoftEdgeTTSError.invalidEndpoint
    }
    return VoiceMicrosoftEdgeTTSRequest(
      requestId: requestId,
      text: trimmedText,
      voiceName: voiceName,
      endpointURL: endpointURL,
      origin: origin,
      userAgent: userAgent
    )
  }

  static func endpointURL(requestId: String) -> URL? {
    var components = URLComponents()
    components.scheme = "wss"
    components.host = host
    components.path = path
    components.queryItems = [
      URLQueryItem(name: "TrustedClientToken", value: trustedClientToken),
      URLQueryItem(name: "ConnectionId", value: requestId.trimmingCharacters(in: .whitespacesAndNewlines)),
    ]
    return components.url
  }

  static func speechConfigMessage(
    request: VoiceMicrosoftEdgeTTSRequest,
    timestamp: String = timestamp()
  ) -> String {
    let body = #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":false,"wordBoundaryEnabled":false},"outputFormat":"\#(request.outputFormat)"}}}}"#
    return headers(
      timestamp: timestamp,
      contentType: "application/json; charset=utf-8",
      path: "speech.config",
      requestId: request.requestId
    ) + body
  }

  static func ssmlMessage(
    request: VoiceMicrosoftEdgeTTSRequest,
    timestamp: String = timestamp(),
    language: String = LanguagePolicySettings.resolve(LanguagePolicySettings.auto)
  ) -> String {
    let ssml = #"<speak version="1.0" xml:lang="\#(language)"><voice name="\#(request.voiceName)">\#(escapeSSML(request.text))</voice></speak>"#
    return headers(
      timestamp: timestamp,
      contentType: "application/ssml+xml",
      path: "ssml",
      requestId: request.requestId
    ) + ssml
  }

  static func audioPayload(from raw: Data) -> Data {
    let bytes = [UInt8](raw)
    guard bytes.count >= 4 else { return raw }
    for index in 0...(bytes.count - 4) {
      if bytes[index] == 13,
         bytes[index + 1] == 10,
         bytes[index + 2] == 13,
         bytes[index + 3] == 10 {
        return Data(bytes[(index + 4)...])
      }
    }
    return raw
  }

  static func timestamp(date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"
    return formatter.string(from: date)
  }

  static func escapeSSML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func headers(
    timestamp: String,
    contentType: String,
    path: String,
    requestId: String
  ) -> String {
    "X-Timestamp:\(timestamp)\r\n" +
      "Content-Type:\(contentType)\r\n" +
      "Path:\(path)\r\n" +
      "X-RequestId:\(requestId)\r\n\r\n"
  }
}
