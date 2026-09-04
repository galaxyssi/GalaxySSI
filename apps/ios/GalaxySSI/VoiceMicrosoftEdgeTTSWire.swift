import CryptoKit
import Foundation

enum VoiceMicrosoftEdgeTTSWire {
  static let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
  static let host = "speech.platform.bing.com"
  static let path = "/consumer/speech/synthesize/readaloud/edge/v1"
  static let origin = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
  static let chromiumFullVersion = "143.0.3650.75"
  static let chromiumMajorVersion = "143"
  static let secMSGECVersion = "1-\(chromiumFullVersion)"
  static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromiumMajorVersion).0.0.0 Safari/537.36 Edg/\(chromiumMajorVersion).0.0.0"
  static let defaultOutputFormat = "audio-24khz-48kbitrate-mono-mp3"
  private static let windowsEpochSeconds: Int64 = 11_644_473_600
  private static let gecWindowSeconds: Int64 = 300
  private static let filetimeTicksPerSecond: Int64 = 10_000_000

  static func request(
    text: String,
    voiceName: String,
    requestId: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
    connectionId: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
    muid: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased(),
    date: Date = Date()
  ) throws -> VoiceMicrosoftEdgeTTSRequest {
    let trimmedText = sanitize(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { throw VoiceMicrosoftEdgeTTSError.blankText }
    guard let endpointURL = endpointURL(
      connectionId: connectionId,
      epochSeconds: Int64(date.timeIntervalSince1970)
    ) else {
      throw VoiceMicrosoftEdgeTTSError.invalidEndpoint
    }
    return VoiceMicrosoftEdgeTTSRequest(
      requestId: requestId,
      connectionId: connectionId,
      muid: muid,
      text: trimmedText,
      voiceName: voiceName,
      endpointURL: endpointURL,
      origin: origin,
      userAgent: userAgent,
      requestDate: date
    )
  }

  static func endpointURL(requestId: String) -> URL? {
    endpointURL(
      connectionId: requestId,
      epochSeconds: Int64(Date().timeIntervalSince1970)
    )
  }

  static func endpointURL(connectionId: String, epochSeconds: Int64) -> URL? {
    var components = URLComponents()
    components.scheme = "wss"
    components.host = host
    components.path = path
    components.queryItems = [
      URLQueryItem(name: "TrustedClientToken", value: trustedClientToken),
      URLQueryItem(name: "ConnectionId", value: connectionId.trimmingCharacters(in: .whitespacesAndNewlines)),
      URLQueryItem(name: "Sec-MS-GEC", value: secMSGEC(epochSeconds: epochSeconds)),
      URLQueryItem(name: "Sec-MS-GEC-Version", value: secMSGECVersion),
    ]
    return components.url
  }

  static func requestHeaders(muid: String) -> [String: String] {
    [
      "Pragma": "no-cache",
      "Cache-Control": "no-cache",
      "Origin": origin,
      "User-Agent": userAgent,
      "Accept-Encoding": "gzip, deflate, br, zstd",
      "Accept-Language": "en-US,en;q=0.9",
      "Cookie": "muid=\(muid);",
    ]
  }

  static func secMSGEC(epochSeconds: Int64) -> String {
    let roundedSeconds = (epochSeconds / gecWindowSeconds) * gecWindowSeconds
    let ticks = (roundedSeconds + windowsEpochSeconds) * filetimeTicksPerSecond
    let digest = SHA256.hash(data: Data("\(ticks)\(trustedClientToken)".utf8))
    return digest.map { String(format: "%02X", $0) }.joined()
  }

  static func speechConfigMessage(
    request: VoiceMicrosoftEdgeTTSRequest,
    timestamp: String? = nil
  ) -> String {
    let resolvedTimestamp = timestamp ?? self.timestamp(date: request.requestDate)
    let body = #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"true","wordBoundaryEnabled":"false"},"outputFormat":"\#(request.outputFormat)"}}}}"#
    return "X-Timestamp:\(resolvedTimestamp)\r\n" +
      "Content-Type:application/json; charset=utf-8\r\n" +
      "Path:speech.config\r\n\r\n\(body)\r\n"
  }

  static func ssmlMessage(
    request: VoiceMicrosoftEdgeTTSRequest,
    timestamp: String? = nil,
    language: String = LanguagePolicySettings.resolve(LanguagePolicySettings.auto)
  ) -> String {
    let resolvedTimestamp = timestamp ?? self.timestamp(date: request.requestDate)
    let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' " +
      "xml:lang='\(language)'><voice name='\(request.voiceName)'><prosody pitch='+0Hz' " +
      "rate='+0%' volume='+0%'>\(escapeSSML(request.text))</prosody></voice></speak>"
    return "X-RequestId:\(request.requestId)\r\n" +
      "Content-Type:application/ssml+xml\r\n" +
      "X-Timestamp:\(resolvedTimestamp)Z\r\n" +
      "Path:ssml\r\n\r\n\(ssml)"
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
    formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
    return formatter.string(from: date)
  }

  static func escapeSSML(_ value: String) -> String {
    sanitize(value)
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func sanitize(_ value: String) -> String {
    value.unicodeScalars.reduce(into: "") { result, scalar in
      let value = scalar.value
      if value <= 8 ||
          (value >= 11 && value <= 12) ||
          (value >= 14 && value <= 31) {
        result.append(" ")
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
  }
}
