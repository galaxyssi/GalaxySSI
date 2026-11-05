import XCTest
@testable import GalaxySSI

final class CloudModelClientStreamingTests: XCTestCase {
  func testHistoricalImageSurvivesToolContinuationAndNonStreamingFallback() throws {
    let bytes = Data([1, 2, 3, 4])
    let image = try CloudImagePayload(displayName: "history.png", mimeType: "image/png", data: bytes,
      historicalSourceTurnId: "original-turn")
    let styles: [GalaxySSICloudAPIStyle] = [.openAICompatible, .anthropic, .gemini]
    for style in styles {
      let initial = try CloudModelClient().conversationStreamingRequest(
        model: model(apiStyle: style), apiKey: "fixture",
        turns: [ChatMessage(contactId: "contact", content: "Latest question", isMine: true)],
        systemPrompt: "system", requestId: "initial", images: [image])
      var conversation = try CloudModelStreamMutableConversation(request: initial)
      let call = AssembledToolCall(callId: "call-1", index: 0, name: "web_search", argumentsJson: "{}")
      try conversation.appendToolResults([(call, "fixture result")])
      let next = try conversation.requestForRound(roundId: "continuation")
      let encoded = try CloudConversationNonStreamingToolEngine.compatibilityBody(next.bodyJson, provider: next.provider)
      let before = try object(initial.bodyJson)
      let after = try object(encoded)
      let key = style == .gemini ? "contents" : "messages"
      let originalMessages = try XCTUnwrap(before[key] as? [[String: Any]])
      let finalMessages = try XCTUnwrap(after[key] as? [[String: Any]])
      XCTAssertGreaterThan(finalMessages.count, originalMessages.count)
      for (original, final) in zip(originalMessages, finalMessages) {
        XCTAssertEqual(original as NSDictionary, final as NSDictionary)
      }
      XCTAssertTrue(encoded.contains("original-turn"))
      XCTAssertTrue(encoded.contains(bytes.base64EncodedString()))
      if style == .gemini { XCTAssertNil(after["stream"]) }
      else { XCTAssertEqual(after["stream"] as? Bool, false) }
    }
  }

  func testDefaultImagePromptAvoidsTextOnlyGroundingWithoutDroppingLanguageOrTools() throws {
    let language = LanguagePolicySettings(responseLanguage: "zh-CN")
    let image = try CloudImagePayload(displayName: "fixture.png", mimeType: "image/png", data: Data([1]))
    var groundingCalls = 0
    func evidence() -> String { groundingCalls += 1; return "Text-only grounding" }
    let visual = CloudModelClient.conversationSystemPrompt(languagePolicy: language, images: [image],
      textOnlyEvidence: evidence)
    XCTAssertEqual(groundingCalls, 0)
    XCTAssertTrue(visual.contains(LanguagePolicySettings.modelLanguageName("zh-CN")))
    XCTAssertTrue(visual.contains("native visual evidence"))
    XCTAssertTrue(visual.contains("without a tool result"))
    XCTAssertFalse(visual.contains("Text-only grounding"))
    let text = CloudModelClient.conversationSystemPrompt(languagePolicy: language, images: [],
      textOnlyEvidence: evidence)
    XCTAssertEqual(groundingCalls, 1)
    XCTAssertEqual(text, CloudModelClient.systemPrompt(languagePolicy: language) + "\nText-only grounding")
  }

  func testAllCloudProvidersAddVisionGuidanceToCustomImageRequestsOnly() throws {
    let styles: [GalaxySSICloudAPIStyle] = [.openAICompatible, .anthropic, .gemini]
    let bytes = Data([1, 2, 3])
    let image = try CloudImagePayload(displayName: "fixture.png", mimeType: "image/png", data: bytes)
    for style in styles {
      for images in [[image], []] {
        let request = try CloudModelClient().conversationStreamingRequest(
          model: model(apiStyle: style), apiKey: "fixture",
          turns: [ChatMessage(contactId: "contact", content: "Describe", isMine: true)],
          systemPrompt: "Custom instructions", requestId: "vision-fixture", images: images)
        let body = try object(request.bodyJson)
        let system: String?
        switch style {
        case .openAICompatible:
          system = (body["messages"] as? [[String: Any]])?.first?["content"] as? String
        case .anthropic:
          system = body["system"] as? String
        case .gemini:
          let instruction = body["system_instruction"] as? [String: Any]
          system = (instruction?["parts"] as? [[String: String]])?.first?["text"]
        }
        let prompt = try XCTUnwrap(system)
        XCTAssertTrue(prompt.hasPrefix("Custom instructions"))
        XCTAssertEqual(prompt.contains("reading orientation"), !images.isEmpty)
        XCTAssertEqual(request.bodyJson.contains(bytes.base64EncodedString()), !images.isEmpty)
      }
    }
  }

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
