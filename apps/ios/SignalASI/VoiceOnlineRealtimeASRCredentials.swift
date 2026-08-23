import Foundation

enum VoiceOnlineRealtimeASRError: LocalizedError {
  case brokerNotConfigured
  case insecureEndpoint
  case invalidResponse
  case credentialExpired
  case network(String)

  var errorDescription: String? {
    switch self {
    case .brokerNotConfigured:
      return "Realtime ASR credential broker is not configured."
    case .insecureEndpoint:
      return "Realtime ASR requires secure HTTPS and WebSocket endpoints."
    case .invalidResponse:
      return "Realtime ASR returned an invalid response."
    case .credentialExpired:
      return "Realtime ASR credential expires too soon."
    case .network(let message):
      return message.ifBlank("Realtime ASR network request failed.")
    }
  }
}

enum VoiceOnlineRealtimeASRConfiguration {
  static let infoPlistKey = "SignalASIRealtimeASRCredentialBrokerURL"
  static let buildSetting = "SIGNALASI_REALTIME_ASR_CREDENTIAL_BROKER_URL"

  static var brokerURL: URL? {
    let candidates = [
      ProcessInfo.processInfo.environment[buildSetting],
      Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
    ]
    for candidate in candidates {
      let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !value.isEmpty, !value.contains("$("), let url = URL(string: value) else { continue }
      if url.scheme?.lowercased() == "https" || url.isLoopbackHTTP {
        return url
      }
    }
    return nil
  }

  static var isConfigured: Bool { brokerURL != nil }
}

final class VoiceOnlineRealtimeASRCredential {
  let providerID: String
  let providerSessionID: String
  let webSocketURL: URL
  let authorizationHeader: String
  let authorizationScheme: String
  let expiresAtMillis: Int64
  let serverDataDeletionSupported: Bool
  private var token: Data

  init(
    providerID: String,
    providerSessionID: String,
    webSocketURL: URL,
    token: String,
    authorizationHeader: String,
    authorizationScheme: String,
    expiresAtMillis: Int64,
    serverDataDeletionSupported: Bool
  ) throws {
    guard webSocketURL.scheme?.lowercased() == "wss" || webSocketURL.isLoopbackWebSocket else {
      throw VoiceOnlineRealtimeASRError.insecureEndpoint
    }
    guard !providerID.isBlank, !providerSessionID.isBlank, !token.isBlank else {
      throw VoiceOnlineRealtimeASRError.invalidResponse
    }
    self.providerID = providerID
    self.providerSessionID = providerSessionID
    self.webSocketURL = webSocketURL
    self.token = Data(token.utf8)
    self.authorizationHeader = authorizationHeader.ifBlank("Authorization")
    self.authorizationScheme = authorizationScheme
    self.expiresAtMillis = expiresAtMillis
    self.serverDataDeletionSupported = serverDataDeletionSupported
  }

  var authorizationValue: String {
    let secret = String(decoding: token, as: UTF8.self)
    let scheme = authorizationScheme.trimmingCharacters(in: .whitespacesAndNewlines)
    return scheme.isEmpty ? secret : "\(scheme) \(secret)"
  }

  func expires(within milliseconds: Int64) -> Bool {
    expiresAtMillis - Int64(Date().timeIntervalSince1970 * 1_000) <= milliseconds
  }

  func clear() {
    token.resetBytes(in: token.startIndex..<token.endIndex)
    token.removeAll(keepingCapacity: false)
  }

  deinit { clear() }
}

struct VoiceOnlineRealtimeASRCredentialSource {
  var session: URLSession = .shared

  func issue(config: VoiceOnlineRealtimeASRConfig) async throws -> VoiceOnlineRealtimeASRCredential {
    guard let brokerURL = VoiceOnlineRealtimeASRConfiguration.brokerURL else {
      throw VoiceOnlineRealtimeASRError.brokerNotConfigured
    }
    var request = URLRequest(url: brokerURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "schema_version": 1,
      "voice_session_id": config.voiceSessionID,
      "transcript_id": config.transcriptID,
      "language": config.language,
      "sample_rate_hz": VoiceOnlineRealtimeASRProtocol.sampleRateHz,
      "channel_count": 1,
      "request_server_data_deletion": config.requestServerDataDeletion
    ])
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw VoiceOnlineRealtimeASRError.network(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let webSocketURL = URL(string: json.string("websocket_url")) else {
      throw VoiceOnlineRealtimeASRError.invalidResponse
    }
    let credential = try VoiceOnlineRealtimeASRCredential(
      providerID: json.string("provider_id"),
      providerSessionID: json.string("provider_session_id"),
      webSocketURL: webSocketURL,
      token: json.string("access_token"),
      authorizationHeader: json.string("authorization_header").ifBlank("Authorization"),
      authorizationScheme: json.string("authorization_scheme").ifBlank("Bearer"),
      expiresAtMillis: json.number("expires_at_epoch_ms")?.int64Value ?? 0,
      serverDataDeletionSupported: json["server_data_deletion_supported"] as? Bool ?? false
    )
    guard !credential.expires(within: 5_000) else {
      credential.clear()
      throw VoiceOnlineRealtimeASRError.credentialExpired
    }
    return credential
  }
}

private extension URL {
  var isLoopbackHTTP: Bool {
    scheme?.lowercased() == "http" && ["127.0.0.1", "localhost", "::1"].contains(host?.lowercased() ?? "")
  }

  var isLoopbackWebSocket: Bool {
    scheme?.lowercased() == "ws" && ["127.0.0.1", "localhost", "::1"].contains(host?.lowercased() ?? "")
  }
}

private extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) -> String {
    (self[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func number(_ key: String) -> NSNumber? { self[key] as? NSNumber }
}
