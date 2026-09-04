import Foundation

struct CloudHTTPFailure: Error, Equatable {
  var statusCode: Int
  var responseBody: String
}

enum CloudContextOverflowPolicy {
  static func isContextOverflow(_ error: CloudHTTPFailure) -> Bool {
    isContextOverflow(statusCode: error.statusCode, responseBody: error.responseBody)
  }

  static func isContextOverflow(statusCode: Int, responseBody: String) -> Bool {
    guard [400, 413, 422].contains(statusCode) else { return false }
    let detail = responseBody.lowercased()
    if overflowMarkers.contains(where: detail.contains) {
      return true
    }
    return statusCode == 413 &&
      (detail.contains("request too large") || detail.contains("payload too large"))
  }

  static func retryWindows(configuredWindowTokens: Int) -> [Int] {
    let configured = max(configuredWindowTokens, minimumRetryWindowTokens)
    var windows: [Int] = []
    var candidate = configured
    for _ in 0..<maximumAttempts {
      if !windows.contains(candidate) {
        windows.append(candidate)
      }
      candidate = max(candidate / 2, minimumRetryWindowTokens)
    }
    return windows
  }

  private static let minimumRetryWindowTokens = 4_096
  private static let maximumAttempts = 4
  private static let overflowMarkers = [
    "context_length_exceeded",
    "maximum context length",
    "context window",
    "too many tokens",
    "token limit",
    "prompt is too long",
    "prompt too long",
    "input is too long",
    "input too long",
    "input token count",
    "exceeds the maximum number of tokens",
    "exceeds maximum token",
    "reduce the length of the messages",
    "reduce your prompt"
  ]
}

struct CloudModelClient {
  func send(contact: SignalASIContact, store: SignalASIStore, turns: [ChatMessage]) async throws -> String {
    try await send(contact: contact, store: store, turns: turns, images: [])
  }

