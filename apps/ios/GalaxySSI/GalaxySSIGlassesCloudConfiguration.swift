import Foundation

enum GalaxySSIGlassesCloudConfiguration {
  typealias Wire = GalaxySSIGlassesSetupProtocol

  struct Draft {
    var agentName = ""
    var endpoint = ""
    var modelID = ""
    var key = ""
    var style = GalaxySSICloudAPIStyle.openAICompatible

    var candidate: Candidate? {
      let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
      let id = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
      let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      let model = CloudModelConfig(id: "glasses-transfer-only", displayName: name, provider: style.rawValue,
        modelId: id, endpoint: endpoint, apiStyle: style, keychainAccount: "", updatedAt: Date(timeIntervalSince1970: 0))
      return Candidate(agentName: name, model: model, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  struct Candidate {
    let agentName: String
    let model: CloudModelConfig
    private let key: String
    let profile: Wire.Profile
    let fingerprint: String

    init?(agentName: String, model: CloudModelConfig, key: String) {
      guard CloudModelCredentialPolicy.isStoredCredential(key), key == key.trimmingCharacters(in: .whitespacesAndNewlines),
            let profile = try? Wire.Profile(agentName: agentName, model: model, key: key),
            let endpoint = URL(string: model.endpoint) else { return nil }
      if model.apiStyle == .gemini {
        let modelID = model.modelId.hasPrefix("models/") ? String(model.modelId.dropFirst(7)) : model.modelId
        guard endpoint.lastPathComponent == modelID + ":generateContent" else { return nil }
      }
      self.agentName = profile.agentName
      self.model = model
      self.key = key
      self.profile = profile
      fingerprint = AgentModelLoopRecoveryIdentity.sha256(["agent": profile.agentName, "id": model.id,
        "endpoint": model.endpoint, "model": model.modelId, "style": model.apiStyle.rawValue,
        "key": Wire.Handshake.digest(Data(key.utf8))])
    }

    func request() throws -> URLRequest {
      guard let url = URL(string: model.endpoint) else { throw Wire.Failure.invalid }
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
      let prompt = "Reply OK."
      let messages = [["role": "user", "content": prompt]]
      let body: [String: Any]
      switch model.apiStyle {
      case .anthropic:
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        body = ["model": model.modelId, "messages": messages, "max_tokens": 16]
      case .gemini:
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        body = ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["maxOutputTokens": 16]]
      case .openAICompatible:
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let host = url.host?.lowercased()
        var options: [String: Any] = ["model": model.modelId, "messages": messages, "stream": false]
        if host == "api.openai.com" {
          options["max_completion_tokens"] = 64
          options["store"] = false
        } else { options["max_tokens"] = 16 }
        if host == "api.deepseek.com" { options["thinking"] = ["type": "disabled"] }
        body = options
      }
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      return request
    }
  }

  static func probe(_ candidate: Candidate, send: ((URLRequest) async throws -> Data)? = nil) async throws {
    let request = try candidate.request()
    let response: Data
    if let send { response = try await send(request) }
    else { response = try await responseBytes(request) }
    try Task.checkCancellation()
    guard (1...32_768).contains(response.count),
          let object = try JSONSerialization.jsonObject(with: response) as? [String: Any], object["error"] == nil else {
      throw Wire.Failure.rejected
    }
    let valid: Bool
    switch candidate.model.apiStyle {
    case .openAICompatible:
      let choices = object["choices"] as? [[String: Any]]
      valid = choices?.first?["message"] is [String: Any]
    case .anthropic:
      let content = object["content"] as? [[String: Any]]
      valid = content?.contains { $0["type"] as? String == "text" && $0["text"] is String } == true
    case .gemini:
      let candidates = object["candidates"] as? [[String: Any]]
      let content = candidates?.first?["content"] as? [String: Any]
      let parts = content?["parts"] as? [[String: Any]]
      valid = parts?.contains { $0["text"] is String } == true
    }
    guard valid else { throw Wire.Failure.rejected }
  }

  private static func responseBytes(_ request: URLRequest) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 30
    let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
          response.url == request.url else { throw Wire.Failure.rejected }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 32_768 else { throw Wire.Failure.rejected }
      data.append(byte)
    }
    return data
  }

  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  }
}
