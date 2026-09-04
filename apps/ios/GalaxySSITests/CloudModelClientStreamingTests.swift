import XCTest
@testable import GalaxySSI

final class CloudModelClientStreamingTests: XCTestCase {
  func testOpenAICompatibleStreamingRequestUsesBearerHeadersAndStreamBody() throws {
    let request = try CloudModelClient().conversationStreamingRequest(
      model: model(apiStyle: .openAICompatible),
      apiKey: "sk-live",
      turns: [
        ChatMessage(contactId: "contact", content: "hidden", isMine: true, isSystem: true),
        ChatMessage(contactId: "contact", content: "hello", isMine: true),
        ChatMessage(contactId: "contact", content: "answer", isMine: false)
      ],
      systemPrompt: "system",
      requestId: " request-1 "
    )
    let body = try object(request.bodyJson)
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

    XCTAssertEqual(request.requestId, "request-1")
    XCTAssertEqual(request.provider, .openAICompatible)
    XCTAssertEqual(request.transport, .sse)
    XCTAssertEqual(request.headers["Authorization"], "Bearer sk-live")
    XCTAssertEqual(body["model"] as? String, "model-id")
    XCTAssertEqual(body["stream"] as? Bool, true)
    XCTAssertEqual(body["tool_choice"] as? String, "auto")
    XCTAssertFalse((body["tools"] as? [[String: Any]])?.isEmpty ?? true)
    XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant"])
    XCTAssertEqual(messages.compactMap { $0["content"] as? String }, ["system", "hello", "answer"])
  }

  func testOpenRouterStreamingRequestCarriesCompatibilityHeaders() throws {
    let request = try CloudModelClient().conversationStreamingRequest(
      model: model(
        endpoint: "https://openrouter.ai/api/v1/chat/completions",
        apiStyle: .openAICompatible
      ),
      apiKey: "sk-openrouter",
      turns: [],
      systemPrompt: "system",
      requestId: "openrouter"
    )

    XCTAssertEqual(request.headers["Authorization"], "Bearer sk-openrouter")
    XCTAssertEqual(request.headers["HTTP-Referer"], "https://galaxyssi.local")
    XCTAssertEqual(request.headers["X-Title"], "GalaxySSI")
  }

  func testAnthropicStreamingRequestEnablesStreamAndHeaders() throws {
    let request = try CloudModelClient().conversationStreamingRequest(
      model: model(endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
      apiKey: "sk-anthropic",
      turns: [ChatMessage(contactId: "contact", content: "hello", isMine: true)],
      systemPrompt: "system",
      requestId: "anthropic"
    )
    let body = try object(request.bodyJson)
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

    XCTAssertEqual(request.provider, .anthropic)
    XCTAssertEqual(request.headers["x-api-key"], "sk-anthropic")
    XCTAssertEqual(request.headers["anthropic-version"], "2023-06-01")
    XCTAssertEqual(request.headers["anthropic-dangerous-direct-browser-access"], "true")
    XCTAssertEqual(body["system"] as? String, "system")
    XCTAssertEqual(body["stream"] as? Bool, true)
    XCTAssertNotNil((body["tools"] as? [[String: Any]])?.first?["input_schema"])
    XCTAssertEqual(messages.first?["role"] as? String, "user")
    XCTAssertEqual(messages.first?["content"] as? String, "hello")
  }

  func testGeminiStreamingRequestUsesStreamEndpointAndSSE() throws {
    let request = try CloudModelClient().conversationStreamingRequest(
      model: model(
        endpoint: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent",
        apiStyle: .gemini
      ),
      apiKey: "gemini key",
      turns: [ChatMessage(contactId: "contact", content: "hello", isMine: true)],
      systemPrompt: "system",
      requestId: "gemini"
    )
    let body = try object(request.bodyJson)
    let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
    let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])

    XCTAssertEqual(request.provider, .gemini)
    XCTAssertTrue(request.endpoint.contains(":streamGenerateContent"))
    XCTAssertTrue(request.endpoint.contains("key=gemini%20key"))
    XCTAssertTrue(request.endpoint.contains("alt=sse"))
    XCTAssertTrue(request.headers.isEmpty)
    XCTAssertNil(body["stream"])
    XCTAssertFalse((body["tools"] as? [[String: Any]])?.isEmpty ?? true)
    XCTAssertEqual(generationConfig["temperature"] as? Double, 0.7)
    XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 1200)
    XCTAssertEqual(contents.first?["role"] as? String, "user")
  }

  func testStreamingRequestKeepsVisibleTurnsWithinContextBudget() throws {
    let turns = (0..<20).map {
      ChatMessage(contactId: "contact", content: "turn-\($0)", isMine: $0.isMultiple(of: 2))
    }
    let request = try CloudModelClient().conversationStreamingRequest(
      model: model(apiStyle: .openAICompatible),
      apiKey: "sk-live",
      turns: turns,
      systemPrompt: "system",
      requestId: "history"
    )
    let body = try object(request.bodyJson)
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

    XCTAssertEqual(messages.count, 21)
    XCTAssertEqual(messages.first?["content"] as? String, "system")
    XCTAssertEqual(messages.dropFirst().first?["content"] as? String, "turn-0")
    XCTAssertEqual(messages.last?["content"] as? String, "turn-19")
  }

  func testStreamingRequestRejectsNonLocalPlainHttpEndpoint() {
    XCTAssertThrowsError(
      try CloudModelClient().conversationStreamingRequest(
        model: model(endpoint: "http://api.example.test/v1/chat/completions", apiStyle: .openAICompatible),
        apiKey: "sk-live",
        turns: [],
        systemPrompt: "system",
        requestId: "bad"
      )
    )
  }

  private func model(
    endpoint: String = "https://api.example.test/v1/chat/completions",
    apiStyle: GalaxySSICloudAPIStyle
  ) -> CloudModelConfig {
    CloudModelConfig(
      id: "model",
      displayName: "Model",
      provider: "Provider",
      modelId: "model-id",
      endpoint: endpoint,
      apiStyle: apiStyle,
      keychainAccount: "model",
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func object(_ bodyJson: String) throws -> [String: Any] {
    let data = try XCTUnwrap(bodyJson.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