  func send(
    contact: SignalASIContact,
    store: SignalASIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload]
  ) async throws -> String {
    try await CloudConversationNonStreamingToolEngine(modelClient: self).reply(
      contact: contact,
      store: store,
      turns: turns,
      images: images,
      requestId: UUID().uuidString
    )
  }

  func sendStructured(
    contact: SignalASIContact,
    store: SignalASIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String {
    guard let model = contact.selectedCloudModel else {
      throw SignalASIError.missingCloudModel
    }
    guard let apiKey = await store.apiKey(for: model),
          CloudModelCredentialPolicy.isStoredCredential(apiKey) else {
      throw SignalASIError.missingAPIKey
    }
    let turns = [
      ChatMessage(contactId: contact.id, content: prompt, isMine: true)
    ]
    switch model.apiStyle {
    case .anthropic:
      return try await sendAnthropic(model: model, apiKey: apiKey, turns: turns, systemPrompt: systemPrompt)
    case .gemini:
      return try await sendGemini(model: model, apiKey: apiKey, turns: turns, systemPrompt: systemPrompt)
    case .openAICompatible:
      return try await sendOpenAICompatible(model: model, apiKey: apiKey, turns: turns, systemPrompt: systemPrompt)
    }
  }

  static func systemPrompt(languagePolicy: LanguagePolicySettings) -> String {
    let responseLanguage = LanguagePolicySettings.modelLanguageName(languagePolicy.responseLanguage)
    return "\(baseSystemPrompt) Reply in \(responseLanguage) unless the user explicitly asks for another language."
  }

  private func sendOpenAICompatible(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    try await withContextOverflowRetry(model: model, apiKey: apiKey) { contextWindow, _ in
      try await sendOpenAICompatibleAttempt(
        model: model,
        apiKey: apiKey,
        turns: turns,
        systemPrompt: systemPrompt,
        contextWindowTokens: contextWindow,
        images: images
      )
    }
  }

  private func sendOpenAICompatibleAttempt(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    contextWindowTokens: Int,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    let context = CloudModelConversationContext.prepare(
      model: model,
      apiKey: apiKey,
      turns: turns,
      systemPrompt: systemPrompt,
      contextWindowTokens: contextWindowTokens
    )
    var request = try jsonRequest(url: model.endpoint, apiKey: apiKey)
    var messages: [[String: Any]] = [
      ["role": "system", "content": context.systemPrompt]
    ]
    messages.append(contentsOf: context.turns.filter { !$0.isSystem }.map {
      ["role": $0.isMine ? "user" : "assistant", "content": $0.content] as [String: Any]
    })
    CloudVisionPayloadEncoder.attachOpenAI(to: &messages, images: images)
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "model": model.modelId,
      "messages": messages,
      "stream": false
    ])
    let object = try await responseObject(for: request, throwHTTPFailure: true)
    if let choices = object["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any],
       let content = message["content"] as? String {
      return content
    }
    if let outputText = object["output_text"] as? String {
      return outputText
    }
    throw SignalASIError.unsupportedResponse
  }

  private func sendAnthropic(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    try await withContextOverflowRetry(model: model, apiKey: apiKey) { contextWindow, _ in
      try await sendAnthropicAttempt(
        model: model,
        apiKey: apiKey,
        turns: turns,
        systemPrompt: systemPrompt,
        contextWindowTokens: contextWindow,
        images: images
      )
    }
  }

  private func sendAnthropicAttempt(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    contextWindowTokens: Int,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    let context = CloudModelConversationContext.prepare(
      model: model,
      apiKey: apiKey,
      turns: turns,
      systemPrompt: systemPrompt,
      contextWindowTokens: contextWindowTokens
    )
    guard let url = URL(string: model.endpoint) else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    var messages = context.turns.filter { !$0.isSystem }.map {
      ["role": $0.isMine ? "user" : "assistant", "content": $0.content] as [String: Any]
    }
    CloudVisionPayloadEncoder.attachAnthropic(to: &messages, images: images)
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "model": model.modelId,
      "system": context.systemPrompt,
      "max_tokens": 1200,
      "messages": messages
    ])
    let object = try await responseObject(for: request, throwHTTPFailure: true)
    if let blocks = object["content"] as? [[String: Any]] {
      let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
      if !text.isEmpty { return text }
    }
    throw SignalASIError.unsupportedResponse
  }

  private func sendGemini(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    try await withContextOverflowRetry(model: model, apiKey: apiKey) { contextWindow, _ in
      try await sendGeminiAttempt(
        model: model,
        apiKey: apiKey,
        turns: turns,
        systemPrompt: systemPrompt,
        contextWindowTokens: contextWindow,
        images: images
      )
    }
  }

  private func sendGeminiAttempt(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    contextWindowTokens: Int,
    images: [CloudImagePayload] = []
  ) async throws -> String {
    let context = CloudModelConversationContext.prepare(
      model: model,
      apiKey: apiKey,
      turns: turns,
      systemPrompt: systemPrompt,
      contextWindowTokens: contextWindowTokens
    )
    var components = URLComponents(string: model.endpoint)
    var items = components?.queryItems ?? []
    items.append(URLQueryItem(name: "key", value: apiKey))
    components?.queryItems = items
    guard let url = components?.url else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var contents = context.turns.filter { !$0.isSystem }.map {
      [
        "role": $0.isMine ? "user" : "model",
        "parts": [["text": $0.content]]
      ] as [String: Any]
    }
    CloudVisionPayloadEncoder.attachGemini(to: &contents, images: images)
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "system_instruction": ["parts": [["text": context.systemPrompt]]],
      "contents": contents,
      "generationConfig": ["temperature": 0.1, "maxOutputTokens": 1200]
    ])
    let object = try await responseObject(for: request, throwHTTPFailure: true)
    if let candidates = object["candidates"] as? [[String: Any]],
       let content = candidates.first?["content"] as? [String: Any],
       let parts = content["parts"] as? [[String: Any]] {
      let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
      if !text.isEmpty { return text }
    }
    throw SignalASIError.unsupportedResponse
  }

  func jsonRequest(url: String, apiKey: String) throws -> URLRequest {
    guard let endpoint = URL(string: url) else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    if url.localizedCaseInsensitiveContains("openrouter.ai") {
      request.setValue("https://signalasi.local", forHTTPHeaderField: "HTTP-Referer")
      request.setValue("SignalASI", forHTTPHeaderField: "X-Title")
    }
    return request
  }

  func responseObject(for request: URLRequest, throwHTTPFailure: Bool = false) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      let body = String(data: data, encoding: .utf8) ?? ""
      if throwHTTPFailure {
        throw CloudHTTPFailure(statusCode: http.statusCode, responseBody: body)
      }
      if CloudContextOverflowPolicy.isContextOverflow(statusCode: http.statusCode, responseBody: body) {
        throw SignalASIError.invalidPayload("Cloud request exceeded the model context window. Try a shorter chat history or smaller attachment.")
      }
      throw SignalASIError.invalidPayload("Cloud request failed with \(http.statusCode): \(body.prefix(240))")
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SignalASIError.unsupportedResponse
    }
    return object
  }

  private static var baseSystemPrompt: String {
    "You are SignalASI, a private superintelligence interface. Be concise, useful, and preserve user privacy. When a response benefits from structure, use clear sections, tables, or code blocks."
  }
}
