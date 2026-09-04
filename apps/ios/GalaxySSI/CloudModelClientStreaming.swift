import Foundation

extension CloudModelClient {
  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload] = [],
    requestId: String = UUID().uuidString,
    streamClient: CloudModelStreamClient = URLSessionCloudModelStreamClient()
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    let normalizedRequestId = Self.normalizedStreamRequestId(requestId)
    return streamPreparedRequest(requestId: normalizedRequestId, streamClient: streamClient) {
      try await prepareConversationStreamRequest(
        contact: contact,
        store: store,
        turns: turns,
        requestId: normalizedRequestId,
        images: images
      )
    }
  }

  func streamStructured(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    systemPrompt: String,
    prompt: String,
    requestId: String = UUID().uuidString,
    streamClient: CloudModelStreamClient = URLSessionCloudModelStreamClient()
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    let normalizedRequestId = Self.normalizedStreamRequestId(requestId)
    return streamPreparedRequest(requestId: normalizedRequestId, streamClient: streamClient) {
      try await prepareStructuredStreamRequest(
        contact: contact,
        store: store,
        systemPrompt: systemPrompt,
        prompt: prompt,
        requestId: normalizedRequestId
      )
    }
  }

  private func streamPreparedRequest(
    requestId: String,
    streamClient: CloudModelStreamClient,
    prepare: @escaping () async throws -> ModelStreamRequest
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let worker = Task {
        do {
          let request = try await prepare()
          for try await event in streamClient.stream(request) {
            continuation.yield(event)
          }
          continuation.finish()
        } catch is CancellationError {
          await streamClient.cancel(requestId: requestId, reason: .userStop)
          continuation.finish()
        } catch {
          continuation.yield(Self.failedStreamEvent(requestId: requestId, error: error))
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in
        worker.cancel()
        Task {
          await streamClient.cancel(requestId: requestId, reason: .userStop)
        }
      }
    }
  }

  func prepareConversationStreamRequest(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    requestId: String,
    images: [CloudImagePayload] = []
  ) async throws -> ModelStreamRequest {
    guard let model = contact.selectedCloudModel else {
      throw GalaxySSIError.missingCloudModel
    }
    guard let apiKey = await store.apiKey(for: model),
          CloudModelCredentialPolicy.isStoredCredential(apiKey) else {
      throw GalaxySSIError.missingAPIKey
    }
    let languagePolicy = await store.languagePolicy
    let systemPrompt = Self.systemPrompt(languagePolicy: languagePolicy) + "\n" + CloudWebGrounding.currentEvidencePrompt()
    return try conversationStreamingRequest(
      model: model,
      apiKey: apiKey,
      turns: turns,
      systemPrompt: systemPrompt,
      requestId: requestId,
      images: images
    )
  }

  func prepareStructuredStreamRequest(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    systemPrompt: String,
    prompt: String,
    requestId: String
  ) async throws -> ModelStreamRequest {
    guard let model = contact.selectedCloudModel else {
      throw GalaxySSIError.missingCloudModel
    }
    guard let apiKey = await store.apiKey(for: model),
          CloudModelCredentialPolicy.isStoredCredential(apiKey) else {
      throw GalaxySSIError.missingAPIKey
    }
    return try conversationStreamingRequest(
      model: model,
      apiKey: apiKey,
      turns: [ChatMessage(contactId: contact.id, content: prompt, isMine: true)],
      systemPrompt: systemPrompt,
      requestId: requestId
    )
  }

  func conversationStreamingRequest(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    requestId: String,
    images: [CloudImagePayload] = []
  ) throws -> ModelStreamRequest {
    let context = CloudModelConversationContext.prepare(
      model: model,
      apiKey: apiKey,
      turns: turns,
      systemPrompt: systemPrompt
    )
    switch model.apiStyle {
    case .anthropic:
      return try anthropicStreamingRequest(
        model: model,
        apiKey: apiKey,
        turns: context.turns,
        systemPrompt: context.systemPrompt,
        images: images,
        requestId: requestId
      )
    case .gemini:
      return try geminiStreamingRequest(
        model: model,
        apiKey: apiKey,
        turns: context.turns,
        systemPrompt: context.systemPrompt,
        images: images,
        requestId: requestId
      )
    case .openAICompatible:
      return try openAICompatibleStreamingRequest(
        model: model,
        apiKey: apiKey,
        turns: context.turns,
        systemPrompt: context.systemPrompt,
        images: images,
        requestId: requestId
      )
    }
  }

  private func openAICompatibleStreamingRequest(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload],
    requestId: String
  ) throws -> ModelStreamRequest {
    let endpoint = try Self.validStreamingEndpoint(model.endpoint)
    var messages = Self.openAIMessages(turns: turns, systemPrompt: systemPrompt)
    CloudVisionPayloadEncoder.attachOpenAI(to: &messages, images: images)
    let body = try Self.bodyJSON([
      "model": model.modelId,
      "messages": messages,
      "stream": true,
      "tools": CloudModelStreamToolSchemas.openAITools(),
      "tool_choice": "auto"
    ])
    return ModelStreamRequest(
      requestId: Self.normalizedStreamRequestId(requestId),
      provider: .openAICompatible,
      endpoint: endpoint,
      headers: Self.openAIHeaders(endpoint: endpoint, apiKey: apiKey),
      bodyJson: body,
      transport: .sse
    )
  }

  private func anthropicStreamingRequest(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload],
    requestId: String
  ) throws -> ModelStreamRequest {
    let endpoint = try Self.validStreamingEndpoint(model.endpoint)
    var messages = Self.anthropicMessages(turns: turns)
    CloudVisionPayloadEncoder.attachAnthropic(to: &messages, images: images)
    let body = try Self.bodyJSON([
      "model": model.modelId,
      "system": systemPrompt,
      "max_tokens": 1200,
      "messages": messages,
      "tools": CloudModelStreamToolSchemas.anthropicTools(),
      "stream": true
    ])
    return ModelStreamRequest(
      requestId: Self.normalizedStreamRequestId(requestId),
      provider: .anthropic,
      endpoint: endpoint,
      headers: [
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true"
      ],
      bodyJson: body,
      transport: .sse
    )
  }

  private func geminiStreamingRequest(
    model: CloudModelConfig,
    apiKey: String,
    turns: [ChatMessage],
    systemPrompt: String,
    images: [CloudImagePayload],
    requestId: String
  ) throws -> ModelStreamRequest {
    let endpoint = try Self.geminiStreamingEndpoint(endpoint: model.endpoint, apiKey: apiKey)
    var contents = Self.geminiContents(turns: turns)
    CloudVisionPayloadEncoder.attachGemini(to: &contents, images: images)
    let body = try Self.bodyJSON([
      "system_instruction": ["parts": [["text": systemPrompt]]],
      "contents": contents,
      "generationConfig": ["temperature": 0.7, "maxOutputTokens": 1200],
      "tools": CloudModelStreamToolSchemas.geminiTools()
    ])
    return ModelStreamRequest(
      requestId: Self.normalizedStreamRequestId(requestId),
      provider: .gemini,
      endpoint: endpoint,
      headers: [:],
      bodyJson: body,
      transport: .sse
    )
  }

  private static func openAIMessages(turns: [ChatMessage], systemPrompt: String) -> [[String: Any]] {
    var messages: [[String: Any]] = [
      ["role": "system", "content": systemPrompt]
    ]
    messages.append(
      contentsOf: visibleHistory(turns).map {
        ["role": $0.isMine ? "user" : "assistant", "content": $0.content]
      }
    )
    return messages
  }

  private static func anthropicMessages(turns: [ChatMessage]) -> [[String: Any]] {
    visibleHistory(turns).map {
      ["role": $0.isMine ? "user" : "assistant", "content": $0.content]
    }
  }

  private static func geminiContents(turns: [ChatMessage]) -> [[String: Any]] {
    visibleHistory(turns).map {
      [
        "role": $0.isMine ? "user" : "model",
        "parts": [["text": $0.content]]
      ] as [String: Any]
    }
  }

  private static func visibleHistory(_ turns: [ChatMessage]) -> ArraySlice<ChatMessage> {
    turns.filter { !$0.isSystem }.suffix(16)
  }

  private static func openAIHeaders(endpoint: String, apiKey: String) -> [String: String] {
    var headers = ["Authorization": "Bearer \(apiKey)"]
    if endpoint.localizedCaseInsensitiveContains("openrouter.ai") {
      headers["HTTP-Referer"] = "https://galaxyssi.local"
      headers["X-Title"] = "GalaxySSI"
    }
    return headers
  }

  private static func geminiStreamingEndpoint(endpoint: String, apiKey: String) throws -> String {
    let streaming = endpoint.replacingOccurrences(of: ":generateContent", with: ":streamGenerateContent")
    guard var components = URLComponents(string: streaming) else {
      throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var items = components.queryItems ?? []
    if !items.contains(where: { $0.name == "key" }) {
      items.append(URLQueryItem(name: "key", value: apiKey))
    }
    items.removeAll { $0.name == "alt" }
    items.append(URLQueryItem(name: "alt", value: "sse"))
    components.queryItems = items
    guard let url = components.url else {
      throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    return try validStreamingEndpoint(url.absoluteString)
  }

  private static func validStreamingEndpoint(_ endpoint: String) throws -> String {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
      throw GalaxySSIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("https://") ||
      lower.hasPrefix("http://127.0.0.1") ||
      lower.hasPrefix("http://localhost") else {
      throw GalaxySSIError.invalidPayload("Cloud streaming endpoint must use HTTPS or local HTTP.")
    }
    return trimmed
  }

  private static func bodyJSON(_ object: [String: Any]) throws -> String {
    let data = try GalaxySSILinkProtocol.jsonData(object)
    guard let body = String(data: data, encoding: .utf8) else {
      throw GalaxySSIError.invalidPayload("Cloud request body is not valid UTF-8.")
    }
    return body
  }

  private static func normalizedStreamRequestId(_ requestId: String) -> String {
    requestId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(UUID().uuidString)
  }

  private static func failedStreamEvent(requestId: String, error: Error) -> ModelStreamEvent {
    .failed(
      ModelStreamFailed(
        requestId: requestId,
        error: ModelStreamError(
          code: "STREAM_PREPARATION_FAILED",
          message: error.localizedDescription.ifBlank(String(describing: error)),
          retryable: false
        )
      )
    )
  }
}
